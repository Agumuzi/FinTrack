import Foundation

enum SyncMetadataDefaults {
    private static let deviceIDKey = "sync_metadata_device_id"

    static var currentDeviceID: String {
        #if os(macOS)
        let defaults = MacPreferences.defaults
        #else
        let defaults = UserDefaults.standard
        #endif
        if let existing = defaults.string(forKey: deviceIDKey), existing.isEmpty == false {
            return existing
        }

        let newValue = UUID().uuidString
        defaults.set(newValue, forKey: deviceIDKey)
        return newValue
    }
}
