import Foundation
import SwiftData

enum MacAutomaticPosting {
    private static var running = false
    static var isRunning: Bool { running }
    static func recurringDates(_ rule: RecurringTransaction, now: Date) throws -> [Date] {
        var result: [Date] = [], cursor = rule.nextExecutionDate
        while cursor <= now {
            if let end = rule.endDate, cursor > end { break }
            guard result.count < 24 else { throw MacFinanceRecords.Failure.tooManyOccurrences }
            result.append(cursor)
            cursor = try MacFinanceRecords.nextDate(cursor, value: rule.intervalValue, unit: rule.intervalUnit)
        }
        return result
    }
    static func depositDates(_ deposit: DepositRecord, now: Date) throws -> [Date] {
        if deposit.typedInterestSettlementMode != .monthly { return [deposit.maturityDate] }
        var result: [Date] = [], cursor = deposit.nextInterestPayoutDate
        while let due = cursor, Calendar.current.startOfDay(for: due) <= Calendar.current.startOfDay(for: now) {
            guard result.count < 24 else { throw MacDepositSettlement.PostingError.tooManyPeriods }
            result.append(due)
            if due >= deposit.maturityDate { break }
            cursor = min(Calendar.current.date(byAdding: .month, value: 1, to: due)!, deposit.maturityDate)
        }
        return result
    }
    static func rates(source: String, base: String, dates: [Date]) async throws -> [Int64: Double] {
        guard source != base else { return [:] }
        var result: [Int64: Double] = [:]
        for date in dates { result[Int64(date.timeIntervalSince1970)] = try await MacExchangeRates.shared.quote(from: source, to: base, on: date) }
        return result
    }
    static func post(_ rule: RecurringTransaction, now: Date, book: String, in context: ModelContext) async throws -> Int {
        let cursor = rule.nextExecutionDate, updated = rule.updatedAt, source = rule.originalCurrency
        let quotes = try await rates(source: source, base: book, dates: recurringDates(rule, now: now))
        guard cursor == rule.nextExecutionDate, updated == rule.updatedAt, source == rule.originalCurrency else { throw MacFinanceReview.Failure.schedule }
        return try MacFinanceRecords.postDue(rule: rule, transactions: [], now: now, bookCurrency: book, exchangeRates: quotes, in: context)
    }
    static func post(_ deposit: DepositRecord, now: Date, book: String, estimated: Bool = false, in context: ModelContext) async throws -> MacDepositSettlement.PostingResult {
        let cursor = deposit.nextInterestPayoutDate, updated = deposit.updatedAt, source = deposit.originalCurrency
        let quotes = try await rates(source: source, base: book, dates: depositDates(deposit, now: now))
        guard cursor == deposit.nextInterestPayoutDate, updated == deposit.updatedAt, source == deposit.originalCurrency else { throw MacFinanceReview.Failure.schedule }
        return try MacDepositSettlement.postDue(deposit, now: now, bookCurrency: book, exchangeRates: quotes, estimated: estimated, in: context)
    }
    static func run(in context: ModelContext, now: Date = Date(), includeRules: Bool = true, includeDeposits: Bool = true, estimateDeposits: Bool = false) async -> String? {
        guard !running else { return nil }
        running = true; defer { running = false }
        var failures: [String] = []
        do {
            let rules = try context.fetch(FetchDescriptor<RecurringTransaction>())
            let deposits = try context.fetch(FetchDescriptor<DepositRecord>())
            let loans = try context.fetch(FetchDescriptor<LoanRule>())
            for rule in rules where includeRules && rule.deletedAt == nil && rule.isActive && MacFinanceRecords.isManagedRecurring(rule) && rule.nextExecutionDate <= now {
                do { _ = try await post(rule, now: now, book: rule.baseCurrencyCode, in: context) }
                catch { failures.append(rule.title + ": " + MacLocalization.error(error)) }
            }
            for deposit in deposits where includeDeposits && MacDepositSettlement.isEligible(deposit, now: now) {
                do { _ = try await post(deposit, now: now, book: deposit.baseCurrencyCode, estimated: estimateDeposits, in: context) }
                catch { failures.append(deposit.bankName + ": " + MacLocalization.error(error)) }
            }
            for loan in loans where includeRules && loan.deletedAt == nil && MacLoanRepayment.isManaged(loan) && loan.generatedRules.isEmpty {
                do { _ = try await post(loan, now: now, book: loan.baseCurrencyCode, in: context) }
                catch { failures.append(loan.title + ": " + MacLocalization.error(error)) }
            }
        } catch { failures.append(MacLocalization.error(error)) }
        try? await MacNotifications.schedule(in: context)
        return failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    static func post(_ loan: LoanRule, now: Date, book: String, in context: ModelContext) async throws -> Int {
        let preview: MacLoanRepayment.Preview
        do { preview = try MacLoanRepayment.nextPayment(loan, now: now, bookCurrency: book, in: context) }
        catch MacLoanRepayment.PostingError.notDue { return 0 }
        catch MacLoanRepayment.PostingError.allPaid { return 0 }
        let source = loan.currency, updated = loan.updatedAt
        let due = loan.amortizationSchedule.filter {
            $0.index >= preview.payment.index && Calendar.current.startOfDay(for: $0.date) <= Calendar.current.startOfDay(for: now)
        }
        guard due.count <= 24 else { throw MacFinanceRecords.Failure.tooManyOccurrences }
        let quotes = try await rates(source: source, base: book, dates: due.map(\.date))
        guard source == loan.currency, updated == loan.updatedAt, loan.deletedAt == nil else { throw MacFinanceReview.Failure.schedule }
        do {
            for payment in due {
                try MacLoanRepayment.recordPaid(loan, now: now, bookCurrency: book, expectedIndex: payment.index,
                    exchangeRate: quotes[Int64(payment.date.timeIntervalSince1970)], expectedPayment: payment,
                    expectedScheduleCount: preview.totalCount, expectedOriginalCurrency: source, saveImmediately: false, in: context)
            }
            try context.save()
        } catch { context.rollback(); throw error }
        return due.count
    }
}
