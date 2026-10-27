// Lightweight, independent smoke tests for production calculation sources.
// Run with the same files as the GitHub Actions Build workflow.
// This test-only enum mirrors the cases of DepositInterestSettlementMode in
// Sources/Shared/Models/DepositRecord.swift. A future XCTest target should
// compile the production model directly instead.
import Foundation

enum DepositInterestSettlementMode {
    case monthly
    case maturity
    case monthlyCompound
}

@main
struct FinanceSmoke {
    static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        guard condition() else { fatalError("Finance smoke failed: \(label)") }
    }

    static func near(_ actual: Double, _ expected: Double, _ label: String, tolerance: Double = 0.00001) {
        check(actual.isFinite && abs(actual - expected) <= tolerance, "\(label): got \(actual), expected \(expected)")
    }

    static func main() {
        near(FinancialPrecision.roundAmountForStorage(12.349), 12.35, "amount storage rounding")
        near(FinancialPrecision.roundAmountForDisplay(12.341), 12.34, "amount display rounding")
        near(FinancialPrecision.roundAmountForStorage(-12.349), -12.35, "negative rounding")
        near(FinancialPrecision.roundExchangeRateForStorage(1.23456789), 1.234568, "FX storage precision")
        near(FinancialPrecision.roundExchangeRateForDisplay(1.23456), 1.2346, "FX display precision")
        near(FinancialPrecision.roundInterestRateForStorage(12.34567), 12.3457, "interest rate precision")

        let parser = ISO8601DateFormatter()
        let start = parser.date(from: "2025-01-01T00:00:00Z")!
        let maturity = parser.date(from: "2026-01-01T00:00:00Z")!
        let januaryEnd = parser.date(from: "2025-02-01T00:00:00Z")!

        let atMaturity = DepositSettlementRule.result(
            principal: 1000, annualInterestRate: 12, startDate: start,
            maturityDate: maturity, settlementMode: .maturity
        )
        near(atMaturity.totalInterest, 120, "simple interest")
        near(atMaturity.maturityAmount, 1120, "maturity principal plus interest")
        near(atMaturity.maturitySettlementInterest, 120, "interest paid at maturity")

        let monthly = DepositSettlementRule.result(
            principal: 1000, annualInterestRate: 12, startDate: start,
            maturityDate: maturity, settlementMode: .monthly
        )
        near(monthly.totalInterest, 120, "monthly interest sum")
        near(monthly.maturityAmount, 1000, "monthly payouts keep principal unchanged")
        near(monthly.maturitySettlementInterest, 0, "no maturity payout for monthly settlement")

        let compounded = DepositSettlementRule.result(
            principal: 1000, annualInterestRate: 12, startDate: start,
            maturityDate: maturity, settlementMode: .monthlyCompound
        )
        near(compounded.totalInterest, 126.83, "monthly compounding")
        near(compounded.maturityAmount, 1126.83, "compounded maturity amount")

        near(DepositSettlementRule.periodicPayoutInterest(
            principal: 1000, annualInterestRate: 12, from: start, to: januaryEnd
        ), 10.19, "31-day period with ACT/365")

        let zeroRate = DepositSettlementRule.result(
            principal: 1000, annualInterestRate: 0, startDate: start,
            maturityDate: maturity, settlementMode: .maturity
        )
        near(zeroRate.totalInterest, 0, "zero rate")
        near(zeroRate.maturityAmount, 1000, "zero rate preserves principal")

        let invalidRange = DepositSettlementRule.result(
            principal: 1000, annualInterestRate: 12, startDate: maturity,
            maturityDate: start, settlementMode: .maturity
        )
        near(invalidRange.totalInterest, 0, "reversed dates")

        let negativePrincipal = DepositSettlementRule.result(
            principal: -1000, annualInterestRate: 12, startDate: start,
            maturityDate: maturity, settlementMode: .maturity
        )
        near(negativePrincipal.maturityAmount, 0, "negative principal clamped")

        let inverse = DepositSettlementRule.annualInterestRate(
            principal: 1000, totalInterest: 120, startDate: start,
            maturityDate: maturity, settlementMode: .maturity
        )
        check(inverse != nil, "inverse rate available")
        near(inverse!, 12, "recover annual interest rate")
        check(DepositSettlementRule.annualInterestRate(
            principal: 0, totalInterest: 100, startDate: start,
            maturityDate: maturity, settlementMode: .maturity
        ) == nil, "invalid inverse principal")

        print("PASS: FinancialPrecision + DepositSettlementRule smoke checks")
    }
}
