import Foundation
import SwiftData

/// Opt-in bank-interest receipts for deposits CREATED by the guarded Mac editor.
/// Existing iOS and pre-V1.6.2 records stay read-only: their historic payouts,
/// rollover and reconciliation cannot safely be inferred from original fields.
///
/// Uses the ORIGINAL DepositSettlementRule amounts and original Transaction
/// original/base snapshot fields. No principal withdrawal/capital transfer is
/// synthesized. Serial single-context idempotency only; separate-window
/// concurrency needs a persistent uniqueness constraint before automation.
@MainActor
enum MacDepositSettlement {
    enum PostingError: LocalizedError {
        case legacyRecord, unsafeRollover, currencyMismatch, notDue
        case corruptedSchedule, duplicateReceipt, tooManyPeriods
        case noLongerActive

        var errorDescription: String? {
            switch self {
            case .legacyRecord: "Old deposits need manual reconciliation before cash posting."
            case .unsafeRollover: "The renewal source or principal allocation could not be verified."
            case .currencyMismatch: "Provide a dated exchange rate for every foreign-currency interest receipt."
            case .notDue: "No bank interest payment is due on this date."
            case .corruptedSchedule: "Original monthly payout dates do not match the saved schedule."
            case .duplicateReceipt: "This deposit interest period already has a posted receipt."
            case .tooManyPeriods: "More than 24 unpaid periods: review before posting."
            case .noLongerActive: "This deposit is inactive or has already been settled."
            }
        }
    }

    struct PostingResult {
        let receipts: Int
        let totalInterest: Double
        let matured: Bool
    }

    static func isManaged(_ record: DepositRecord) -> Bool {
        (record.note ?? "").hasPrefix(MacFinanceRecords.managedDepositTag)
            && record.deletedAt == nil
    }

    static func isEligible(_ record: DepositRecord, now: Date = Date()) -> Bool {
        guard isManaged(record), record.isActive, !record.hasCreditedInterest,
              record.principalExchangeRateToBase > 0,
              record.originalCurrency == record.currency
        else { return false }
        let due = record.typedInterestSettlementMode == .monthly
            ? record.nextInterestPayoutDate : Optional(record.maturityDate)
        guard let due else { return false }
        return Calendar.current.startOfDay(for: due) <= Calendar.current.startOfDay(for: now)
    }

    /// Matches the original DepositManager.nextInterestPayoutDate() calendar
    /// progression. The original method cannot be compiled without its iOS-only
    /// notification/exchange-rate service dependencies.
    private static func nextPayout(_ deposit: DepositRecord, after last: Date?) -> Date? {
        let base = last ?? deposit.startDate
        guard base < deposit.maturityDate,
              let next = Calendar.current.date(byAdding: .month, value: 1, to: base)
        else { return nil }
        return min(next, deposit.maturityDate)
    }

    static func receiptMarker(depositID: UUID, date: Date, monthly: Bool) -> String {
        let kind = monthly ? "MP" : "MAT"
        return "[FTDep:\(depositID.uuidString):\(Int64(date.timeIntervalSince1970)):\(kind)]"
    }

    @discardableResult
    static func postDue(
        _ deposit: DepositRecord, now: Date, bookCurrency: String,
        exchangeRates: [Int64: Double] = [:], in context: ModelContext
    ) throws -> PostingResult {
        guard isManaged(deposit) else { throw PostingError.legacyRecord }
        if let sourceID = deposit.sourceDepositID {
            let parents = try context.fetch(FetchDescriptor<DepositRecord>())
            guard parents.contains(where: { $0.id == sourceID && !$0.isActive && $0.hasCreditedInterest }) else { throw PostingError.unsafeRollover }
        } else if deposit.resolvedRolloverBasePrincipalAmount != 0 || deposit.resolvedRolloverBaseInterestAmount != 0 {
            throw PostingError.unsafeRollover
        }
        guard deposit.isActive, !deposit.hasCreditedInterest else {
            throw PostingError.noLongerActive
        }
        guard deposit.principalExchangeRateToBase.isFinite, deposit.principalExchangeRateToBase > 0,
              deposit.baseCurrencyCode == bookCurrency,
              deposit.currency == deposit.originalCurrency,
              deposit.principal == deposit.originalPrincipal,
              deposit.basePrincipal == FinancialPrecision.roundAmountForStorage(deposit.originalPrincipal * deposit.principalExchangeRateToBase),
              deposit.startDate < deposit.maturityDate
        else { throw PostingError.currencyMismatch }

        // Double-check ALL persisted source models; do not post a separate
        // currency book merely because this particular deposit matches it.
        let allTransactions = try context.fetch(FetchDescriptor<Transaction>())
        let allDeposits = try context.fetch(FetchDescriptor<DepositRecord>())
        let allLoans = try context.fetch(FetchDescriptor<LoanRule>())
        let allRules = try context.fetch(FetchDescriptor<RecurringTransaction>())
        var currencies = Set(allTransactions.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        currencies.formUnion(allDeposits.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        currencies.formUnion(allLoans.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        currencies.formUnion(allRules.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        guard currencies == Set([bookCurrency]) else { throw PostingError.currencyMismatch }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let isMonthly = deposit.typedInterestSettlementMode == .monthly
        var items: [(date: Date, amount: Double, marker: String)] = []
        var newLast = deposit.lastInterestPayoutDate
        var newNext = deposit.nextInterestPayoutDate
        var matured = false
        var periods = 0

        if isMonthly {
            guard newNext == nextPayout(deposit, after: newLast) else {
                throw PostingError.corruptedSchedule
            }
            while let due = newNext, calendar.startOfDay(for: due) <= today {
                guard periods < 24 else { throw PostingError.tooManyPeriods }
                periods += 1
                let start = newLast ?? deposit.startDate
                guard due > start else { throw PostingError.corruptedSchedule }
                let amount = DepositSettlementRule.periodicPayoutInterest(
                    principal: deposit.principal,
                    annualInterestRate: deposit.annualInterestRate,
                    from: start, to: due
                )
                let marker = receiptMarker(depositID: deposit.id, date: due, monthly: true)
                if amount > 0 { items.append((due, amount, marker)) }
                newLast = due
                newNext = nextPayout(deposit, after: newLast)
                if due >= deposit.maturityDate {
                    matured = true
                    newNext = nil
                    break
                }
            }
            // Zero-rate periods also advance the scheduling cursor, but must
            // count toward the cap to avoid unbounded catch-up loops.
        } else {
            guard deposit.lastInterestPayoutDate == nil,
                  deposit.nextInterestPayoutDate == nil
            else { throw PostingError.corruptedSchedule }
            guard today >= calendar.startOfDay(for: deposit.maturityDate) else {
                throw PostingError.notDue
            }
            let amount = DepositSettlementRule.maturitySettlementInterest(
                principal: deposit.principal,
                annualInterestRate: deposit.annualInterestRate,
                startDate: deposit.startDate,
                maturityDate: deposit.maturityDate,
                settlementMode: deposit.typedInterestSettlementMode
            )
            let marker = receiptMarker(
                depositID: deposit.id, date: deposit.maturityDate, monthly: false)
            if amount > 0 { items.append((deposit.maturityDate, amount, marker)) }
            matured = true
        }

        guard matured || newLast != deposit.lastInterestPayoutDate else {
            throw PostingError.notDue
        }
        let uniqueMarkers = Set(items.map(\.marker))
        guard uniqueMarkers.count == items.count,
              !allTransactions.contains(where: { row in
                  let note = row.note ?? ""
                  return uniqueMarkers.contains(where: { note.contains($0) })
              })
        else { throw PostingError.duplicateReceipt }
        let snapshots = try items.map { item in
            try MacCurrency.snapshot(amount: item.amount, original: deposit.originalCurrency,
                base: bookCurrency, rate: deposit.originalCurrency == bookCurrency ? 1 : exchangeRates[Int64(item.date.timeIntervalSince1970)])
        }

        do {
            for (item, snapshot) in zip(items, snapshots) {
                context.insert(Transaction(
                    amount: snapshot.baseAmount, currency: bookCurrency, type: .income,
                    category: "Deposit",
                    note: "Bank interest: \(deposit.bankName) \(item.marker)",
                    date: item.date,
                    originalAmount: item.amount, originalCurrency: deposit.originalCurrency,
                    exchangeRateToBase: snapshot.rate, baseAmount: snapshot.baseAmount,
                    baseCurrencyCode: bookCurrency
                ))
            }
            if isMonthly {
                deposit.lastInterestPayoutDate = newLast
                deposit.nextInterestPayoutDate = newNext
            }
            if matured {
                deposit.isActive = false
                deposit.hasCreditedInterest = true
                deposit.nextInterestPayoutDate = nil
            }
            deposit.updatedAt = now
            if deposit.syncVersion < Int.max { deposit.syncVersion += 1 }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return PostingResult(
            receipts: items.count,
            totalInterest: FinancialPrecision.roundAmountForStorage(
                items.reduce(0.0) { $0 + $1.amount }),
            matured: matured
        )
    }
}
