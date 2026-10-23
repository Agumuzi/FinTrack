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
