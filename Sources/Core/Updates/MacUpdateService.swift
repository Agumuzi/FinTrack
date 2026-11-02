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
    nonisolated static let officialManifestURL = "https://agumuzi.github.io/FinTrack/updates/dmg/latest.json"
    nonisolated static let legacyManifestURL = "https://agumuzi.github.io/FinTrack/updates/latest.json"
    private static var activeManifestURL: String {
        #if FINTRACK_LOCAL_VALIDATION
        if MacPreferences.isTesting, ProcessInfo.processInfo.environment["FINTRACK_V142_LEGACY_FEED_TEST"] == "1" { return legacyManifestURL }
        #endif
        return officialManifestURL
    }
    nonisolated static let officialPublicKey = "GV97/PaIi/JO1WKGFTsEuJ+jpHfkyBUkuyd6OIxjMtA="
    @Published private(set) var status = L10n.text("mac.updateService.status.8642a3f756")
    @Published private(set) var busy = false
    @Published private(set) var installing = false
    @Published private(set) var installError: String?
    @Published private(set) var release: MacUpdateRelease?
    @Published private(set) var archive: URL?
    @Published private(set) var checkedAt: Date?
    private var trustedConfiguration: String?
    private var downloadID: UUID?
    private var requestedFromNotification = false
    var handlingNotification: Bool { requestedFromNotification }
    private static var configurationIdentity: String { activeManifestURL + "|" + officialPublicKey }
    struct SignedManifest: Codable { var payload: Data; var signature: Data }
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L10n.text("mac.updateService.version.4d8c1c5b42") }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? L10n.text("mac.updateService.build.4d8c1c5b42") }
    static var configured: Bool { validatedURL(officialManifestURL) != nil && Data(base64Encoded: officialPublicKey)?.count == 32 }
    var actionTitle: String { busy ? L10n.text("mac.updateService.actionTitle.d3d21191f3") : archive != nil ? L10n.text("mac.updateService.actionTitle.96c760c3c7") : release != nil ? L10n.text("mac.updateService.actionTitle.ac69f68b70") : L10n.text("mac.updateService.actionTitle.a6c1e125e9") }
    func performPrimaryAction() {
        if archive != nil { MacUpdatePrompt.shared.show(.ready) }
        else if release != nil { MacUpdatePrompt.shared.download() }
        else { Task { await check() } }
    }
    nonisolated static func validatedURL(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        return url
    }
    static func verify(_ data: Data, publicKey: Data) throws -> MacUpdateRelease {
        guard data.count <= 1024 * 1024 else { throw MacSettingsFailure.invalid(L10n.text("mac.updateService.verify.c6422cd5dd")) }
        let manifest = try JSONDecoder().decode(SignedManifest.self, from: data)
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        guard key.isValidSignature(manifest.signature, for: manifest.payload) else { throw MacSettingsFailure.invalid(L10n.text("mac.updateService.verify.c2de896867")) }
        let release = try JSONDecoder().decode(MacUpdateRelease.self, from: manifest.payload)
        guard release.build > 0, !release.version.isEmpty, validatedURL(release.packageURL) != nil,
              release.sha256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
              release.minimumOS.range(of: #"^\d+\.\d+(\.\d+)?$"#, options: .regularExpression) != nil
        else { throw MacSettingsFailure.invalid(L10n.text("mac.updateService.verify.056268d6e8")) }
        return release
    }
    func reset() { release = nil; archive = nil; checkedAt = nil; trustedConfiguration = nil; status = L10n.text("mac.updateService.reset.c830afac88") }
    func openFromNotification() {
        MacApplicationRuntime.shared.showMain()
        if release != nil && !busy { MacUpdatePrompt.shared.show(archive == nil ? .offer : .ready); return }
        requestedFromNotification = true
        if !busy { Task { await check() } }
    }
    func check(automatic: Bool = false) async {
        guard !busy else { return }
        guard Self.configured, let url = Self.validatedURL(Self.activeManifestURL),
              let key = Data(base64Encoded: Self.officialPublicKey)
        else { status = L10n.text("mac.updateService.check.e4f12a906f"); return }
        let identity = Self.configurationIdentity
        busy = true; defer { busy = false }; release = nil; archive = nil; trustedConfiguration = nil; status = L10n.text("mac.updateService.check.a87bfd662c")
        do {
            let data = try await download(url, limit: 1024 * 1024, allowHTTPSRedirects: false)
            guard identity == Self.configurationIdentity else { throw MacSettingsFailure.invalid(L10n.text("mac.updateService.check.c830afac88")) }
            let item = try Self.verify(data, publicKey: key)
            checkedAt = Date(); MacPreferences.defaults.set(Date(), forKey: "v2_update_last_check")
            guard item.build > (Int(Self.build) ?? 0) else {
                status = L10n.text("mac.updateService.check.af1bb1a3d9")
                if requestedFromNotification { MacPreferences.defaults.set("about",forKey:"v2_settings_page"); MacApplicationRuntime.shared.showMain(settings:true) }
                requestedFromNotification = false; return
            }
            guard ProcessInfo.processInfo.operatingSystemVersionString.count > 0,
                  Self.isCompatible(item.minimumOS) else {
                status = L10n.format("mac.updateService.check.da3046fbca", "\(item.minimumOS)")
                if requestedFromNotification { MacPreferences.defaults.set("about",forKey:"v2_settings_page"); MacApplicationRuntime.shared.showMain(settings:true) }
                requestedFromNotification = false; return
            }
            trustedConfiguration = identity; release = item; status = L10n.format("mac.updateService.check.5f90cf98eb", "\(item.version)", "\(item.build)")
            if automatic && !requestedFromNotification {
                do {
                    if try await MacNotifications.notifyUpdate(item) { status += L10n.text("mac.updateService.check.f36f5c9763") }
                    else { status += L10n.text("mac.updateService.check.1ce820b987") }
                } catch { status += L10n.text("mac.updateService.check.62e37df94b") }
            } else { MacUpdatePrompt.shared.show(.offer) }
            requestedFromNotification = false
        } catch {
            status = L10n.format("mac.updateService.check.cf9c6bdf38", "\(safe(error))")
            if requestedFromNotification { MacPreferences.defaults.set("about",forKey:"v2_settings_page"); MacApplicationRuntime.shared.showMain(settings:true) }
            requestedFromNotification = false
        }
    }
    static func isCompatible(_ minimum: String) -> Bool {
        let parts = minimum.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return false }
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(.init(majorVersion: parts[0], minorVersion: parts[1], patchVersion: parts.count > 2 ? parts[2] : 0))
    }
    func downloadRelease() async {
        guard !busy, let item = release, let url = Self.validatedURL(item.packageURL) else { return }
        busy = true; defer { busy = false }; archive = nil; status = L10n.text("mac.updateService.downloadRelease.b285736309")
        let identity = trustedConfiguration
        let operationID = UUID(); downloadID = operationID
        defer { downloadID = nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FinTrack-Updates/" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let ext = url.pathExtension.lowercased()
            guard ["dmg","zip"].contains(ext) else { throw MacUpdatePackageFailure.format }
            let file = folder.appendingPathComponent("FinTrack-update."+ext)
            let transfer = MacUpdateArchiveDownload(destination: file, limit: 300 * 1024 * 1024) { [weak self] percent in
                Task { @MainActor [weak self] in
                    guard let self, self.busy, self.downloadID == operationID, self.trustedConfiguration == identity,
                          self.release?.sha256 == item.sha256 else { return }
                    self.status = L10n.format("mac.updateService.Task.99fa32f7e9", "\(percent)")
                }
            }
            _ = try await transfer.download(url)
            downloadID = nil
            try Task.checkCancellation()
            guard trustedConfiguration == Self.configurationIdentity, release?.sha256 == item.sha256, release?.build == item.build else { throw MacSettingsFailure.invalid(L10n.text("mac.updateService.downloadRelease.2e9d8f80fa")) }
            status = L10n.text("mac.updateService.downloadRelease.d0b2c6fecb")
            try await MacUpdateArchiveDownload.verify(file, sha256: item.sha256)
            guard trustedConfiguration == Self.configurationIdentity, release?.sha256 == item.sha256, release?.build == item.build else { throw MacSettingsFailure.invalid(L10n.text("mac.updateService.downloadRelease.2e9d8f80fa")) }
            archive = file; status = L10n.text("mac.updateService.downloadRelease.d2251b0437")
            MacUpdatePrompt.shared.show(.ready)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            if error is CancellationError || (error as? URLError)?.code == .cancelled { status = L10n.text("mac.updateService.downloadRelease.333cf0cd32") }
            else { status = L10n.format("mac.updateService.downloadRelease.e70b26e60e", "\(safe(error))") }
        }
    }
    private static var installationAllowed: Bool {
        if !MacPreferences.isTesting { return true }
        #if FINTRACK_LOCAL_VALIDATION
        return ProcessInfo.processInfo.environment["FINTRACK_TEST_REAL_INSTALL"] == "1" && Bundle.main.bundleURL.path.hasPrefix("/private/tmp/FinTrack-V13-v144-")
        #else
        return false
        #endif
    }
    #if FINTRACK_LOCAL_VALIDATION
    func loadInstallationFixture() {
        struct Fixture: Decodable { let archive: String; let release: MacUpdateRelease }
        guard Self.installationAllowed, let path = ProcessInfo.processInfo.environment["FINTRACK_TEST_UPDATE_FIXTURE"],
              path.hasPrefix("/private/tmp/FinTrack-V13-v144-"), let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let fixture = try? JSONDecoder().decode(Fixture.self, from: data), fixture.release.build > (Int(Self.build) ?? 0),
              fixture.archive.hasPrefix(FileManager.default.temporaryDirectory.appendingPathComponent("FinTrack-Updates/").path) else { return }
        release = fixture.release; archive = URL(fileURLWithPath: fixture.archive)
        trustedConfiguration = Self.configurationIdentity; status = L10n.text("mac.updateService.loadInstallationFixture.acec4df000")
        MacUpdatePrompt.shared.show(.ready)
    }
    #endif
    /// Prepare and validate the complete replacement before terminating the running app.
    func installAndRelaunch() async throws {
        guard Self.installationAllowed, trustedConfiguration == Self.configurationIdentity, let archive, let release,
              Bundle.main.bundleURL.pathExtension == "app" else { throw MacSettingsFailure.invalid(L10n.text("mac.updateService.installAndRelaunch.2f5dc5e5e6")) }
        let fm = FileManager.default, root = archive.deletingLastPathComponent()
        guard !busy, let bundleIdentifier=Bundle.main.bundleIdentifier else { throw MacSettingsFailure.invalid(L10n.text("mac.updateService.installAndRelaunch.146559e9d8")) }
        busy = true; installing = true; installError = nil; status = L10n.text("mac.updateService.installAndRelaunch.b9ee7798c4")
        do {
            let candidate = try await Task.detached(priority: .userInitiated) { try MacUpdatePackage.prepare(archive, release: release, bundleIdentifier: bundleIdentifier) }.value
            guard trustedConfiguration == Self.configurationIdentity, self.release?.sha256 == release.sha256 else { throw MacSettingsFailure.invalid(L10n.text("mac.updateService.installAndRelaunch.10486567eb")) }
            let current = Bundle.main.bundleURL
            guard fm.isWritableFile(atPath: current.deletingLastPathComponent().path) else { throw MacSettingsFailure.invalid(L10n.text("mac.updateService.installAndRelaunch.d3b7825044")) }
            let handoff = try MacUpdateInstallation.writeHelper(root: root, target: current, release: release)
            status = L10n.text("mac.updateService.installAndRelaunch.fb8216cd6d")
            // Termination while an attached SwiftUI sheet is active can be deferred.
            // End that sheet first, and retain the install lock until process exit.
            let sheet = MacApplicationRuntime.shared.mainWindow?.attachedSheet
            MacUpdatePrompt.shared.dismiss()
            for _ in 0..<60 {
                if sheet?.sheetParent == nil { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard sheet?.sheetParent == nil else { throw MacSettingsFailure.invalid(L10n.text("mac.updateService.installAndRelaunch.c59276903d")) }
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [handoff.helper.path, String(ProcessInfo.processInfo.processIdentifier), candidate.path, current.path, root.path, handoff.ticket.path, handoff.token]
            #if FINTRACK_LOCAL_VALIDATION
            if Self.installationAllowed { process.arguments?.append(ProcessInfo.processInfo.environment["FINTRACK_V13_TEST_STORE_PATH"] ?? "") }
            #endif
            let log = root.appendingPathComponent("installation.log"); fm.createFile(atPath: log.path, contents: nil)
            process.standardOutput = try FileHandle(forWritingTo: log); process.standardError = process.standardOutput
            try process.run()
            // Do not quit until the independent helper owns the target lock and
            // has verified its replacement on the destination filesystem.
            let stateFile = root.appendingPathComponent("installation-state")
            var helperReady = false
            for _ in 0..<600 {
                if (try? String(contentsOf: stateFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) == "waiting_for_exit" { helperReady = true; break }
                if !process.isRunning { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard helperReady else {
                if process.isRunning { process.terminate() }
                throw MacSettingsFailure.invalid(L10n.text("mac.updateService.installAndRelaunch.561e561dc2"))
            }
            NSApp.terminate(nil)
        } catch {
            installing = false; busy = false; installError = error.localizedDescription; status = L10n.text("mac.updateService.installAndRelaunch.b131240cd2") + error.localizedDescription
            MacUpdatePrompt.shared.show(.ready)
            throw error
        }
    }

    func runAutomaticChecks() async {
        guard !MacPreferences.isTesting else { return }
        while !Task.isCancelled {
            let d = MacPreferences.defaults
            if d.bool(forKey: "v2_update_auto"), Self.configured {
                let interval: TimeInterval = d.string(forKey: "v2_update_frequency") == "daily" ? 86400 : d.string(forKey: "v2_update_frequency") == "monthly" ? 30 * 86400 : 7 * 86400
                let last = d.object(forKey: "v2_update_last_check") as? Date ?? .distantPast
                if Date().timeIntervalSince(last) >= interval {
                    await check(automatic:true)
                }
            }
            do { try await Task.sleep(for: .seconds(3600)) } catch { return }
        }
    }
    private func download(_ url: URL, limit: Int, allowHTTPSRedirects: Bool) async throws -> Data {
        // GitHub Release assets redirect to its asset CDN. The signed manifest
        // pins the final ZIP digest; redirects may only remain on HTTPS.
        let delegate: URLSessionTaskDelegate = allowHTTPSRedirects ? MacUpdateHTTPSRedirect() : MacNoRedirect()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.timeoutInterval = 45
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), response.expectedContentLength <= limit else { throw MacSettingsFailure.invalid(L10n.text("mac.updateService.download.a106418a7f")) }
        var data = Data()
        for try await byte in bytes { data.append(byte); guard data.count <= limit else { throw MacSettingsFailure.invalid(L10n.text("mac.updateService.download.8d0f1d2830")) } }
        return data
    }
    private func run(_ path: String, _ arguments: [String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = arguments
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw MacSettingsFailure.invalid(L10n.text("mac.updateService.run.4965bdaa5c")) }
        return String(data: data, encoding: .utf8) ?? ""
    }
    private func safe(_ error: Error) -> String {
        if let failure = error as? MacSettingsFailure { return failure.errorDescription ?? L10n.text("mac.updateService.safe.ca1c32eb06") }
        if let failure = error as? MacUpdateTransferError { return failure.localizedDescription }
        if let failure = error as? URLError {
            if failure.code == .timedOut { return L10n.text("mac.updateService.safe.11b83028c7") }
            if failure.code == .notConnectedToInternet { return L10n.text("mac.updateService.safe.e6a2d5caee") }
            if failure.code == .cancelled { return L10n.text("mac.updateService.safe.333cf0cd32") }
            return L10n.text("mac.updateService.safe.217716855a")
        }
        return L10n.text("mac.updateService.safe.c7430bc918")
    }
}

final class MacUpdateHTTPSRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, MacUpdateService.validatedURL(url.absoluteString) != nil else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }
}
