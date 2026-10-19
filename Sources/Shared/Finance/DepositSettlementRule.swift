import Foundation

enum DepositSettlementRule {
    private static let compoundingPeriodsPerYear = 12.0

    struct Result {
        let totalInterest: Double
        let maturityAmount: Double
        let maturitySettlementInterest: Double
    }

    static func result(
        principal: Double,
        annualInterestRate: Double,
        startDate: Date,
        maturityDate: Date,
        settlementMode: DepositInterestSettlementMode
    ) -> Result {
        let principal = max(principal, 0)
        let annualRate = max(annualInterestRate, 0) / 100.0
        let years = yearsBetween(start: startDate, end: maturityDate)

        guard principal > 0, annualRate > 0, years > 0 else {
            return Result(
                totalInterest: 0,
                maturityAmount: FinancialPrecision.roundAmountForStorage(principal),
                maturitySettlementInterest: 0
            )
        }

        switch settlementMode {
        case .monthly:
            let interest = simpleInterest(
                principal: principal,
                annualRate: annualRate,
                years: years
            )
            return Result(
                totalInterest: roundedAmount(interest),
                maturityAmount: FinancialPrecision.roundAmountForStorage(principal),
                maturitySettlementInterest: 0
            )
        case .maturity:
            let interest = simpleInterest(
                principal: principal,
                annualRate: annualRate,
                years: years
            )
            return Result(
                totalInterest: roundedAmount(interest),
                maturityAmount: roundedAmount(principal + interest),
                maturitySettlementInterest: roundedAmount(interest)
            )
        case .monthlyCompound:
            let interest = compoundInterest(
                principal: principal,
                annualRate: annualRate,
                years: years,
                periodsPerYear: compoundingPeriodsPerYear
            )
            return Result(
                totalInterest: roundedAmount(interest),
                maturityAmount: roundedAmount(principal + interest),
                maturitySettlementInterest: roundedAmount(interest)
            )
        }
    }

    static func totalInterest(
        principal: Double,
        annualInterestRate: Double,
        startDate: Date,
        maturityDate: Date,
        settlementMode: DepositInterestSettlementMode
    ) -> Double {
        result(
            principal: principal,
            annualInterestRate: annualInterestRate,
            startDate: startDate,
            maturityDate: maturityDate,
            settlementMode: settlementMode
        ).totalInterest
    }

    static func maturitySettlementInterest(
        principal: Double,
        annualInterestRate: Double,
        startDate: Date,
        maturityDate: Date,
        settlementMode: DepositInterestSettlementMode
    ) -> Double {
        result(
            principal: principal,
            annualInterestRate: annualInterestRate,
            startDate: startDate,
            maturityDate: maturityDate,
            settlementMode: settlementMode
        ).maturitySettlementInterest
    }

    static func periodicPayoutInterest(
        principal: Double,
        annualInterestRate: Double,
        from startDate: Date,
        to endDate: Date
    ) -> Double {
        let principal = max(principal, 0)
        let annualRate = max(annualInterestRate, 0) / 100.0
        let years = yearsBetween(start: startDate, end: endDate)

        guard principal > 0, annualRate > 0, years > 0 else { return 0 }

        return roundedAmount(simpleInterest(
            principal: principal,
            annualRate: annualRate,
            years: years
        ))
    }

    static func annualInterestRate(
        principal: Double,
        totalInterest: Double,
        startDate: Date,
        maturityDate: Date,
        settlementMode: DepositInterestSettlementMode
    ) -> Double? {
        let principal = max(principal, 0)
        let totalInterest = max(totalInterest, 0)
        let years = yearsBetween(start: startDate, end: maturityDate)

        guard principal > 0, years > 0 else { return nil }

        let annualRate: Double
        switch settlementMode {
        case .monthly, .maturity:
            annualRate = totalInterest / (principal * years)
        case .monthlyCompound:
            let ratio = 1 + (totalInterest / principal)
            guard ratio > 0 else { return 0 }
            annualRate = compoundingPeriodsPerYear * (pow(ratio, 1 / (compoundingPeriodsPerYear * years)) - 1)
        }

        guard annualRate.isFinite else { return nil }
        return FinancialPrecision.roundAmountForStorage(max(annualRate * 100, 0))
    }

    private static func simpleInterest(
        principal: Double,
        annualRate: Double,
        years: Double
    ) -> Double {
        max(principal * annualRate * years, 0)
    }

    private static func compoundInterest(
        principal: Double,
        annualRate: Double,
        years: Double,
        periodsPerYear: Double
    ) -> Double {
        let maturityAmount = principal * pow(1 + (annualRate / periodsPerYear), periodsPerYear * years)
        return max(maturityAmount - principal, 0)
    }

    private static func roundedAmount(_ value: Double) -> Double {
        FinancialPrecision.roundAmountForStorage(max(value, 0))
    }

    // Current convention uses Act/365; upgrade to Act/Act later if finer accrual accuracy is required.
    private static func yearsBetween(start: Date, end: Date) -> Double {
        guard end > start else { return 0 }

        var gregorianCalendar = Calendar(identifier: .gregorian)
        gregorianCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let startOfDay = gregorianCalendar.startOfDay(for: start)
        let endOfDay = gregorianCalendar.startOfDay(for: end)
        let dayCount = gregorianCalendar.dateComponents([.day], from: startOfDay, to: endOfDay).day ?? 0

        return max(Double(dayCount), 0) / 365.0
    }
}
