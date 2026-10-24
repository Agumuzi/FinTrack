import Foundation

enum MacDepositTerms {
    struct Period { let date: Date; let interest: Double }
    /// A manual total is authoritative. Allocate monthly totals cumulatively so
    /// rounding individual periods cannot create or lose a cent.
    static func schedule(_ deposit: DepositRecord) -> [Period] {
        guard deposit.startDate < deposit.maturityDate else { return [] }
        if deposit.typedInterestSettlementMode != .monthly {
            return [Period(date: deposit.maturityDate, interest: deposit.isInterestManuallyEdited ? deposit.expectedInterest : DepositSettlementRule.maturitySettlementInterest(principal: deposit.principal, annualInterestRate: deposit.annualInterestRate, startDate: deposit.startDate, maturityDate: deposit.maturityDate, settlementMode: deposit.typedInterestSettlementMode))]
        }
        var result: [Period] = [], cursor = deposit.startDate, allocated = 0.0
        let calendar = Calendar.current
        let totalDays = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: deposit.startDate), to: calendar.startOfDay(for: deposit.maturityDate)).day ?? 1)
        for _ in 0..<1200 {
            guard cursor < deposit.maturityDate, let next = calendar.date(byAdding: .month, value: 1, to: cursor), next > cursor else { break }
            let due = min(next, deposit.maturityDate)
            let amount: Double
            if deposit.isInterestManuallyEdited {
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: deposit.startDate), to: calendar.startOfDay(for: due)).day ?? 0
                let cumulative = due == deposit.maturityDate ? deposit.expectedInterest : FinancialPrecision.roundAmountForStorage(deposit.expectedInterest * Double(days) / Double(totalDays))
                amount = FinancialPrecision.roundAmountForStorage(max(0, cumulative - allocated)); allocated = cumulative
            } else { amount = DepositSettlementRule.periodicPayoutInterest(principal: deposit.principal, annualInterestRate: deposit.annualInterestRate, from: cursor, to: due) }
            result.append(Period(date: due, interest: amount)); cursor = due
        }
        return result
    }
    static func projectedInterest(_ deposit: DepositRecord) -> Double {
        FinancialPrecision.roundAmountForStorage(schedule(deposit).reduce(0) { $0 + $1.interest })
    }
    private static func monthlyTotal(principal: Double, annualRate: Double, start: Date, maturity: Date) -> Double {
        var cursor = start, total = 0.0
        for _ in 0..<1200 {
            guard cursor < maturity, let next = Calendar.current.date(byAdding: .month, value: 1, to: cursor), next > cursor else { break }
            let due = min(next, maturity)
            total += DepositSettlementRule.periodicPayoutInterest(principal: principal, annualInterestRate: annualRate, from: cursor, to: due)
            cursor = due
        }
        return FinancialPrecision.roundAmountForStorage(total)
    }
    struct Terms { let annualRate: Double; let expectedInterest: Double; let manuallyEdited: Bool }
    static func calculate(principal: Double, annualRate: Double, start: Date, maturity: Date,
                          mode: DepositInterestSettlementMode, expectedOverride: Double?) throws -> Terms {
        guard principal > 0, maturity > start, annualRate.isFinite, (0...100).contains(annualRate) else { throw MacFinanceRecords.Failure.invalidRate }
        if let expectedOverride {
            guard expectedOverride.isFinite, expectedOverride >= 0,
                  let rate = DepositSettlementRule.annualInterestRate(principal: principal, totalInterest: expectedOverride,
                    startDate: start, maturityDate: maturity, settlementMode: mode), (0...100).contains(rate)
            else { throw MacFinanceRecords.Failure.invalidRate }
            return Terms(annualRate: rate, expectedInterest: FinancialPrecision.roundAmountForStorage(expectedOverride), manuallyEdited: true)
        }
        let storedRate = FinancialPrecision.roundInterestRateForStorage(annualRate)
        let interest = mode == .monthly ? monthlyTotal(principal: principal, annualRate: storedRate, start: start, maturity: maturity) : DepositSettlementRule.totalInterest(principal: principal,
            annualInterestRate: storedRate, startDate: start, maturityDate: maturity, settlementMode: mode)
        return Terms(annualRate: storedRate, expectedInterest: interest, manuallyEdited: false)
    }
}
