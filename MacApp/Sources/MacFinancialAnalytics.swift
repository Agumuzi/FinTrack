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
    static func nonnegativeAmount(_ text: String) throws -> Double {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        if !value.isEmpty, value.allSatisfy({ "0123456789.".contains($0) }),
           value.filter({ $0 == "." }).count <= 1, Double(value) == 0 { return 0 }
        return try MacTransactionCRUD.amount(value)
    }

    static func saveProfile(assets: String, debt: String, currency: String, in context: ModelContext) throws {
        _ = try MacCurrency.ledgerCurrency(in: context, preferred: currency)
        let assets = try nonnegativeAmount(assets), debt = try nonnegativeAmount(debt)
        let profile = try context.fetch(FetchDescriptor<FinancialProfile>(sortBy: [SortDescriptor(\.createdAt)])).first { $0.deletedAt == nil }
            ?? FinancialProfile()
        if profile.modelContext == nil { context.insert(profile) }
        profile.initialAssets = assets
        profile.initialDebt = Goal.normalizedDebt(debt)
        profile.updatedAt = Date()
        if profile.syncVersion < Int.max { profile.syncVersion += 1 }
        do { try context.save() } catch { context.rollback(); throw error }
    }

    static func snapshot(profile: FinancialProfile?, transactions: [Transaction], loans: [LoanRule],
                         deposits: [DepositRecord], currency: String, asOf date: Date) -> FinancialProfileSnapshot {
        FinancialProfileSnapshotRule.snapshot(profile: profile,
            transactions: transactions.filter { $0.deletedAt == nil },
            loans: loans.filter { $0.deletedAt == nil }, deposits: deposits.filter { $0.deletedAt == nil },
            baseCurrency: currency, asOf: date)
    }
}
