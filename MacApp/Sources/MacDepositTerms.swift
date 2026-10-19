import Foundation

enum MacDepositTerms {
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
        return Terms(annualRate: annualRate, expectedInterest: DepositSettlementRule.totalInterest(principal: principal,
            annualInterestRate: annualRate, startDate: start, maturityDate: maturity, settlementMode: mode), manuallyEdited: false)
    }
}
