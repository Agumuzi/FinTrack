import Foundation
import SwiftData
import CryptoKit
import Darwin

/// A durable undo record spans SwiftData, preferences, and bank images. A
/// surviving record is rolled back before the ledger is exposed on next open.
@MainActor
enum MacRecoveryJournal {
    private static var recovering = false
    private static var depth = 0
    static var isRecovering: Bool { recovering }
    private struct Record: Codable {
        let version: Int
        let store: String
        let snapshot: Data
        let preferences: Data
        let sha256: String
    }
    private struct Ticket {
        let file: URL?
        let snapshot: Data
        let preferences: Data
        let database: String
    }
    private static var preferenceKeys: [String] {
        MacSettingsStore.keys + ["app_language", "v2_update_url", "v2_update_public_key", "v2_backup_history", "v147_loan_calendars"]
    }
    private static func preferences() throws -> Data {
        var values: [String: Any] = [:]
        for key in preferenceKeys { if let value = MacPreferences.defaults.object(forKey: key) { values[key] = value } }
        return try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
    }
    private static func restorePreferences(_ data: Data) throws {
        guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              Set(values.keys).isSubset(of: Set(preferenceKeys)) else { throw MacSettingsFailure.invalid("恢复设置记录无效") }
        for key in preferenceKeys { MacPreferences.defaults.removeObject(forKey: key) }
        for (key, value) in values { MacPreferences.defaults.set(value, forKey: key) }
    }
    static func location(in context: ModelContext) -> URL? {
        guard let config = context.container.configurations.first(where: { !$0.isStoredInMemoryOnly }) else { return nil }
        return config.url.appendingPathExtension("recovery.json")
    }
    private static func database(_ payload: MacNativeBackup.Payload) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        func rows<T: Encodable>(_ values: [T]) throws -> [String] {
            try values.map { String(decoding: try encoder.encode($0), as: UTF8.self) }.sorted()
        }
        let values = try [rows(payload.account), rows(payload.transaction), rows(payload.category), rows(payload.goal),
                          rows(payload.financialProfile), rows(payload.recurringTransaction), rows(payload.depositRecord), rows(payload.loanRule)]
        return MacNativeBackup.digest(try encoder.encode(values))
    }
    private static func synchronize(_ file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.synchronize()
        let directory = Darwin.open(file.deletingLastPathComponent().path, O_RDONLY)
        guard directory >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(directory) }
        guard fsync(directory) == 0 else { throw POSIXError(.EIO) }
    }
    static func assertWritable(in context: ModelContext, allowSnapshotRead:Bool = false) throws {
        if !allowSnapshotRead,MacDataOperationState.shared.status != nil,!MacDataOperationState.shared.committing {
            throw MacSettingsFailure.invalid("数据文件正在处理中，请完成后再保存账目。当前输入尚未保存。")
        }
        if depth == 0 && !recovering,let file=location(in:context),FileManager.default.fileExists(atPath:file.path) {
            throw MacSettingsFailure.invalid("上次操作尚未完成恢复，暂不能写入账本。请退出并重新打开应用。")
        }
    }
    private static func begin(in context: ModelContext) throws -> Ticket {
        try assertWritable(in:context)
        guard !MacAutomaticPosting.isRunning else { throw MacSettingsFailure.invalid("自动入账正在处理中，请稍后再操作。") }
        guard !context.hasChanges else { throw MacSettingsFailure.invalid("请先保存或取消当前编辑，再执行此操作。") }
        let file = location(in: context)
        if let file, FileManager.default.fileExists(atPath: file.path) {
            throw MacSettingsFailure.invalid("上次操作尚未完成恢复，请退出并重新打开应用后再操作。")
        }
        let snapshot = try MacNativeBackup.create(in: context)
        let payload = try MacNativeBackup.preview(snapshot, validateFinancial: false), settings = try preferences()
        if let file {
            let record = Record(version: 1, store: file.deletingPathExtension().standardizedFileURL.path,
                                snapshot: snapshot, preferences: settings, sha256: MacNativeBackup.digest(snapshot + settings))
            try JSONEncoder().encode(record).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            try synchronize(file)
        }
        return Ticket(file: file, snapshot: snapshot, preferences: settings, database: try database(payload))
    }
    private static func finish(_ ticket: Ticket) throws {
        guard MacPreferences.defaults.synchronize() else {
            throw MacSettingsFailure.invalid("设置尚未安全保存，操作已取消。")
        }
        if let file = ticket.file { try FileManager.default.removeItem(at: file) }
    }
    private static func rollback(_ ticket: Ticket, in context: ModelContext, alwaysRestore: Bool) throws {
        context.rollback()
        var needsRestore = alwaysRestore
        if !alwaysRestore {
            let fresh = ModelContext(context.container)
            let current = try MacNativeBackup.preview(MacNativeBackup.create(in: fresh), validateFinancial: false)
            let old = try MacNativeBackup.preview(ticket.snapshot, validateFinancial: false)
            needsRestore = (try database(current)) != ticket.database || current.bankLogos != old.bankLogos
        }
        if needsRestore {
            recovering = true; defer { recovering = false }
            try MacNativeBackup.restore(ticket.snapshot, in: context)
        }
        try restorePreferences(ticket.preferences)
        if alwaysRestore {
            MacPreferences.defaults.set(false, forKey: "fintrack_auto_posting")
            MacPreferences.defaults.set(false, forKey: "v13_auto_deposit_posting")
        }
        try finish(ticket)
    }
    static func perform(in context: ModelContext, _ body: () throws -> Void) throws {
        if recovering || depth > 0 { try body(); return }
        let ticket = try begin(in: context)
        depth += 1; defer { depth -= 1 }
        do {
            checkpoint("prepared")
            try body()
            checkpoint("applied")
            try finish(ticket)
        }
        catch {
            let original = error
            do { try rollback(ticket, in: context, alwaysRestore: false) }
            catch { MacLedgerAccess.shared.quarantineRecovery();throw MacSettingsFailure.invalid("操作未完成，恢复记录已保留。请退出后重新打开应用恢复账本。") }
            throw original
        }
    }
    static func checkpoint(_ phase: String) {
        #if FINTRACK_LOCAL_VALIDATION
        let env = ProcessInfo.processInfo.environment
        if MacPreferences.isTesting, env["FINTRACK_V147_RECOVERY_PROBE"] == "crash", env["FINTRACK_V147_CRASH_PHASE"] == phase {
            Darwin.kill(getpid(), SIGKILL)
        }
        #endif
    }
    @discardableResult static func recoverIfNeeded(in context: ModelContext) throws -> Bool {
        guard let file = location(in: context), FileManager.default.fileExists(atPath: file.path) else { return false }
        let data = try MacDataIO.read(file,limit:200*1024*1024)
        let record = try JSONDecoder().decode(Record.self, from: data)
        guard record.version == 1, record.store == file.deletingPathExtension().standardizedFileURL.path,
              record.sha256 == MacNativeBackup.digest(record.snapshot + record.preferences) else {
            throw MacSettingsFailure.invalid("操作恢复记录校验未通过。原账本与恢复记录均已保留，请先安排安全恢复。")
        }
        let payload = try MacNativeBackup.preview(record.snapshot, validateFinancial: false)
        try rollback(Ticket(file: file, snapshot: record.snapshot, preferences: record.preferences, database: try database(payload)), in: context, alwaysRestore: true)
        NotificationCenter.default.post(name: MacSettingsStore.restoreCompleted, object: nil)
        return true
    }
}
