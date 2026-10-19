import Foundation
import SwiftData

enum MacFinanceReview {
    enum Failure: LocalizedError {
        case confirmation, schedule
        var errorDescription: String? {
            switch self {
            case .confirmation: "Confirm the next unrecorded date against your ledger before continuing."
            case .schedule: "The saved schedule is inconsistent. Review the record before enabling it."
            }
        }
    }
    static func recurring(_ rule: RecurringTransaction, next: Date, confirmed: Bool, in context: ModelContext) throws {
        guard confirmed else { throw Failure.confirmation }
        guard rule.deletedAt == nil, (1...365).contains(rule.intervalValue),
              RecurringIntervalUnit(rawValue: rule.intervalUnit) != nil,
              rule.lastExecutionDate == nil || next > rule.lastExecutionDate! else { throw Failure.schedule }
        _ = try MacCurrency.code(rule.originalCurrency)
        if !MacFinanceRecords.isManagedRecurring(rule) { rule.note = MacFinanceRecords.reviewedRecurringTag + "\n" + (rule.note ?? "") }
        rule.nextExecutionDate = next; rule.isActive = true; rule.updatedAt = Date()
        do { try context.save() } catch { context.rollback(); throw error }
    }
    static func deposit(_ record: DepositRecord, firstUnrecorded: Date, confirmed: Bool, in context: ModelContext) throws {
        guard confirmed else { throw Failure.confirmation }
        guard record.deletedAt == nil, !record.hasCreditedInterest, record.startDate < record.maturityDate else { throw Failure.schedule }
        var prior: Date?
        var next: Date?
        if record.typedInterestSettlementMode == .monthly {
            var cursor = record.startDate
            var found = false
            for _ in 0..<1200 {
                let due = min(Calendar.current.date(byAdding: .month, value: 1, to: cursor)!, record.maturityDate)
                if Calendar.current.isDate(due, inSameDayAs: firstUnrecorded) { next = due; prior = cursor == record.startDate ? nil : cursor; found = true; break }
                if due >= record.maturityDate { break }
                cursor = due
            }
            guard found else { throw Failure.schedule }
        }
        if !MacDepositSettlement.isManaged(record) { record.note = MacFinanceRecords.managedDepositTag + "\n" + (record.note ?? "") }
        record.lastInterestPayoutDate = prior; record.nextInterestPayoutDate = next
        record.isActive = true; record.updatedAt = Date()
        do { try context.save() } catch { context.rollback(); throw error }
    }
    static func loan(_ loan: LoanRule, firstUnrecordedIndex: Int, confirmed: Bool, in context: ModelContext) throws {
        guard confirmed else { throw Failure.confirmation }
        let schedule = loan.amortizationSchedule
        guard !schedule.isEmpty, (1...schedule.count).contains(firstUnrecordedIndex) else { throw Failure.schedule }
        let prefix = "loan_generated:\(loan.id.uuidString):"
        let allRules = try context.fetch(FetchDescriptor<RecurringTransaction>())
        var byIndex: [Int: RecurringTransaction] = [:]
        for r in allRules where (r.projectIdentifier ?? "").hasPrefix(prefix) {
            guard let index = Int(String(r.projectIdentifier!.dropFirst(prefix.count))),
                  (1...schedule.count).contains(index), byIndex[index] == nil else { throw Failure.schedule }
            byIndex[index] = r
        }
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        do {
            var linked: [RecurringTransaction] = []
            for payment in schedule {
                let rule: RecurringTransaction
                if let existing = byIndex[payment.index] { rule = existing }
                else {
                    rule = RecurringTransaction(title: "\(loan.title) \(payment.index)/\(loan.termMonths)",
                        amount: payment.total, currency: loan.currency, type: .expense, category: loan.category,
                        note: "Principal: \(payment.principal); Interest: \(payment.interest)",
                        projectIdentifier: prefix + String(payment.index), intervalValue: 1, intervalUnit: .month,
                        nextExecutionDate: payment.date, endDate: payment.date,
                        originalAmount: payment.total, originalCurrency: loan.currency,
                        exchangeRateToBase: loan.exchangeRateToBase,
                        baseAmount: FinancialPrecision.roundAmountForStorage(payment.total * loan.exchangeRateToBase), baseCurrencyCode: loan.baseCurrencyCode)
                    context.insert(rule)
                }
                let alreadyMarked = transactions.contains { ($0.note ?? "").contains(MacLoanRepayment.marker(loanID: loan.id, payment: payment)) }
                let alreadyExecuted = rule.lastExecutionDate.map { $0 >= payment.date } ?? false
                rule.isActive = payment.index >= firstUnrecordedIndex && !alreadyMarked && !alreadyExecuted
                if !MacFinanceRecords.isManagedRecurring(rule) { rule.note = MacFinanceRecords.reviewedRecurringTag + "\n" + (rule.note ?? "") }
                linked.append(rule)
            }
            loan.generatedRules = linked; loan.updatedAt = Date()
            try context.save()
        } catch { context.rollback(); throw error }
    }
    static func renewal(source: DepositRecord, bank: String, principal: String, annualRate: Double,
                        start: Date, maturity: Date, mode: DepositInterestSettlementMode,
                        book: String, sourceCurrency: String, principalRate: Double?, interestRate: Double?,
                        notificationsEnabled: Bool = false, reminder: MacReminderSettings? = nil, userNote: String = "", expectedInterestOverride: Double? = nil,
                        in context: ModelContext) throws -> DepositRecord {
        guard !source.isActive, source.hasCreditedInterest, source.deletedAt == nil,
              source.typedInterestSettlementMode != .monthly, start >= source.maturityDate else { throw Failure.schedule }
        let existing = try context.fetch(FetchDescriptor<DepositRecord>())
        guard !existing.contains(where: { $0.sourceDepositID == source.id && $0.deletedAt == nil }) else { throw Failure.schedule }
        do {
            let target = try MacFinanceRecords.addDeposit(bank: bank, principalText: principal, annualRate: annualRate,
                start: start, maturity: maturity, mode: mode, currency: book, originalCurrency: sourceCurrency,
                principalRate: principalRate, expectedInterestRate: interestRate, notificationsEnabled: notificationsEnabled,
                reminder: reminder, userNote: userNote, expectedInterestOverride: expectedInterestOverride, saveImmediately: false, in: context)
            target.sourceDepositID = source.id
            target.rolloverBasePrincipalAmount = min(target.basePrincipal, source.basePrincipal)
            target.rolloverBaseInterestAmount = min(max(target.basePrincipal - target.resolvedRolloverBasePrincipalAmount, 0), source.baseExpectedInterest)
            source.typedMaturityInterestHandling = .rollover
            try context.save()
            return target
        } catch { context.rollback(); throw error }
    }
}
