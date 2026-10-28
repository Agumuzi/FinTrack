import Foundation
import SwiftData

@MainActor
enum MacDataManagement {
    enum Failure: LocalizedError {
        case generatedReceipts, protectedCategory
        var errorDescription: String? {
            switch self {
            case .generatedReceipts: "Generated finance receipts cannot be deleted from Records."
            case .protectedCategory: "Loan and Deposit categories cannot be renamed."
            }
        }
    }
    /// Repair catalogs created by older imports without changing any financial row.
    /// A new ledger stays empty; categories only come from the user's own records.
    static func reconcileCategories(in context: ModelContext) throws {
        guard !context.hasChanges else { throw MacSettingsFailure.invalid("请先保存或取消当前编辑，再更新分类目录") }
        do {
            try registerReferencedCategories(in: context)
            if context.hasChanges { try context.save() }
        } catch { context.rollback(); throw error }
    }

    /// Caller owns the save so CSV records and their catalog entries commit atomically.
    static func registerReferencedCategories(in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<Category>())
        var names = Dictionary(grouping: existing.filter { $0.deletedAt == nil }, by: \.type)
            .mapValues { Set($0.map(\.name)) }
        var referenced: [String: Set<String>] = [:]
        for row in try context.fetch(FetchDescriptor<Transaction>()) where row.deletedAt == nil {
            referenced[row.type, default: []].insert(row.category)
        }
        for row in try context.fetch(FetchDescriptor<RecurringTransaction>()) where row.deletedAt == nil {
            referenced[row.typedType.storageValue, default: []].insert(row.category)
        }
        for row in try context.fetch(FetchDescriptor<LoanRule>()) where row.deletedAt == nil {
            referenced["Expense", default: []].insert(row.category)
        }
        for type in ["Expense", "Income"] {
            for name in (referenced[type] ?? []).sorted()
                where !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && names[type, default: []].insert(name).inserted {
                // Match the stored name exactly: localization/case aliases must not
                // silently merge distinct categories or orphan exact-name references.
                if let row = existing.first(where: { $0.type == type && $0.name == name }) {
                    row.deletedAt = nil; row.updatedAt = Date()
                } else {
                    context.insert(Category(name: name, type: type))
                }
            }
        }
    }
    static func clearLedger(in context: ModelContext) throws {
        try MacRecoveryJournal.assertWritable(in:context)
        guard !MacAutomaticPosting.isRunning else { throw MacSettingsFailure.invalid("自动入账正在处理中，请完成后再清空账本") }
        do {
            for row in try context.fetch(FetchDescriptor<RecurringTransaction>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<LoanRule>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<DepositRecord>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<Transaction>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<Category>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<Goal>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<FinancialProfile>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<Account>()) { context.delete(row) }
            try context.save()
        } catch { context.rollback(); throw error }
    }

    static func deleteTransactions(_ rows: [Transaction], in context: ModelContext) throws {
        try MacRecoveryJournal.assertWritable(in:context)
        guard !rows.contains(where: MacTransactionCRUD.isProtectedGeneratedPosting) else {
            throw Failure.generatedReceipts
        }
        do {
            for row in rows { context.delete(row) }
            try context.save()
        } catch { context.rollback(); throw error }
    }

    /// Original category rename/merge updates transaction, recurring and loan names.
    static func rename(_ category: Category, to name: String, in context: ModelContext,
                       save: ((ModelContext) throws -> Void)? = nil,
                       recordTiming: ((String, TimeInterval) -> Void)? = nil) throws {
        let metadataStart = recordTiming.map { _ in ProcessInfo.processInfo.systemUptime }
        func measure<T>(_ phase: String, _ work: () throws -> T) rethrows -> T {
            guard let recordTiming else { return try work() }
            let start = ProcessInfo.processInfo.systemUptime
            defer { recordTiming(phase, ProcessInfo.processInfo.systemUptime - start) }
            return try work()
        }
        if CategoryUsageHelper.isProtectedCategory(category) {
            let clean = try MacTransactionCRUD.validatedCategory(name)
            let catalog = try context.fetch(FetchDescriptor<Category>())
            guard !catalog.contains(where: { $0.deletedAt == nil && $0.id != category.id && $0.type == category.type && ($0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame || MacOverviewStyle.category($0.name).localizedCaseInsensitiveCompare(clean) == .orderedSame) }) else { throw MacSettingsFailure.invalid("系统分类显示名称不能与其他分类重复") }
            var style = MacCategoryCatalog.style(name: category.name, type: category.type)
            style.displayName = clean
            try MacCategoryCatalog.saveStyle(style, name: category.name, type: category.type)
            return
        }
        let name = try MacTransactionCRUD.validatedCategory(CategoryUsageHelper.canonicalCategoryName(name, type: category.type))
        guard !context.hasChanges else { throw MacSettingsFailure.invalid("请先保存或取消当前编辑，再重命名分类") }
        let old = category.name
        let categoryType = category.type
        let target = try context.fetch(FetchDescriptor<Category>()).first {
            $0.id != category.id && $0.type == category.type && $0.deletedAt == nil && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        let finalName = target?.name ?? name
        var budgets: [MacBudget] = MacSettingsStore.load("v2_budgets", fallback: [])
        if category.type == "Expense", let target {
            let sourceBudgets = budgets.filter { $0.categoryID == category.id || ($0.categoryID == nil && $0.categoryName == old) }
            let targetBudgets = budgets.filter { $0.categoryID == target.id || ($0.categoryID == nil && $0.categoryName == target.name) }
            guard !sourceBudgets.contains(where: { source in targetBudgets.contains { $0.month == source.month && $0.currency == source.currency } })
            else { throw MacSettingsFailure.invalid("两个分类在同月均有预算，请先调整预算再合并，避免重复统计") }
        }
        if category.type == "Expense" {
            for index in budgets.indices where budgets[index].categoryID == category.id || (budgets[index].categoryID == nil && budgets[index].categoryName == old) {
                budgets[index].categoryID = target?.id ?? category.id; budgets[index].categoryName = finalName
            }
        }
        let budgetBytes = try JSONEncoder().encode(budgets)
        var styles: [String: MacCategoryStyle] = MacSettingsStore.load("v2_category_styles", fallback: [:])
        let oldKey = MacCategoryCatalog.key(name: old, type: categoryType)
        let newKey = MacCategoryCatalog.key(name: finalName, type: categoryType)
        if oldKey != newKey {
            if target == nil, let oldStyle = styles[oldKey] { styles[newKey] = oldStyle }
            styles.removeValue(forKey: oldKey)
        }
        let styleBytes = try JSONEncoder().encode(styles)
        if let metadataStart { recordTiming?("validation-budget-style", ProcessInfo.processInfo.systemUptime - metadataStart) }
        try MacRecoveryJournal.perform(in: context) {
        do {
            let transactions = try measure("transaction-fetch") {
                try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.type == categoryType && $0.category == old }))
            }
            measure("transaction-update") {
                for row in transactions { row.category = finalName; row.updatedAt = Date() }
            }
            try measure("rules-loans-catalog") {
                for row in try context.fetch(FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.category == old })) where row.typedType.storageValue == categoryType {
                    row.category = finalName; row.updatedAt = Date()
                }
                if category.type == "Expense" {
                    for row in try context.fetch(FetchDescriptor<LoanRule>(predicate: #Predicate { $0.category == old })) {
                        row.category = finalName; row.updatedAt = Date()
                    }
                }
                if target != nil { context.delete(category) }
                else { category.name = finalName; category.updatedAt = Date() }
            }
            try measure("database-save") {
                if let save { try save(context) } else { try context.save() }
            }
            MacRecoveryJournal.checkpoint("database")
            measure("preferences-commit") {
                MacPreferences.defaults.set(budgetBytes, forKey: "v2_budgets")
                MacPreferences.defaults.set(styleBytes, forKey: "v2_category_styles")
            }
        } catch { context.rollback(); throw error }
        }
    }
}
