import Foundation
import SwiftData

/// The pure original DepositManager balance method is provided here because
/// the iOS manager's notification/editor dependencies are not part of MacApp.
/// FinancialProfileSnapshotRule itself is compiled unchanged from FinTrack/.
enum DepositManager {
    static func frozenPrincipalBalance(
        for deposits: [DepositRecord], baseCurrency: String,
        excluding excludedDepositID: UUID? = nil, asOf date: Date = Date()
    ) -> Double {
        let today = Calendar.current.startOfDay(for: date)
        return deposits.filter { deposit in
            guard deposit.baseCurrencyCode == baseCurrency else { return false }
            guard deposit.id != excludedDepositID else { return false }
            guard deposit.isActive else { return false }
            return Calendar.current.startOfDay(for: deposit.startDate) <= today
        }.reduce(0) { result, deposit in result + max(deposit.basePrincipal, 0) }
    }
}

enum MacFinancialSettings {
    enum ProfileInputError: LocalizedError {
        case cash, debt
        var errorDescription: String? { L10n.text(self == .cash ? "liquidity.invalid.cash" : "liquidity.invalid.debt") }
    }
    static func nonnegativeAmount(_ text: String) throws -> Double {
        let value = MacNumberInput.normalizedAmount(text)
        if value.range(of: #"^[0-9]+(\.[0-9]*)?$"#, options: .regularExpression) != nil, Double(value) == 0 { return 0 }
        return try MacTransactionCRUD.amount(value)
    }

    static func saveProfile(assets: String, debt: String, currency: String, initializingOnly: Bool = false, in context: ModelContext) throws {
        _ = try MacCurrency.ledgerCurrency(in: context, preferred: currency)
        let cashText = MacNumberInput.normalizedAmount(assets)
        guard cashText.range(of: #"^-?[0-9]+(\.[0-9]*)?$"#, options: .regularExpression) != nil,
              let assets = Double(cashText), assets.isFinite, abs(assets) <= 1e12 else { throw ProfileInputError.cash }
        let debtValue: Double
        do { debtValue = try nonnegativeAmount(debt) } catch { throw ProfileInputError.debt }
        let profile = try MacLiquidity.profile(in: context)
            ?? FinancialProfile()
        if initializingOnly && profile.liquidityData != nil { throw MacFinanceReview.Failure.confirmation }
        if profile.modelContext == nil { context.insert(profile) }
        do { try MacLiquidity.confirm(amount: assets, profile: profile, currency: currency, in: context) }
        catch { context.rollback(); throw error }
        profile.initialDebt = Goal.normalizedDebt(debtValue)
        profile.updatedAt = Date()
        if profile.syncVersion < Int.max { profile.syncVersion += 1 }
        do { try context.save() } catch { context.rollback(); throw error }
    }

    static func snapshot(profile: FinancialProfile?, transactions: [Transaction], loans: [LoanRule],
                         deposits: [DepositRecord], currency: String, asOf date: Date) -> FinancialProfileSnapshot {
        // Ledger dates are calendar days: settlement may retain a time later
        // today even after the user has confirmed receipt. Match the overview's
        // daily accounting boundary without rewriting historical timestamps.
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date)) ?? date
        let cash = transactions.filter { $0.deletedAt == nil && $0.date < nextDay }
        let currentLoans = loans.filter { $0.deletedAt == nil && $0.baseCurrencyCode == currency }
        let original = FinancialProfileSnapshotRule.snapshot(profile: profile,
            transactions: cash, loans: [], deposits: deposits.filter { $0.deletedAt == nil },
            baseCurrency: currency, asOf: date)
        // A date passing is not evidence of a repayment. Unverified loans retain
        // their full saved principal until their receipt history is reconciled.
        let debt = currentLoans.reduce(0.0) { sum, loan in
            let audit = MacLoansData.audit(loan, transactions: cash, rules: [])
            let remaining = audit.reliable ? (audit.outstanding ?? loan.principal) : loan.principal
            return sum + FinancialPrecision.roundAmountForStorage(remaining * loan.exchangeRateToBase)
        }
        var liquid = original.availableAssets
        var held = original.frozenDepositPrincipal
        if let state = MacLiquidity.state(profile), state.currency == currency {
            liquid = MacLiquidity.cash(state, transactions: transactions, asOf: date)
            let today = Calendar.current.startOfDay(for: date)
            held = state.positions.filter { !$0.returned && !$0.cancelled && ($0.opening || Calendar.current.startOfDay(for: $0.start) <= today) }
                .reduce(0) { $0 + $1.principal }
            // Imported records have no funding provenance; retain active assets
            // and require explicit calibration instead of inventing transfers.
            let tracked = Set(state.positions.map(\.id))
            held += DepositManager.frozenPrincipalBalance(for: deposits.filter { $0.deletedAt == nil && !tracked.contains($0.id) }, baseCurrency: currency, asOf: date)
        }
        return FinancialProfileSnapshot(netWorth: liquid + held - original.manualDebtBalance - debt, availableAssets: liquid,
            frozenDepositPrincipal: held, manualDebtBalance: original.manualDebtBalance,
            loanBalance: debt, requiredAssetReferenceTopUp: original.requiredAssetReferenceTopUp)
    }
}
