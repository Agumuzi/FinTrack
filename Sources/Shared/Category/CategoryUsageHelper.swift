import Foundation
import SwiftData

struct CategoryUsageHelper {
    private struct UsageRecord: Codable {
        var useCount: Int
        var lastUsedAt: Date
    }

    static let customCategoryName = "Custom"
    static let allCategoriesName = "All"
    static let loanCategoryName = "Loan"
    static let depositCategoryName = "Deposit"

    private static let usageDefaultsKey = "categoryUsageHistory"

    static let defaultExpenseNames = [
        "Loan",
        "Supermarket",
        "Dining",
        "Transport",
        "Shopping",
        "Health",
        "Travel",
        "Other"
    ]

    static let defaultIncomeNames = [
        "Salary",
        "Bonus",
        "Investment",
        "Deposit",
        "Gift",
        "Other"
    ]

    static func localizedDisplayName(for name: String) -> String {
        #if os(macOS)
        if name == depositCategoryName || name == loanCategoryName {
            let type = name == depositCategoryName ? "Income" : "Expense"
            if let alias = MacCategoryCatalog.style(name: name, type: type).displayName, !alias.isEmpty { return alias }
        }
        #endif
        switch name {
        case customCategoryName:
            return LanguageManager.shared.ui(UIStringKey.Common.custom)
        case allCategoriesName:
            return LanguageManager.shared.ui(UIStringKey.Common.all)
        case "Supermarket":
            return LanguageManager.shared.ui(UIStringKey.Category.supermarket)
        case "Dining":
            return LanguageManager.shared.ui(UIStringKey.Category.dining)
        case "Transport":
            return LanguageManager.shared.ui(UIStringKey.Category.transport)
        case "Shopping":
            return LanguageManager.shared.ui(UIStringKey.Category.shopping)
        case "Health":
            return LanguageManager.shared.ui(UIStringKey.Category.health)
        case "Travel":
            return LanguageManager.shared.ui(UIStringKey.Category.travel)
        case "Other":
            return LanguageManager.shared.ui(UIStringKey.Category.other)
        case "Loan":
            return LanguageManager.shared.ui(UIStringKey.Category.loan)
        case "Salary":
            return LanguageManager.shared.ui(UIStringKey.Category.salary)
        case "Bonus":
            return LanguageManager.shared.ui(UIStringKey.Category.bonus)
        case "Investment":
            return LanguageManager.shared.ui(UIStringKey.Category.investment)
        case "Deposit":
            return LanguageManager.shared.ui(UIStringKey.Category.deposit)
        case "Gift":
            return LanguageManager.shared.ui(UIStringKey.Category.gift)
        default:
            return name
        }
    }

    static func localizedTypeName(for type: String) -> String {
        switch type {
        case "Expense":
            return LanguageManager.shared.ui(UIStringKey.Common.expense)
        case "Income":
            return LanguageManager.shared.ui(UIStringKey.Common.income)
        default:
            return type
        }
    }

    static func canonicalCategoryName(_ name: String, type: String) -> String {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanName.isEmpty == false else { return cleanName }

        if let protectedName = protectedCategoryName(matching: cleanName, type: type) {
            return protectedName
        }

        return cleanName
    }

    static func selectionItems(from categoryNames: [String]) -> [CategoryChipItem] {
        categoryNames.map {
            CategoryChipItem(
                title: localizedDisplayName(for: $0),
                value: $0
            )
        } + [
            CategoryChipItem(
                title: localizedDisplayName(for: customCategoryName),
                value: customCategoryName
            )
        ]
    }

    static func sortedCategoryNames(
        for type: String,
        categories: [Category]
    ) -> [String] {
        let availableNames = categories
            .filter { $0.type == type }
            .map { $0.name }

        guard !availableNames.isEmpty else { return [] }

        return availableNames.sorted {
            compareCategoryNames($0, $1, type: type)
        }
    }

    static func sortedCategoriesForManagement(
        type: String,
        categories: [Category]
    ) -> [Category] {
        let availableCategories = categories.filter { $0.type == type }
        guard !availableCategories.isEmpty else { return [] }

        let protectedCategories = availableCategories
            .filter { category in
                isProtectedCategory(category)
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

        let sortableCategories = availableCategories.filter { category in
            !isProtectedCategory(category)
        }
        let rankedCategories = sortableCategories.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return protectedCategories + rankedCategories
    }

    static func bestDefaultCategory(
        for type: String,
        categories: [Category]
    ) -> String? {
        sortedCategoryNames(
            for: type,
            categories: categories
        ).first
    }

    static func searchableCategoryNames(
        selectedType: String,
        categories: [Category]
    ) -> [String] {
        if selectedType == "Expense" || selectedType == "Income" {
            return sortedCategoryNames(
                for: selectedType,
                categories: categories
            )
        }

        let expense = sortedCategoryNames(
            for: "Expense",
            categories: categories
        )

        let income = sortedCategoryNames(
            for: "Income",
            categories: categories
        )

        return expense + income.filter { !expense.contains($0) }
    }

    static func recordUsage(categoryName: String, type: String) {
        let cleanName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanType = type.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanName.isEmpty, !cleanType.isEmpty else { return }

        var records = usageRecords()
        let key = usageKey(name: cleanName, type: cleanType)
        var record = records[key] ?? UsageRecord(useCount: 0, lastUsedAt: .distantPast)
        record.useCount += 1
        record.lastUsedAt = Date()
        records[key] = record
        saveUsageRecords(records)
    }

    static func seedDefaultCategoriesIfNeeded(
        in modelContext: ModelContext,
        existingCategories: [Category]
    ) {
        let existingPairs = Set(existingCategories.map { "\($0.type)::\($0.name)" })
        let hasExpenseCategories = existingCategories.contains { $0.type == "Expense" }
        let hasIncomeCategories = existingCategories.contains { $0.type == "Income" }
        var insertedAny = false

        if !hasExpenseCategories {
            for item in defaultExpenseNames {
                let key = "Expense::\(item)"
                if !existingPairs.contains(key) {
                    modelContext.insert(Category(name: item, type: "Expense"))
                    insertedAny = true
                }
            }
        }

        if !hasIncomeCategories {
            for item in defaultIncomeNames {
                let key = "Income::\(item)"
                if !existingPairs.contains(key) {
                    modelContext.insert(Category(name: item, type: "Income"))
                    insertedAny = true
                }
            }
        }

        if !existingPairs.contains("Expense::\(loanCategoryName)") {
            modelContext.insert(Category(name: loanCategoryName, type: "Expense"))
            insertedAny = true
        }

        if !existingPairs.contains("Income::\(depositCategoryName)") {
            modelContext.insert(Category(name: depositCategoryName, type: "Income"))
            insertedAny = true
        }

        if insertedAny {
            PersistenceLogger.save(modelContext)
        }
    }

    static func finalCategory(
        selectedCategory: String,
        customCategory: String
    ) -> String {
        selectedCategory == customCategoryName
            ? customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
            : selectedCategory
    }

    static func resolveSelectedCategory(
        storedCategory: String,
        type: String,
        categories: [Category]
    ) -> (selectedCategory: String, customCategory: String) {
        let names = categories
            .filter { $0.type == type }
            .map { $0.name }

        if names.contains(storedCategory) {
            return (storedCategory, "")
        }

        return (customCategoryName, storedCategory)
    }

    static func defaultCategorySelection(
        available: [String],
        currentSelection: String,
        customCategory: String,
        fallback: String?
    ) -> String {
        guard !available.isEmpty else { return "" }

        if available.contains(currentSelection) {
            return currentSelection
        }

        if currentSelection == "Custom", !customCategory.isEmpty {
            return currentSelection
        }

        return fallback ?? available.first ?? ""
    }

    static func isProtectedCategory(_ category: Category) -> Bool {
        (category.type == "Expense" && category.name == loanCategoryName) ||
        (category.type == "Income" && category.name == depositCategoryName)
    }

    @discardableResult
    static func ensureCategoryExists(
        name: String,
        type: String,
        in modelContext: ModelContext,
        existingCategories: [Category]
    ) -> Category? {
        let cleanName = canonicalCategoryName(name, type: type)
        let cleanType = type.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanName.isEmpty, !cleanType.isEmpty else { return nil }

        if let existingCategory = existingCategories.first(where: {
            $0.type == cleanType &&
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(cleanName) == .orderedSame
        }) {
            return existingCategory
        }

        let category = Category(name: cleanName, type: cleanType)
        modelContext.insert(category)
        return category
    }

    private static func compareCategoryNames(_ lhs: String, _ rhs: String, type: String) -> Bool {
        let records = usageRecords()
        let lhsRecord = records[usageKey(name: lhs, type: type)] ?? UsageRecord(useCount: 0, lastUsedAt: .distantPast)
        let rhsRecord = records[usageKey(name: rhs, type: type)] ?? UsageRecord(useCount: 0, lastUsedAt: .distantPast)

        if lhsRecord.useCount != rhsRecord.useCount {
            return lhsRecord.useCount > rhsRecord.useCount
        }

        if lhsRecord.lastUsedAt != rhsRecord.lastUsedAt {
            return lhsRecord.lastUsedAt > rhsRecord.lastUsedAt
        }

        return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }

    private static func usageKey(name: String, type: String) -> String {
        "\(type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())::\(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private static func protectedCategoryName(matching name: String, type: String) -> String? {
        let normalizedCandidate = normalizedCategoryLookupName(name)

        switch type {
        case "Expense":
            let normalizedLoanNames = [
                normalizedCategoryLookupName(loanCategoryName),
                normalizedCategoryLookupName(localizedDisplayName(for: loanCategoryName))
            ]
            return normalizedLoanNames.contains(normalizedCandidate) ? loanCategoryName : nil
        case "Income":
            let normalizedDepositNames = [
                normalizedCategoryLookupName(depositCategoryName),
                normalizedCategoryLookupName(localizedDisplayName(for: depositCategoryName))
            ]
            return normalizedDepositNames.contains(normalizedCandidate) ? depositCategoryName : nil
        default:
            return nil
        }
    }

    private static func normalizedCategoryLookupName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func usageRecords() -> [String: UsageRecord] {
        guard let data = UserDefaults.standard.data(forKey: usageDefaultsKey),
              let records = try? JSONDecoder().decode([String: UsageRecord].self, from: data) else {
            return [:]
        }
        return records
    }

    private static func saveUsageRecords(_ records: [String: UsageRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: usageDefaultsKey)
    }
}

struct CategorySelectionState {
    var selectedCategory = ""
    var customCategory = ""

    var finalCategory: String {
        CategoryUsageHelper.finalCategory(
            selectedCategory: selectedCategory,
            customCategory: customCategory
        )
    }

    var isCustomSelected: Bool {
        selectedCategory == CategoryUsageHelper.customCategoryName
    }

    mutating func select(_ category: String) {
        selectedCategory = category

        if category != CategoryUsageHelper.customCategoryName {
            customCategory = ""
        }
    }

    mutating func resetForTypeChange(
        available: [String],
        fallback: String?
    ) {
        selectedCategory = ""
        customCategory = ""
        applyDefaultSelection(available: available, fallback: fallback)
    }

    mutating func applyDefaultSelection(
        available: [String],
        fallback: String?
    ) {
        selectedCategory = CategoryUsageHelper.defaultCategorySelection(
            available: available,
            currentSelection: selectedCategory,
            customCategory: customCategory,
            fallback: fallback
        )
    }

    mutating func applyStoredCategory(
        _ storedCategory: String,
        type: String,
        categories: [Category]
    ) {
        let resolved = CategoryUsageHelper.resolveSelectedCategory(
            storedCategory: storedCategory,
            type: type,
            categories: categories
        )

        selectedCategory = resolved.selectedCategory
        customCategory = resolved.customCategory
    }

    mutating func resolveCustomSelectionAfterSave() {
        guard isCustomSelected else { return }

        let resolved = finalCategory
        if !resolved.isEmpty {
            selectedCategory = resolved
        }
    }
}

struct CategoryFilterState {
    var selectedCategory = ""

    mutating func select(_ category: String) {
        selectedCategory = category
    }

    mutating func reset() {
        selectedCategory = ""
    }
}
