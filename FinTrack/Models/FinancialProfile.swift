import Foundation
import SwiftData

@Model
final class FinancialProfile {
    var id: UUID
    var ownerUID: String?
    var initialAssets: Double
    var initialDebt: Double
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedDeviceID: String
    var syncVersion: Int

    init(
        id: UUID = UUID(),
        ownerUID: String? = nil,
        initialAssets: Double = 0,
        initialDebt: Double = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        lastModifiedDeviceID: String = SyncMetadataDefaults.currentDeviceID,
        syncVersion: Int = 1
    ) {
        self.id = id
        self.ownerUID = ownerUID
        self.initialAssets = initialAssets
        self.initialDebt = initialDebt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastModifiedDeviceID = lastModifiedDeviceID
        self.syncVersion = syncVersion
    }
}
