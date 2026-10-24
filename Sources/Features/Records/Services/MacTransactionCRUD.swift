import Foundation
import SwiftData

/// V1.5 Mac input adapter built on the ORIGINAL Transaction + Category @Model
/// and ORIGINAL FinancialPrecision. Does not introduce an alternative ledger.
@MainActor
enum MacTransactionCRUD {
    enum PostingError: LocalizedError {
        case amountRequired
        case amountOutsideSafeRange
        case categoryRequired
        case mixedBaseCurrencies
        case foreignCurrencyEdit
        case invalidBookCurrency
        case generatedPostingProtected

        var errorDescription: String? {
            switch self {
            case .amountRequired: "Enter a positive amount with at most one decimal separator."
            case .amountOutsideSafeRange: "Amount is invalid, too small after rounding, or larger than 1 trillion."
            case .categoryRequired: "Enter a category."
            case .mixedBaseCurrencies: "Existing records use multiple base currencies. Convert the ledger in Settings before editing."
            case .foreignCurrencyEdit: "Enter the original currency and a valid exchange rate before editing this foreign-currency record."
            case .invalidBookCurrency: "Choose an explicit three-letter bookkeeping currency."
            case .generatedPostingProtected: "Generated bank or recurring receipts must be reconciled in Finance; direct changes could corrupt posting status."
            }
        }
    }

    struct Draft {
        var type: TransactionType
        var amountText: String
        var category: String
        var note: String
        var date: Date
    }

    static func isProtectedGeneratedPosting(_ transaction: Transaction) -> Bool {
        let note = transaction.note ?? ""
        return note.contains("[FTDep:") || note.contains("[FTRec:") || note.contains("[FTLoan:")
    }

    private static func cleanCurrency(_ value: String) throws -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard cleaned.count == 3, cleaned.unicodeScalars.allSatisfy({
            $0.value >= 65 && $0.value <= 90
        }) else { throw PostingError.invalidBookCurrency }
        return cleaned
    }

    /// Only a single previously persisted base currency can accept new
    /// postings. The user default is used exclusively for an empty ledger.
    static func bookCurrency(
        transactions: [Transaction], preferredCurrency: String
    ) throws -> String {
        let currencies = Set(transactions.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        if currencies.count > 1 { throw PostingError.mixedBaseCurrencies }
        return try cleanCurrency(currencies.first ?? preferredCurrency)
    }

    /// Editing text is independent of display preferences. Untouched legacy values round-trip exactly.
    static func amountEditingText(_ value: Double) -> String { String(value) }
    static func editedAmount(_ text: String, original: Double) throws -> Double {
        if text == amountEditingText(original), original.isFinite, original > 0, original <= 1_000_000_000_000 { return original }
        return try amount(text)
    }

    static func amount(_ text: String) throws -> Double {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !input.isEmpty,
              input.allSatisfy({ ("0123456789.".contains($0)) }),
              input.filter({ $0 == "." }).count <= 1,
              let decimal = Decimal(string: input, locale: Locale(identifier: "en_US_POSIX")),
              decimal > 0 else { throw PostingError.amountRequired }
        let number = NSDecimalNumber(decimal: decimal).doubleValue
        guard number.isFinite, number <= 1_000_000_000_000 else {
            throw PostingError.amountOutsideSafeRange
        }
        let rounded = FinancialPrecision.roundAmountForStorage(number)
        guard rounded.isFinite, rounded > 0 else { throw PostingError.amountOutsideSafeRange }
        return rounded
    }

    static func validatedCategory(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed.count <= 100 else { throw PostingError.categoryRequired }
        return trimmed
    }

    /// Uses the same Category @Model name/type data as the original app.
    /// A new category and its transaction are committed in the SAME save.
    private static func ensureCategory(
        _ category: String, type: TransactionType, in context: ModelContext
    ) throws -> String {
        let existing = try context.fetch(FetchDescriptor<FinTrackMac.Category>())
        if let matched = existing.first(where: {
            $0.deletedAt == nil && $0.type == type.rawValue
                && $0.name.localizedCaseInsensitiveCompare(category) == .orderedSame
        }) {
            return matched.name
        }
        let canonical = CategoryUsageHelper.canonicalCategoryName(category, type: type.rawValue)
        if let matched = existing.first(where: { $0.deletedAt == nil && $0.type == type.rawValue && $0.name.localizedCaseInsensitiveCompare(canonical) == .orderedSame }) {
            return matched.name
        }
        context.insert(FinTrackMac.Category(name: canonical, type: type.rawValue))
        return canonical
    }

    @discardableResult
    static func create(
        _ draft: Draft, currency: String, originalCurrency: String? = nil,
        exchangeRate: Double? = nil, actualBaseAmount: Double? = nil, in context: ModelContext
    ) throws -> Transaction {
        let amount = try amount(draft.amountText)
        let category = try validatedCategory(draft.category)
        let book = try cleanCurrency(currency)
        _ = try MacCurrency.ledgerCurrency(in: context, preferred: book)
        let snapshot: MacCurrencySnapshot
        if let actualBaseAmount {
            snapshot = try MacBankSettlement.snapshot(originalAmount:amount,actualBaseAmount:actualBaseAmount,original:originalCurrency ?? book,base:book)
        } else {
            snapshot = try MacCurrency.snapshot(amount:amount,original:originalCurrency ?? book,base:book,rate:exchangeRate)
        }
        do {
            let storedCategory = try ensureCategory(category, type: draft.type, in: context)
            let transaction = Transaction(
                amount: snapshot.baseAmount, currency: book, type: draft.type,
                category: storedCategory,
                note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                date: draft.date,
                originalAmount: snapshot.originalAmount, originalCurrency: snapshot.originalCurrency,
                exchangeRateToBase: snapshot.rate, baseAmount: snapshot.baseAmount, baseCurrencyCode: book
            )
            context.insert(transaction)
            try context.save()
            return transaction
        } catch {
            context.rollback()
            throw error
        }
    }

    static func update(
        _ transaction: Transaction, with draft: Draft,
        currency: String, originalCurrency: String? = nil,
        exchangeRate: Double? = nil, actualBaseAmount: Double? = nil, in context: ModelContext
    ) throws {
        guard !isProtectedGeneratedPosting(transaction) else {
            throw PostingError.generatedPostingProtected
        }
        let book = try cleanCurrency(currency)
        guard transaction.baseCurrencyCode == book,
              originalCurrency != nil || (transaction.originalCurrency == book && transaction.exchangeRateToBase == 1)
        else {
            throw PostingError.foreignCurrencyEdit
        }
        let amount = try editedAmount(draft.amountText, original: transaction.originalAmount)
        let category = try validatedCategory(draft.category)
        _ = try MacCurrency.ledgerCurrency(in: context, preferred: book)
        let source = try MacCurrency.code(originalCurrency ?? book)
        let snapshot: MacCurrencySnapshot
        let unchangedAmount = draft.amountText == amountEditingText(transaction.originalAmount) && source == transaction.originalCurrency
        let unchangedSettlement = actualBaseAmount.map { $0 == transaction.baseAmount } ?? ((exchangeRate ?? transaction.exchangeRateToBase) == transaction.exchangeRateToBase)
        if unchangedAmount, unchangedSettlement,
           transaction.originalAmount.isFinite, transaction.originalAmount > 0,
           transaction.baseAmount.isFinite, transaction.baseAmount > 0, transaction.baseAmount <= 1e12,
           transaction.exchangeRateToBase.isFinite, transaction.exchangeRateToBase > 0,
           abs(FinancialPrecision.roundAmountForStorage(transaction.originalAmount * transaction.exchangeRateToBase) - FinancialPrecision.roundAmountForStorage(transaction.baseAmount)) < 0.005,
           source != book || (transaction.exchangeRateToBase == 1 && abs(transaction.originalAmount - transaction.baseAmount) < 1e-6) {
            snapshot = .init(originalAmount: transaction.originalAmount, originalCurrency: source,
                             baseAmount: transaction.baseAmount, baseCurrency: book, rate: transaction.exchangeRateToBase)
        } else if let actualBaseAmount {
            let candidate = try MacBankSettlement.snapshot(originalAmount:amount,actualBaseAmount:actualBaseAmount,original:originalCurrency ?? book,base:book)
            // A non-financial edit must not re-derive even the last floating bit
            // of an existing, valid snapshot. Explicit amount changes derive anew.
            let unchanged = amount == transaction.originalAmount && candidate.originalCurrency == transaction.originalCurrency && candidate.baseAmount == transaction.baseAmount
            if unchanged, (try? MacBankSettlement.validateSavedSnapshot(amount:amount,actual:candidate.baseAmount,source:candidate.originalCurrency,base:book,rate:transaction.exchangeRateToBase)) != nil {
                snapshot = .init(originalAmount:amount,originalCurrency:candidate.originalCurrency,baseAmount:transaction.baseAmount,baseCurrency:book,rate:transaction.exchangeRateToBase)
            } else { snapshot = candidate }
        } else {
            snapshot = try MacCurrency.snapshot(amount:amount,original:originalCurrency ?? book,base:book,rate:exchangeRate)
        }
        do {
            let storedCategory = try ensureCategory(category, type: draft.type, in: context)
            transaction.originalAmount = snapshot.originalAmount
            transaction.originalCurrency = snapshot.originalCurrency
            transaction.baseAmount = snapshot.baseAmount
            transaction.exchangeRateToBase = snapshot.rate
            transaction.typedType = draft.type
            transaction.category = storedCategory
            transaction.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            transaction.date = draft.date
            transaction.updatedAt = Date()
            if transaction.syncVersion < Int.max { transaction.syncVersion += 1 }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func delete(_ transaction: Transaction, in context: ModelContext) throws {
        guard !isProtectedGeneratedPosting(transaction) else {
            throw PostingError.generatedPostingProtected
        }
        context.delete(transaction) // Original TransactionManager.delete also hard deletes.
        do { try context.save() }
        catch {
            context.rollback()
            throw error
        }
    }

    static func totals(
        transactions: [Transaction], currency: String
    ) -> (income: Double, expense: Double, net: Double) {
        let scoped = transactions.filter {
            $0.deletedAt == nil && $0.baseCurrencyCode == currency
        }
        let income = scoped.filter { $0.typedType == .income }
            .reduce(0.0) { $0 + $1.baseAmount }
        let expense = scoped.filter { $0.typedType == .expense }
            .reduce(0.0) { $0 + $1.baseAmount }
        return (
            FinancialPrecision.roundAmountForDisplay(income),
            FinancialPrecision.roundAmountForDisplay(expense),
            FinancialPrecision.roundAmountForDisplay(income - expense)
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
