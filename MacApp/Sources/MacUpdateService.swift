import Foundation
import AppKit
import CryptoKit

struct MacUpdateRelease: Codable, Sendable {
    var version: String
    var build: Int
    var minimumOS: String
    var notes: String
    var packageURL: String
    var sha256: String
}

@MainActor
final class MacUpdateService: ObservableObject {
    static let shared = MacUpdateService()
    @Published private(set) var status = "尚未检查更新"
    @Published private(set) var busy = false
    @Published private(set) var release: MacUpdateRelease?
    @Published private(set) var archive: URL?
    @Published private(set) var checkedAt: Date?
    private var trustedConfiguration: String?
    private static var configurationIdentity: String { (MacPreferences.defaults.string(forKey: "v2_update_url") ?? "") + "|" + (MacPreferences.defaults.string(forKey: "v2_update_public_key") ?? "") }
    struct SignedManifest: Codable { var payload: Data; var signature: Data }
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知" }
    static var configured: Bool {
        let d = MacPreferences.defaults
        return validatedURL(d.string(forKey: "v2_update_url") ?? "") != nil && Data(base64Encoded: d.string(forKey: "v2_update_public_key") ?? "")?.count == 32
    }
    static func validatedURL(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        return url
    }
    static func verify(_ data: Data, publicKey: Data) throws -> MacUpdateRelease {
        guard data.count <= 1024 * 1024 else { throw MacSettingsFailure.invalid("更新清单过大") }
        let manifest = try JSONDecoder().decode(SignedManifest.self, from: data)
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        guard key.isValidSignature(manifest.signature, for: manifest.payload) else { throw MacSettingsFailure.invalid("更新清单签名无效") }
        let release = try JSONDecoder().decode(MacUpdateRelease.self, from: manifest.payload)
        guard release.build > 0, !release.version.isEmpty, validatedURL(release.packageURL) != nil,
              release.sha256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
              release.minimumOS.range(of: #"^\d+\.\d+(\.\d+)?$"#, options: .regularExpression) != nil
        else { throw MacSettingsFailure.invalid("更新清单内容无效") }
        return release
    }
    func reset() { release = nil; archive = nil; checkedAt = nil; trustedConfiguration = nil; status = "更新源已更改，请重新检查" }
    func check() async {
        guard !busy else { return }
        guard Self.configured, let url = Self.validatedURL(MacPreferences.defaults.string(forKey: "v2_update_url") ?? ""),
              let key = Data(base64Encoded: MacPreferences.defaults.string(forKey: "v2_update_public_key") ?? "")
        else { status = "尚未配置签名发布源，当前使用本地安装包更新"; return }
        let identity = Self.configurationIdentity
        busy = true; defer { busy = false }; release = nil; archive = nil; trustedConfiguration = nil; status = "正在检查签名更新…"
        do {
            let data = try await download(url, limit: 1024 * 1024)
            guard identity == Self.configurationIdentity else { throw MacSettingsFailure.invalid("更新源已更改，请重新检查") }
            let item = try Self.verify(data, publicKey: key)
            checkedAt = Date(); MacPreferences.defaults.set(Date(), forKey: "v2_update_last_check")
            guard item.build > (Int(Self.build) ?? 0) else { status = "当前已是此发布源的最新版本"; return }
            guard ProcessInfo.processInfo.operatingSystemVersionString.count > 0,
                  Self.isCompatible(item.minimumOS) else { status = "新版本需要 macOS \(item.minimumOS) 或更高版本"; return }
            trustedConfiguration = identity; release = item; status = "发现新版本 \(item.version)（\(item.build)）"
        } catch { status = "检查失败：\(safe(error))" }
    }
    static func isCompatible(_ minimum: String) -> Bool {
        let parts = minimum.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return false }
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(.init(majorVersion: parts[0], minorVersion: parts[1], patchVersion: parts.count > 2 ? parts[2] : 0))
    }
    func downloadRelease() async {
        guard !busy, let item = release, let url = Self.validatedURL(item.packageURL) else { return }
        busy = true; defer { busy = false }; status = "正在下载并校验更新…"
        do {
            let data = try await download(url, limit: 300 * 1024 * 1024)
            guard trustedConfiguration == Self.configurationIdentity, release?.sha256 == item.sha256, release?.build == item.build else { throw MacSettingsFailure.invalid("更新源或版本已更改，请重新检查") }
            guard MacNativeBackup.digest(data) == item.sha256 else { throw MacSettingsFailure.invalid("安装包校验不一致，已拒绝安装") }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FinTrack-Updates/" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("FinTrack-update.zip"); try data.write(to: file, options: .atomic)
            archive = file; status = "更新已下载并通过签名清单与 SHA256 校验，等待安装确认"
        } catch { status = "下载失败：\(safe(error))" }
    }
    /// Prepare and validate the complete replacement before terminating the running app.
    func installAndRelaunch() throws {
        guard !MacPreferences.isTesting, trustedConfiguration == Self.configurationIdentity, let archive, let release,
              Bundle.main.bundleURL.pathExtension == "app" else { throw MacSettingsFailure.invalid("没有可安装的已验证更新") }
        let fm = FileManager.default, root = archive.deletingLastPathComponent()
        guard MacNativeBackup.digest(try Data(contentsOf: archive)) == release.sha256 else { throw MacSettingsFailure.invalid("安装包内容已发生变化") }
        let listing = try run("/usr/bin/unzip", ["-Z1", archive.path])
        let entries = listing.split(separator: "\n").map(String.init)
        guard !entries.isEmpty, entries.count <= 5000, entries.allSatisfy({ !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") && ($0.hasPrefix("FinTrack.app/") || $0.hasPrefix("__MACOSX/")) }) else { throw MacSettingsFailure.invalid("安装包结构不符合要求") }
        let extracted = root.appendingPathComponent("extracted")
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        _ = try run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
        let candidate = extracted.appendingPathComponent("FinTrack.app")
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", candidate.path])
        guard let info = NSDictionary(contentsOf: candidate.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              String(describing: info["CFBundleVersion"] ?? "") == String(release.build),
              info["CFBundleShortVersionString"] as? String == release.version
        else { throw MacSettingsFailure.invalid("更新包身份或版本不匹配") }
        let current = Bundle.main.bundleURL
        guard fm.isWritableFile(atPath: current.deletingLastPathComponent().path) else { throw MacSettingsFailure.invalid("应用目录不可写，请将应用放在用户可写目录后再安装") }
        let helper = root.appendingPathComponent("install.sh")
        // Paths are passed as separate argv values, never interpolated into shell source.
        let script = """
        #!/bin/sh
        set -eu
        old_pid="$1"
        candidate="$2"
        target="$3"
        previous="$4"
        count=0
        while kill -0 "$old_pid" 2>/dev/null; do
          count=$((count + 1))
          [ "$count" -lt 60 ] || exit 1
          sleep 1
        done
        mv "$target" "$previous"
        if /usr/bin/ditto "$candidate" "$target" && /usr/bin/codesign --verify --deep --strict "$target"; then
          /usr/bin/open -n "$target"
        else
          rm -rf "$target"
          mv "$previous" "$target"
          /usr/bin/open -n "$target"
          exit 1
        fi
        """
        try Data(script.utf8).write(to: helper, options: .atomic)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [helper.path, String(ProcessInfo.processInfo.processIdentifier), candidate.path, current.path, root.appendingPathComponent("FinTrack-previous.app").path]
        let log = root.appendingPathComponent("installation.log"); fm.createFile(atPath: log.path, contents: nil)
        process.standardOutput = try FileHandle(forWritingTo: log); process.standardError = process.standardOutput
        try process.run(); NSApp.terminate(nil)
    }
    func runAutomaticChecks() async {
        guard !MacPreferences.isTesting else { return }
        while !Task.isCancelled {
            let d = MacPreferences.defaults
            if d.bool(forKey: "v2_update_auto"), Self.configured {
                let interval: TimeInterval = d.string(forKey: "v2_update_frequency") == "daily" ? 86400 : d.string(forKey: "v2_update_frequency") == "monthly" ? 30 * 86400 : 7 * 86400
                let last = d.object(forKey: "v2_update_last_check") as? Date ?? .distantPast
                if Date().timeIntervalSince(last) >= interval {
                    await check()
                    if release != nil, d.bool(forKey: "v2_update_download") { await downloadRelease() }
                }
            }
            try? await Task.sleep(for: .seconds(3600))
        }
    }
    private func download(_ url: URL, limit: Int) async throws -> Data {
        let session = URLSession(configuration: .ephemeral, delegate: MacNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.timeoutInterval = 45
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), response.expectedContentLength <= limit else { throw MacSettingsFailure.invalid("更新服务器响应无效") }
        var data = Data()
        for try await byte in bytes { data.append(byte); guard data.count <= limit else { throw MacSettingsFailure.invalid("更新文件超过大小限制") } }
        return data
    }
    private func run(_ path: String, _ arguments: [String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = arguments
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw MacSettingsFailure.invalid("安装包验证失败，现有应用未修改") }
        return String(data: data, encoding: .utf8) ?? ""
    }
    private func safe(_ error: Error) -> String { (error as? MacSettingsFailure)?.errorDescription ?? "网络或签名验证未通过" }
}
