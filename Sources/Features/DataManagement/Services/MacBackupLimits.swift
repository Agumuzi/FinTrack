import Foundation

/// Native v1 JSON remains unchanged. Bound both writers and readers, including
/// the journal's additional base64 envelope and private preferences snapshot.
nonisolated enum MacBackupLimits {
    static let nativeBytes = 256 * 1024 * 1024
    static let preferencesBytes = 16 * 1024 * 1024
    static let journalBytes = ((nativeBytes + preferencesBytes + 2) / 3) * 4 + 64 * 1024

    static func checkNativeSize(_ count: Int) throws {
        guard count <= nativeBytes else {
            throw MacSettingsFailure.invalid(L10n.text("mac.backupLimits.checkNativeSize.84c9780b21"))
        }
    }
}
