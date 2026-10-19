import Foundation

struct FinancialProfileSnapshot {
    let netWorth: Double
    let availableAssets: Double
    let frozenDepositPrincipal: Double
    let manualDebtBalance: Double
    let loanBalance: Double
    let requiredAssetReferenceTopUp: Double
}

enum FinancialProfileSnapshotRule {
    static func snapshot(
        profile: FinancialProfile?,
        transactions: [Transaction],
        loans: [LoanRule],
        deposits: [DepositRecord],
        baseCurrency: String,
        excludingDepositID: UUID? = nil,
        asOf date: Date = Date()
    ) -> FinancialProfileSnapshot {
        let baselineAssets = profile?.initialAssets ?? 0
        let manualDebtBalance = max(-Goal.normalizedDebt(profile?.initialDebt ?? 0), 0)
        let baseCurrencyTransactions = transactions.filter { $0.baseCurrencyCode == baseCurrency }
        let incomeBalance = baseCurrencyTransactions
            .filter { $0.typedType == .income }
            .reduce(0) { $0 + $1.baseAmount }
        let expenseBalance = baseCurrencyTransactions
            .filter { $0.typedType == .expense }
            .reduce(0) { $0 + $1.baseAmount }
        let availableAssets = baselineAssets + incomeBalance - expenseBalance
        let loanBalance = LoanAnalytics.totalOutstandingPrincipal(
            for: LoanAnalytics.baseCurrencyLoans(from: loans, baseCurrency: baseCurrency),
            asOf: date
        )
        let frozenDepositPrincipal = DepositManager.frozenPrincipalBalance(
            for: deposits,
            baseCurrency: baseCurrency,
            excluding: excludingDepositID,
            asOf: date
        )
        let netWorth = availableAssets + frozenDepositPrincipal - manualDebtBalance - loanBalance

        return FinancialProfileSnapshot(
            netWorth: netWorth,
            availableAssets: availableAssets,
            frozenDepositPrincipal: frozenDepositPrincipal,
            manualDebtBalance: manualDebtBalance,
            loanBalance: loanBalance,
            requiredAssetReferenceTopUp: 0
        )
    }
}
