import Foundation
import Darwin

enum MacTestStore {
    /// Build outputs and explicitly named validation copies never fall back to
    /// the personal ledger when a launcher drops their environment parameters.
    static func requiresExplicitIsolation(bundleURL:URL)->Bool {
        let path=bundleURL.standardizedFileURL
        return path.pathComponents.contains(".build") || path.deletingLastPathComponent().lastPathComponent.hasPrefix("FinTrack-V13-")
    }

    static func isIsolated(_ path: String) -> Bool {
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard candidate.pathExtension == "sqlite",
              candidate.deletingLastPathComponent().lastPathComponent.hasPrefix("FinTrack-V13-") else { return false }
        // XCTest may give its runner and target different TMPDIR subdirectories.
        // The OS user temporary root is stable across both processes.
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        guard length > 1 else { return false }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, length) > 0 else { return false }
        let root = URL(fileURLWithPath: String(cString: buffer), isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let runnerTemporary = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/dev.agumuzi.fintrack.macos.uitests.xctrunner/Data/tmp", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        return [root, runnerTemporary].contains { allowed in
            candidate.path.hasPrefix(allowed.path.hasSuffix("/") ? allowed.path : allowed.path + "/")
        }
    }
}
