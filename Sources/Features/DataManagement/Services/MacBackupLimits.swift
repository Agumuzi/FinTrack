import Foundation

/// Native v1 JSON remains unchanged. Bound both writers and readers, including
/// the journal's additional base64 envelope and private preferences snapshot.
nonisolated enum MacBackupLimits {
    static let nativeBytes = 256 * 1024 * 1024
    static let preferencesBytes = 16 * 1024 * 1024
    static let journalBytes = ((nativeBytes + preferencesBytes + 2) / 3) * 4 + 64 * 1024

    static func checkNativeSize(_ count: Int) throws {
        guard count <= nativeBytes else {
            throw MacSettingsFailure.invalid("完整备份超过 256 MiB 安全上限，未更改账本。请退出应用后保留整个账本目录的副本，再安排大账本恢复；请勿删除原库。")
        }
    }
}
