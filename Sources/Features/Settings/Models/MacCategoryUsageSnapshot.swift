import Foundation
import SwiftData

/// One read-only aggregate per ledger change, shared by all category rows.
/// Historical tombstones intentionally still block deletion and follow renames.
struct MacCategoryUsageSnapshot {
    struct Key: Hashable { var type: String; var name: String }
    var references: [Key: Int] = [:]
    var budgetIDs: [UUID: Int] = [:]

    func count(for row: Category) -> Int {
        references[Key(type: row.type, name: row.name), default: 0] + budgetIDs[row.id, default: 0]
    }
    @MainActor func sorted(_ rows: [Category]) -> [Category] {
        let styles: [String: MacCategoryStyle] = MacSettingsStore.load("v2_category_styles", fallback: [:])
        return rows.sorted {
            let a = count(for: $0), b = count(for: $1)
            if a != b { return a > b }
            let first = MacCategoryCatalog.style(name: $0.name, type: $0.type, in: styles).order
            let second = MacCategoryCatalog.style(name: $1.name, type: $1.type, in: styles).order
            if first != second { return first < second }
            return $0.name == $1.name ? $0.id.uuidString < $1.id.uuidString : $0.name < $1.name
        }
    }
    @MainActor static func load(in context: ModelContext) throws -> Self {
        var result = Self()
        for row in try context.fetch(FetchDescriptor<Transaction>()) {
            result.references[Key(type: row.type, name: row.category), default: 0] += 1
        }
        for row in try context.fetch(FetchDescriptor<RecurringTransaction>()) {
            result.references[Key(type: row.typedType.storageValue, name: row.category), default: 0] += 1
        }
        for row in try context.fetch(FetchDescriptor<LoanRule>()) {
            result.references[Key(type: "Expense", name: row.category), default: 0] += 1
        }
        let budgets: [MacBudget] = MacSettingsStore.load("v2_budgets", fallback: [])
        for budget in budgets {
            if let id = budget.categoryID { result.budgetIDs[id, default: 0] += 1 }
            else if let name = budget.categoryName {
                result.references[Key(type: "Expense", name: name), default: 0] += 1
            }
        }
        return result
    }
}
