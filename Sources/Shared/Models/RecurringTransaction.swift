import Foundation
import SwiftData

enum RecurringTransactionType: String, CaseIterable, Codable {
    case income
    case expense
}

extension RecurringTransactionType {
    static func fromStorage(_ rawValue: String) -> RecurringTransactionType {
        switch rawValue.lowercased() {
        case "income":
            return .income
        default:
            return .expense
        }
    }

    var storageValue: String {
        switch self {
        case .income:
            return "Income"
        case .expense:
            return "Expense"
        }
    }
}

enum RecurringIntervalUnit: String, CaseIterable, Codable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }
}

@Model
final class RecurringTransaction {
    var id: UUID
    var ownerUID: String?
    // Audit note:
    // - amount/currency remain the rule-definition values used by editor flows, notifications, and future executions.
    // - originalAmount/originalCurrency are persisted alongside them for generated transaction snapshots and
    //   rebase/conversion workflows; this looks redundant at first glance, but current call sites still rely on both.
    // - baseAmount/baseCurrencyCode/exchangeRateToBase are the persisted bookkeeping snapshot in the app base currency.
    // - typedType/typedIntervalUnit/usesForeignCurrency are derived helpers and are not persisted.
    //
    // Migration posture for this phase: do not mark duplicated-looking fields as @Transient until a dedicated
    // schema migration clarifies whether rule-definition and snapshot semantics can be merged safely.
    var originalAmount: Double
    var originalCurrency: String
    var baseAmount: Double
    var baseCurrencyCode: String
    var exchangeRateToBase: Double

    var title: String
    var amount: Double
    var currency: String
    var type: String
    var category: String
    var note: String?
    var projectIdentifier: String?

    var intervalValue: Int
    var intervalUnit: String

    var nextExecutionDate: Date
    var lastExecutionDate: Date?
    var endDate: Date?
    var isActive: Bool
    var notificationsEnabled: Bool
    var reminderDaysBefore: Int
    var reminderHour: Int
    var reminderMinute: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedDeviceID: String
    var syncVersion: Int

    var typedType: RecurringTransactionType {
        get { RecurringTransactionType.fromStorage(type) }
        set { type = newValue.storageValue }
    }

    var typedIntervalUnit: RecurringIntervalUnit {
        get { RecurringIntervalUnit(rawValue: intervalUnit) ?? .month }
        set { intervalUnit = newValue.rawValue }
    }

    var usesForeignCurrency: Bool {
        originalCurrency != baseCurrencyCode
    }

    init(
        id: UUID = UUID(),
        ownerUID: String? = nil,
        title: String,
        amount: Double,
        currency: String,
        type: String,
        category: String,
        note: String? = nil,
        projectIdentifier: String? = nil,
        intervalValue: Int,
        intervalUnit: String,
        nextExecutionDate: Date,
        lastExecutionDate: Date? = nil,
        endDate: Date? = nil,
        isActive: Bool = true,
        notificationsEnabled: Bool = false,
        reminderDaysBefore: Int = 0,
        reminderHour: Int = 9,
        reminderMinute: Int = 0,
        originalAmount: Double? = nil,
        originalCurrency: String? = nil,
        exchangeRateToBase: Double = 1.0,
        baseAmount: Double? = nil,
        baseCurrencyCode: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        lastModifiedDeviceID: String = SyncMetadataDefaults.currentDeviceID,
        syncVersion: Int = 1
    ) {
        let resolvedOriginalAmount = originalAmount ?? amount
        let resolvedOriginalCurrency = originalCurrency ?? currency
        let resolvedBaseAmount = baseAmount ?? amount
        let resolvedBaseCurrencyCode = baseCurrencyCode ?? currency

        self.id = id
        self.ownerUID = ownerUID
        self.originalAmount = resolvedOriginalAmount
        self.originalCurrency = resolvedOriginalCurrency
        self.baseAmount = resolvedBaseAmount
        self.baseCurrencyCode = resolvedBaseCurrencyCode
        self.exchangeRateToBase = exchangeRateToBase
        self.title = title
        self.amount = amount
        self.currency = currency
        self.type = type
        self.category = category
        self.note = note
        self.projectIdentifier = projectIdentifier
        self.intervalValue = intervalValue
        self.intervalUnit = intervalUnit
        self.nextExecutionDate = nextExecutionDate
        self.lastExecutionDate = lastExecutionDate
        self.endDate = endDate
        self.isActive = isActive
        self.notificationsEnabled = notificationsEnabled
        self.reminderDaysBefore = reminderDaysBefore
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastModifiedDeviceID = lastModifiedDeviceID
        self.syncVersion = syncVersion
    }

    convenience init(
        id: UUID = UUID(),
        ownerUID: String? = nil,
        title: String,
        amount: Double,
        currency: String,
        type: RecurringTransactionType,
        category: String,
        note: String? = nil,
        projectIdentifier: String? = nil,
        intervalValue: Int,
        intervalUnit: RecurringIntervalUnit,
        nextExecutionDate: Date,
        lastExecutionDate: Date? = nil,
        endDate: Date? = nil,
        isActive: Bool = true,
        notificationsEnabled: Bool = false,
        reminderDaysBefore: Int = 0,
        reminderHour: Int = 9,
        reminderMinute: Int = 0,
        originalAmount: Double? = nil,
        originalCurrency: String? = nil,
        exchangeRateToBase: Double = 1.0,
        baseAmount: Double? = nil,
        baseCurrencyCode: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        lastModifiedDeviceID: String = SyncMetadataDefaults.currentDeviceID,
        syncVersion: Int = 1
    ) {
        self.init(
            id: id,
            ownerUID: ownerUID,
            title: title,
            amount: amount,
            currency: currency,
            type: type.rawValue,
            category: category,
            note: note,
            projectIdentifier: projectIdentifier,
            intervalValue: intervalValue,
            intervalUnit: intervalUnit.rawValue,
            nextExecutionDate: nextExecutionDate,
            lastExecutionDate: lastExecutionDate,
            endDate: endDate,
            isActive: isActive,
            notificationsEnabled: notificationsEnabled,
            reminderDaysBefore: reminderDaysBefore,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute,
            originalAmount: originalAmount,
            originalCurrency: originalCurrency,
            exchangeRateToBase: exchangeRateToBase,
            baseAmount: baseAmount,
            baseCurrencyCode: baseCurrencyCode,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastModifiedDeviceID: lastModifiedDeviceID,
            syncVersion: syncVersion
        )
    }
}
