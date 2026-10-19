import Foundation

enum SyncMetadataDefaults {
    private static let deviceIDKey = "sync_metadata_device_id"

    static var currentDeviceID: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: deviceIDKey), existing.isEmpty == false {
            return existing
        }

        let newValue = UUID().uuidString
        defaults.set(newValue, forKey: deviceIDKey)
        return newValue
    }
}
