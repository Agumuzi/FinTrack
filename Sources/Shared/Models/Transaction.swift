import Foundation
import SwiftData

enum TransactionType: String, CaseIterable, Codable {
    case income = "Income"
    case expense = "Expense"
}

@Model
final class Transaction {
    var id: UUID
    var ownerUID: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedDeviceID: String
    var syncVersion: Int

    // Audit note:
    // - originalAmount/originalCurrency are the canonical source values entered by the user.
    // - baseAmount/baseCurrencyCode/exchangeRateToBase are the persisted bookkeeping snapshot used by analytics,
    //   export, and cross-currency consistency.
    // - amount/currency below are backward-compatible accessors only; they intentionally map to the base snapshot
    //   and should not be converted to separate persisted schema fields or @Transient without a migration task.
    // - signedAmount/signedOriginalAmount/usesForeignCurrency are derived helpers and are not persisted.
    //
    // Migration posture for this phase: keep schema unchanged, document semantics first.
    // Original transaction values
    var originalAmount: Double
    var originalCurrency: String

    // Base-currency snapshot values saved at record time
    var baseAmount: Double
    var baseCurrencyCode: String
    var exchangeRateToBase: Double

    var type: String
    var category: String
    var note: String?
    var date: Date

    var typedType: TransactionType {
        get { TransactionType(rawValue: type) ?? .expense }
        set { type = newValue.rawValue }
    }

    // Backward-compatible accessors used by the current app.
    // These are semantic aliases over persisted baseAmount/baseCurrencyCode.
    var amount: Double {
        get { baseAmount }
        set { baseAmount = newValue }
    }

    var currency: String {
        get { baseCurrencyCode }
        set { baseCurrencyCode = newValue }
    }

    var signedAmount: Double {
        typedType == .expense ? -baseAmount : baseAmount
    }

    var signedOriginalAmount: Double {
        typedType == .expense ? -originalAmount : originalAmount
    }

    var usesForeignCurrency: Bool {
        originalCurrency != baseCurrencyCode
    }

    init(
        id: UUID = UUID(),
        ownerUID: String? = nil,
        amount: Double,
        currency: String,
        type: String,
        category: String,
        note: String? = nil,
        date: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        lastModifiedDeviceID: String = SyncMetadataDefaults.currentDeviceID,
        syncVersion: Int = 1,
        originalAmount: Double? = nil,
        originalCurrency: String? = nil,
        exchangeRateToBase: Double = 1.0,
        baseAmount: Double? = nil,
        baseCurrencyCode: String? = nil
    ) {
        let resolvedOriginalAmount = originalAmount ?? amount
        let resolvedOriginalCurrency = originalCurrency ?? currency
        let resolvedBaseAmount = baseAmount ?? amount
        let resolvedBaseCurrencyCode = baseCurrencyCode ?? currency

        self.id = id
        self.ownerUID = ownerUID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastModifiedDeviceID = lastModifiedDeviceID
        self.syncVersion = syncVersion
        self.originalAmount = resolvedOriginalAmount
        self.originalCurrency = resolvedOriginalCurrency
        self.baseAmount = resolvedBaseAmount
        self.baseCurrencyCode = resolvedBaseCurrencyCode
        self.exchangeRateToBase = exchangeRateToBase
        self.type = type
        self.category = category
        self.note = note
        self.date = date
    }

    convenience init(
        id: UUID = UUID(),
        ownerUID: String? = nil,
        amount: Double,
        currency: String,
        type: TransactionType,
        category: String,
        note: String? = nil,
        date: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        lastModifiedDeviceID: String = SyncMetadataDefaults.currentDeviceID,
        syncVersion: Int = 1,
        originalAmount: Double? = nil,
        originalCurrency: String? = nil,
        exchangeRateToBase: Double = 1.0,
        baseAmount: Double? = nil,
        baseCurrencyCode: String? = nil
    ) {
        self.init(
            id: id,
            ownerUID: ownerUID,
            amount: amount,
            currency: currency,
            type: type.rawValue,
            category: category,
            note: note,
            date: date,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastModifiedDeviceID: lastModifiedDeviceID,
            syncVersion: syncVersion,
            originalAmount: originalAmount,
            originalCurrency: originalCurrency,
            exchangeRateToBase: exchangeRateToBase,
            baseAmount: baseAmount,
            baseCurrencyCode: baseCurrencyCode
        )
    }
}
