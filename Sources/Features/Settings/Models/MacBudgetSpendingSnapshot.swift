import Foundation

/// A render-local index. Each saved expense contributes in the original row
/// order, so rounding and category-ID/legacy-name semantics remain unchanged.
struct MacBudgetSpendingSnapshot {
    private struct Key: Hashable {
        var month: String
        var currency: String
        var category: String?
    }
    private var totals: [Key: Double] = [:]
    private var categoryNames: [UUID: String] = [:]

    init(rows: [Transaction], categories: [Category]) {
        for category in categories where categoryNames[category.id] == nil {
            categoryNames[category.id] = category.name
        }
        for row in rows where row.deletedAt == nil && row.typedType == .expense {
            let month = MacBudgetData.month(row.date), currency = row.baseCurrencyCode
            let amount = row.baseAmount
            totals[Key(month: month, currency: currency, category: nil), default: 0] += amount
            totals[Key(month: month, currency: currency, category: row.category), default: 0] += amount
        }
    }

    func spent(_ budget: MacBudget) -> Double {
        let name = budget.categoryID.flatMap { categoryNames[$0] } ?? budget.categoryName
        return FinancialPrecision.roundAmountForStorage(totals[Key(month: budget.month, currency: budget.currency, category: name), default: 0])
    }
}
