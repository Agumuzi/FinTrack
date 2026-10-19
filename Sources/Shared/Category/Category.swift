import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID
    var ownerUID: String?
    var name: String
    var type: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedDeviceID: String
    var syncVersion: Int

    init(
        id: UUID = UUID(),
        ownerUID: String? = nil,
        name: String,
        type: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        lastModifiedDeviceID: String = SyncMetadataDefaults.currentDeviceID,
        syncVersion: Int = 1
    ) {
        self.id = id
        self.ownerUID = ownerUID
        self.name = name
        self.type = type
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastModifiedDeviceID = lastModifiedDeviceID
        self.syncVersion = syncVersion
    }
}
