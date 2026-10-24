import Foundation

/// One local file has one current history entry. Restored metadata without a
/// local path remains distinct and never authorizes deleting a local file.
enum MacBackupHistory {
    static func fileIdentity(_ path: String) -> String? {
        guard !path.isEmpty, path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func normalized(_ rows: [MacBackupRecord]) -> [MacBackupRecord] {
        var paths = Set<String>(), ids = Set<UUID>()
        return rows.sorted { $0.date > $1.date }.filter { row in
            guard ids.insert(row.id).inserted else { return false }
            return fileIdentity(row.path).map { paths.insert($0).inserted } ?? true
        }
    }

    static func recording(_ data: Data, at url: URL, history: [MacBackupRecord], now: Date = Date()) -> [MacBackupRecord] {
        let identity = fileIdentity(url.path)
        let previous = normalized(history).first { fileIdentity($0.path) == identity }
        let record = MacBackupRecord(id: previous?.id ?? UUID(), name: url.lastPathComponent,
                                     path: url.standardizedFileURL.path, date: now, size: data.count,
                                     sha256: MacNativeBackup.digest(data))
        return Array(normalized([record] + history.filter { fileIdentity($0.path) != identity }).prefix(100))
    }

    struct PartialRemoval: LocalizedError {
        let history: [MacBackupRecord]
        let underlying: Error
        var errorDescription: String? { "部分备份未能移除，历史已保留未删除的项目：" + underlying.localizedDescription }
    }

    static func removing(_ selected: Set<UUID>, from history: [MacBackupRecord],
                         dispose: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws -> [MacBackupRecord] {
        let remaining = history.filter { !selected.contains($0.id) }
        let retainedPaths = Set(remaining.compactMap { fileIdentity($0.path) })
        var handled = Set<String>()
        // Validate every candidate before touching any file. An overwritten or
        // externally replaced file is never deleted using a stale history row.
        var files: [URL] = []
        for row in normalized(history.filter { selected.contains($0.id) }) {
            guard let path = fileIdentity(row.path), !retainedPaths.contains(path), handled.insert(path).inserted else { continue }
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let url = URL(fileURLWithPath: path)
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard let size, size <= 100 * 1024 * 1024 else { throw MacSettingsFailure.invalid("备份文件已变化，本次未删除。请重新核对文件。") }
            let data = try Data(contentsOf: url)
            guard data.count == row.size, MacNativeBackup.digest(data) == row.sha256 else {
                throw MacSettingsFailure.invalid("备份文件已被覆盖或替换，本次未删除。请重新核对文件。")
            }
            files.append(url)
        }
        var disposed = Set<String>()
        for url in files {
            do { try dispose(url); disposed.insert(url.path) }
            catch {
                let retained = history.filter { row in
                    guard let identity = fileIdentity(row.path) else { return true }
                    return !disposed.contains(identity)
                }
                throw PartialRemoval(history: normalized(retained), underlying: error)
            }
        }
        return normalized(remaining)
    }
}
