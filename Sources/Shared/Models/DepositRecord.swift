import Foundation
import SwiftData

enum DepositInterestSettlementMode: String, CaseIterable, Codable, Identifiable {
    case monthly = "Monthly"
    case monthlyCompound = "Monthly Compound"
    case maturity = "At Maturity"

    var id: String { rawValue }

    // These short codes are product display labels, not localized prose.
    var displayCode: String {
        switch self {
        case .monthly:
            return "MP"
        case .monthlyCompound:
            return "CM"
        case .maturity:
            return "SM"
        }
    }

    var pickerTitle: String {
        displayCode
    }

    func summaryText(durationText: String) -> String {
        "\(displayCode) · \(durationText)"
    }
}

enum DepositMaturityInterestHandling: String, CaseIterable, Codable, Identifiable {
    case payout = "Payout"
    case rollover = "Rollover"

    var id: String { rawValue }
}

@Model
final class DepositRecord {
    var id: UUID
    var ownerUID: String?
    var bankName: String
    var principal: Double
    var originalPrincipal: Double
    var originalCurrency: String
    var basePrincipal: Double
    var baseCurrencyCode: String
    var principalExchangeRateToBase: Double
    var annualInterestRate: Double
    var interestSettlementMode: String
    var expectedInterest: Double
    var baseExpectedInterest: Double
    var interestExchangeRateToBase: Double
    var isInterestManuallyEdited: Bool
    var currency: String
    var startDate: Date
    var maturityDate: Date
    var isActive: Bool
    var hasCreditedInterest: Bool
    var lastInterestPayoutDate: Date?
    var nextInterestPayoutDate: Date?
    var notificationsEnabled: Bool
    var reminderDaysBefore: Int
    var reminderHour: Int
    var reminderMinute: Int
    var note: String?
    var maturityInterestHandling: String?
    var sourceDepositID: UUID?
    var rolloverBasePrincipalAmount: Double?
    var rolloverBaseInterestAmount: Double?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedDeviceID: String
    var syncVersion: Int

    var typedInterestSettlementMode: DepositInterestSettlementMode {
        get { DepositInterestSettlementMode(rawValue: interestSettlementMode) ?? .maturity }
        set { interestSettlementMode = newValue.rawValue }
    }

    var typedMaturityInterestHandling: DepositMaturityInterestHandling {
        get { DepositMaturityInterestHandling(rawValue: maturityInterestHandling ?? "") ?? .payout }
        set { maturityInterestHandling = newValue.rawValue }
    }

    var resolvedRolloverBasePrincipalAmount: Double {
        get { rolloverBasePrincipalAmount ?? 0 }
        set { rolloverBasePrincipalAmount = newValue }
    }

    var resolvedRolloverBaseInterestAmount: Double {
        get { rolloverBaseInterestAmount ?? 0 }
        set { rolloverBaseInterestAmount = newValue }
    }

    init(
        id: UUID = UUID(),
        ownerUID: String? = nil,
        bankName: String,
        principal: Double,
        originalPrincipal: Double? = nil,
        originalCurrency: String? = nil,
        basePrincipal: Double? = nil,
        baseCurrencyCode: String? = nil,
        principalExchangeRateToBase: Double = 1.0,
        annualInterestRate: Double,
        interestSettlementMode: String = DepositInterestSettlementMode.maturity.rawValue,
        expectedInterest: Double,
        baseExpectedInterest: Double? = nil,
        interestExchangeRateToBase: Double = 1.0,
        isInterestManuallyEdited: Bool = false,
        currency: String,
        startDate: Date,
        maturityDate: Date,
        isActive: Bool = true,
        hasCreditedInterest: Bool = false,
        lastInterestPayoutDate: Date? = nil,
        nextInterestPayoutDate: Date? = nil,
        notificationsEnabled: Bool = false,
        reminderDaysBefore: Int = 0,
        reminderHour: Int = 9,
        reminderMinute: Int = 0,
        note: String? = nil,
        maturityInterestHandling: String? = DepositMaturityInterestHandling.payout.rawValue,
        sourceDepositID: UUID? = nil,
        rolloverBasePrincipalAmount: Double? = 0,
        rolloverBaseInterestAmount: Double? = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        lastModifiedDeviceID: String = SyncMetadataDefaults.currentDeviceID,
        syncVersion: Int = 1
    ) {
        let resolvedOriginalPrincipal = originalPrincipal ?? principal
        let resolvedOriginalCurrency = originalCurrency ?? currency
        let resolvedBasePrincipal = basePrincipal ?? principal
        let resolvedBaseCurrencyCode = baseCurrencyCode ?? currency
        let resolvedBaseExpectedInterest = baseExpectedInterest ?? expectedInterest

        self.id = id
        self.ownerUID = ownerUID
        self.bankName = bankName
        self.principal = principal
        self.originalPrincipal = resolvedOriginalPrincipal
        self.originalCurrency = resolvedOriginalCurrency
        self.basePrincipal = resolvedBasePrincipal
        self.baseCurrencyCode = resolvedBaseCurrencyCode
        self.principalExchangeRateToBase = principalExchangeRateToBase
        self.annualInterestRate = annualInterestRate
        self.interestSettlementMode = interestSettlementMode
        self.expectedInterest = expectedInterest
        self.baseExpectedInterest = resolvedBaseExpectedInterest
        self.interestExchangeRateToBase = interestExchangeRateToBase
        self.isInterestManuallyEdited = isInterestManuallyEdited
        self.currency = currency
        self.startDate = startDate
        self.maturityDate = maturityDate
        self.isActive = isActive
        self.hasCreditedInterest = hasCreditedInterest
        self.lastInterestPayoutDate = lastInterestPayoutDate
        self.nextInterestPayoutDate = nextInterestPayoutDate
        self.notificationsEnabled = notificationsEnabled
        self.reminderDaysBefore = reminderDaysBefore
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.note = note
        self.maturityInterestHandling = maturityInterestHandling
        self.sourceDepositID = sourceDepositID
        self.rolloverBasePrincipalAmount = rolloverBasePrincipalAmount
        self.rolloverBaseInterestAmount = rolloverBaseInterestAmount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastModifiedDeviceID = lastModifiedDeviceID
        self.syncVersion = syncVersion
    }
}
