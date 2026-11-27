import Foundation
import SwiftData

enum MacAutomaticPosting {
    private static var running = false
    static var isRunning: Bool { running }
    struct Issue: Identifiable {
        let section: MacWorkspaceSection?
        let recordID: UUID?
        let name: String
        let reason: String
        var advancedPeriods = 0
        var id: String { "\(section?.storageID ?? "general")-\(recordID?.uuidString ?? name)" }
    }

    static func recurringDates(_ rule: RecurringTransaction, now: Date) throws -> [Date] {
        try MacFinanceRecords.recurringBatch(rule, through: now).dates
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
        for date in dates {
            try Task.checkCancellation()
            result[Int64(date.timeIntervalSince1970)] = try await MacExchangeRates.shared.quote(from: source, to: base, on: date)
        }
        return result
    }
    static func post(_ rule: RecurringTransaction, now: Date, book: String, expectedDates: [Date]? = nil, in context: ModelContext) async throws -> Int {
        let cursor = rule.nextExecutionDate, revision = rule.syncVersion, updated = rule.updatedAt, source = rule.originalCurrency
        let dates = try recurringDates(rule, now: now)
        guard expectedDates == nil || expectedDates == dates else { throw MacFinanceReview.Failure.schedule }
        let quotes = try await rates(source: source, base: book, dates: dates)
        try Task.checkCancellation()
        guard rule.modelContext === context, rule.deletedAt == nil, rule.isActive, cursor == rule.nextExecutionDate,
              revision == rule.syncVersion, updated == rule.updatedAt, source == rule.originalCurrency,
              dates == (try recurringDates(rule, now: now)) else { throw MacFinanceReview.Failure.schedule }
        return try MacFinanceRecords.postDue(rule: rule, transactions: [], now: now, bookCurrency: book, exchangeRates: quotes, in: context)
    }
    static func post(_ deposit: DepositRecord, now: Date, book: String, scheduled: Bool = false, in context: ModelContext) async throws -> MacDepositSettlement.PostingResult {
        let cursor = deposit.nextInterestPayoutDate, updated = deposit.updatedAt, source = deposit.originalCurrency
        let quotes = try await rates(source: source, base: book, dates: depositDates(deposit, now: now))
        try Task.checkCancellation()
        guard deposit.modelContext === context, deposit.deletedAt == nil, deposit.isActive, cursor == deposit.nextInterestPayoutDate, updated == deposit.updatedAt, source == deposit.originalCurrency else { throw MacFinanceReview.Failure.schedule }
        return try MacDepositSettlement.postDue(deposit, now: now, bookCurrency: book, exchangeRates: quotes, scheduled: scheduled, in: context)
    }
    static func run(in context: ModelContext, now: Date = Date(), includeRules: Bool = true, includeDeposits: Bool = true) async -> [Issue]? {
        guard !running, !Task.isCancelled else { return nil }
        running = true
        defer { running = false }
        var issues: [Issue] = []
        do {
            let rules = try context.fetch(FetchDescriptor<RecurringTransaction>())
            let deposits = try context.fetch(FetchDescriptor<DepositRecord>())
            let loans = try context.fetch(FetchDescriptor<LoanRule>())
            for rule in rules where includeRules && MacFinanceRecords.isManagedRecurring(rule) && MacFinanceRecords.isRecurringDue(rule, through: now) {
                var advanced = 0
                do {
                    // Limit each automatic run to three commits per rule and let the main actor
                    // service input between batches. The saved cursor owns resume semantics.
                    for _ in 0..<3 where MacFinanceRecords.isRecurringDue(rule, through: now) {
                        try Task.checkCancellation()
                        advanced += try await post(rule, now: now, book: rule.baseCurrencyCode, in: context)
                        await Task.yield()
                    }
                    if MacFinanceRecords.isRecurringDue(rule, through: now) {
                        issues.append(Issue(section: .recurring, recordID: rule.id, name: rule.title,
                                            reason: L10n.text("posting.remaining"), advancedPeriods: advanced))
                    }
                } catch is CancellationError { return nil }
                catch {
                    issues.append(Issue(section: .recurring, recordID: rule.id, name: rule.title,
                                        reason: MacLocalization.error(error), advancedPeriods: advanced))
                }
            }
            if includeDeposits, let state = MacLiquidity.state(try MacLiquidity.profile(in: context)) {
                let transactions = try context.fetch(FetchDescriptor<Transaction>())
                for deposit in deposits where !deposit.isActive {
                    try Task.checkCancellation()
                    do {
                        try MacDepositSettlement.finishScheduledMaturity(
                            deposit, state: state, deposits: deposits, transactions: transactions, now: now, in: context
                        )
                    } catch { issues.append(Issue(section: .deposits, recordID: deposit.id, name: deposit.bankName, reason: MacLocalization.error(error))) }
                }
                for deposit in deposits where MacDepositSettlement.isEligible(deposit, now: now) {
                    do { _ = try await post(deposit, now: now, book: deposit.baseCurrencyCode, scheduled: true, in: context) }
                    catch is CancellationError { return nil }
                    catch { issues.append(Issue(section: .deposits, recordID: deposit.id, name: deposit.bankName, reason: MacLocalization.error(error))) }
                }
            }
            for loan in loans where includeRules && loan.deletedAt == nil && MacLoanRepayment.isManaged(loan) && loan.generatedRules.isEmpty {
                var advanced = 0
                do {
                    for _ in 0..<3 {
                        try Task.checkCancellation()
                        let count = try await post(loan, now: now, book: loan.baseCurrencyCode, in: context)
                        advanced += count
                        if count < RecurringScheduleRule.batchLimit { break }
                        await Task.yield()
                    }
                    if advanced == RecurringScheduleRule.batchLimit * 3 {
                        do {
                            _ = try MacLoanRepayment.nextPayment(loan, now: now, bookCurrency: loan.baseCurrencyCode, in: context)
                            issues.append(Issue(section: .loans, recordID: loan.id, name: loan.title,
                                                reason: L10n.text("posting.remaining"), advancedPeriods: advanced))
                        } catch MacLoanRepayment.PostingError.allPaid {
                        } catch MacLoanRepayment.PostingError.notDue {}
                    }
                } catch is CancellationError { return nil }
                catch {
                    issues.append(Issue(section: .loans, recordID: loan.id, name: loan.title,
                                        reason: MacLocalization.error(error), advancedPeriods: advanced))
                }
            }
        } catch is CancellationError { return nil }
        catch { issues.append(Issue(section: nil, recordID: nil, name: L10n.text("posting.title"), reason: MacLocalization.error(error))) }
        try? await MacNotifications.schedule(in: context)
        return issues.isEmpty ? nil : issues
    }

    static func post(_ loan: LoanRule, now: Date, book: String, in context: ModelContext) async throws -> Int {
        let preview: MacLoanRepayment.Preview
        do { preview = try MacLoanRepayment.nextPayment(loan, now: now, bookCurrency: book, in: context) }
        catch MacLoanRepayment.PostingError.notDue { return 0 }
        catch MacLoanRepayment.PostingError.allPaid { return 0 }
        let source = loan.currency, updated = loan.updatedAt
        let due = MacLoanRepayment.resolvedSchedule(loan, transactions: try context.fetch(FetchDescriptor<Transaction>())).filter {
            $0.total > 0 && $0.index >= preview.payment.index && Calendar.current.startOfDay(for: $0.date) <= Calendar.current.startOfDay(for: now)
        }
        let batch = due.prefix(RecurringScheduleRule.batchLimit)
        let quotes = try await rates(source: source, base: book, dates: batch.map(\.date))
        try Task.checkCancellation()
        guard !context.hasChanges, loan.modelContext === context, source == loan.currency, updated == loan.updatedAt, loan.deletedAt == nil else { throw MacFinanceReview.Failure.schedule }
        do {
            for payment in batch {
                try MacLoanRepayment.recordPaid(loan, now: now, bookCurrency: book, expectedIndex: payment.index,
                    exchangeRate: quotes[Int64(payment.date.timeIntervalSince1970)], expectedPayment: payment,
                    expectedScheduleCount: preview.totalCount, expectedOriginalCurrency: source, saveImmediately: false, in: context)
            }
            try context.save()
        } catch { context.rollback(); throw error }
        return batch.count
    }
}
