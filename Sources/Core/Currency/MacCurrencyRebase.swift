import Foundation
import SwiftData

enum MacCurrencyRebase {
    struct Plan {
        let currency: String
        let count: Int
        fileprivate let signature: String
        fileprivate let apply: () -> Void
        fileprivate let budgets: Data
    }
    enum Failure: LocalizedError {
        case changed
        var errorDescription: String? { "The ledger changed while conversion was being prepared. Prepare the conversion again. Nothing was saved." }
    }
    private static func signature(_ context: ModelContext) throws -> String {
        var parts: [String] = []
        parts += try context.fetch(FetchDescriptor<Transaction>()).map { "T:\($0.id):\($0.originalAmount):\($0.originalCurrency):\($0.baseAmount):\($0.baseCurrencyCode):\($0.updatedAt):\($0.date)" }
        parts += try context.fetch(FetchDescriptor<RecurringTransaction>()).map { "R:\($0.id):\($0.originalAmount):\($0.originalCurrency):\($0.baseAmount):\($0.baseCurrencyCode):\($0.updatedAt):\($0.nextExecutionDate)" }
        parts += try context.fetch(FetchDescriptor<DepositRecord>()).map { "D:\($0.id):\($0.originalPrincipal):\($0.originalCurrency):\($0.basePrincipal):\($0.baseExpectedInterest):\($0.updatedAt)" }
        parts += try context.fetch(FetchDescriptor<LoanRule>()).map { "L:\($0.id):\($0.principal):\($0.currency):\($0.basePrincipal):\($0.updatedAt)" }
        parts += try context.fetch(FetchDescriptor<FinancialProfile>()).map { "P:\($0.id):\($0.initialAssets):\($0.initialDebt):\($0.updatedAt)" }
        parts += try context.fetch(FetchDescriptor<Goal>()).map { "G:\($0.id):\($0.targetAmount):\($0.creationNetWorth):\($0.updatedAt)" }
        parts.append("Budgets:" + (MacPreferences.defaults.data(forKey: "v2_budgets")?.base64EncodedString() ?? ""))
        return parts.sorted().joined(separator: "\n")
    }
    static func prepare(in context: ModelContext, to newCode: String, referenceCurrency: String,
                        manualRates: [String: Double] = [:]) async throws -> Plan {
        guard !context.hasChanges else { throw Failure.changed }
        let book = try MacCurrency.code(newCode), reference = try MacCurrency.code(referenceCurrency)
        let initial = try signature(context)
        func convert(_ amount: Double, _ source: String, _ date: Date) async throws -> MacCurrencySnapshot {
            let source = try MacCurrency.code(source)
            if amount == 0 { return MacCurrencySnapshot(originalAmount: 0, originalCurrency: source, baseAmount: 0, baseCurrency: book, rate: 1) }
            let rate: Double
            if source == book { rate = 1 }
            else if let manual = manualRates[source] { rate = manual }
            else { rate = try await MacExchangeRates.shared.quote(from: source, to: book, on: min(date, Date())) }
            return try MacCurrency.snapshot(amount: abs(amount), original: source, base: book, rate: rate)
        }
        var changes: [() -> Void] = []
        for row in try context.fetch(FetchDescriptor<Transaction>()) {
            let s = try await convert(row.originalAmount, row.originalCurrency, row.date)
            changes.append { row.baseAmount = s.baseAmount; row.baseCurrencyCode = book; row.exchangeRateToBase = s.rate }
        }
        for row in try context.fetch(FetchDescriptor<RecurringTransaction>()) {
            let s = try await convert(row.originalAmount, row.originalCurrency, row.nextExecutionDate)
            changes.append { row.baseAmount = s.baseAmount; row.baseCurrencyCode = book; row.exchangeRateToBase = s.rate }
        }
        for row in try context.fetch(FetchDescriptor<LoanRule>()) {
            let s = try await convert(row.principal, row.currency, row.startDate)
            changes.append { row.basePrincipal = s.baseAmount; row.baseCurrencyCode = book; row.exchangeRateToBase = s.rate }
        }
        for row in try context.fetch(FetchDescriptor<DepositRecord>()) {
            let p = try await convert(row.originalPrincipal, row.originalCurrency, row.startDate)
            let i = try await convert(row.expectedInterest, row.originalCurrency, row.maturityDate)
            let oldBook = row.baseCurrencyCode
            let transferred = try await convert(row.resolvedRolloverBasePrincipalAmount, oldBook, row.startDate)
            let transferredInterest = try await convert(row.resolvedRolloverBaseInterestAmount, oldBook, row.startDate)
            changes.append {
                row.basePrincipal = p.baseAmount; row.baseExpectedInterest = i.baseAmount; row.baseCurrencyCode = book
                row.principalExchangeRateToBase = p.rate; row.interestExchangeRateToBase = i.rate
                row.rolloverBasePrincipalAmount = transferred.baseAmount; row.rolloverBaseInterestAmount = transferredInterest.baseAmount
            }
        }
        for row in try context.fetch(FetchDescriptor<FinancialProfile>()) {
            let a = try await convert(row.initialAssets, reference, row.createdAt)
            let d = try await convert(row.initialDebt, reference, row.createdAt)
            let sign = row.initialDebt < 0 ? -1.0 : 1.0
            changes.append { row.initialAssets = a.baseAmount; row.initialDebt = d.baseAmount * sign }
        }
        for row in try context.fetch(FetchDescriptor<Goal>()) {
            let t = try await convert(row.targetAmount, reference, row.createdAt)
            let c = try await convert(row.creationNetWorth, reference, row.createdAt)
            let sign = row.creationNetWorth < 0 ? -1.0 : 1.0
            changes.append { row.targetAmount = t.baseAmount; row.creationNetWorth = c.baseAmount * sign }
        }
        var budgets: [MacBudget] = MacSettingsStore.load("v2_budgets", fallback: [])
        for index in budgets.indices {
            try budgets[index].validate()
            let parts = budgets[index].month.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2, let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: 1)) else { throw Failure.changed }
            let converted = try await convert(budgets[index].amount, budgets[index].currency, date)
            budgets[index].amount = converted.baseAmount; budgets[index].currency = book
        }
        let budgetData = try JSONEncoder().encode(budgets)
        guard initial == (try signature(context)), !context.hasChanges else { throw Failure.changed }
        return Plan(currency: book, count: changes.count + budgets.count, signature: initial, apply: { changes.forEach { $0() } }, budgets: budgetData)
    }
    static func commit(_ plan: Plan, in context: ModelContext) throws {
        guard !MacAutomaticPosting.isRunning else { throw MacSettingsFailure.invalid("自动入账正在处理中，请完成后再变更本位币") }
        guard !context.hasChanges, plan.signature == (try signature(context)) else { throw Failure.changed }
        let backup = try MacNativeBackup.create(in: context)
        let folder: URL
        if MacPreferences.isTesting { folder = FileManager.default.temporaryDirectory.appendingPathComponent("FinTrack-V13-backups") }
        else { folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FinTrackMac/Backups") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try backup.write(to: folder.appendingPathComponent(UUID().uuidString + ".fintrack"), options: .atomic)
        try MacRecoveryJournal.perform(in: context) {
        do { plan.apply(); try context.save(); MacRecoveryJournal.checkpoint("database"); MacPreferences.defaults.set(plan.currency, forKey: "base_currency"); MacPreferences.defaults.set(plan.budgets, forKey: "v2_budgets") }
        catch { context.rollback(); throw error }
        }
    }
}
