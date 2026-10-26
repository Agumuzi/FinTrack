import Foundation

/// One installer owns one download directory. A launch receipt keeps the rollback
/// copy until the replacement has actually finished starting.
nonisolated enum MacUpdateInstallation {
    struct Ticket: Codable {
        let token: String
        let target: String
        let version: String
        let build: Int
    }
    static func writeHelper(root: URL, target: URL, release: MacUpdateRelease) throws -> (helper: URL, ticket: URL, token: String) {
        let token = UUID().uuidString, helper = root.appendingPathComponent("install.sh"), ticket = root.appendingPathComponent("launch.json")
        guard !FileManager.default.fileExists(atPath: root.appendingPathComponent("install.lock").path),
              !FileManager.default.fileExists(atPath: root.appendingPathComponent("FinTrack-previous.app").path) else {
            throw MacSettingsFailure.invalid("此安装任务已经启动，请勿重复安装。")
        }
        try JSONEncoder().encode(Ticket(token: token, target: target.standardizedFileURL.path, version: release.version, build: release.build)).write(to: ticket, options: .atomic)
        try Data(script.utf8).write(to: helper, options: .atomic)
        return (helper, ticket, token)
    }
    static let script = #"""
    #!/bin/sh
    set -eu
    old_pid="$1"
    candidate="$2"
    target="$3"
    root="$4"
    ticket="$5"
    token="$6"
    test_store="${7:-}"
    previous="$root/FinTrack-previous.app"
    replacement="${target%.app}.update-$token.app"
    status() { printf '%s\n' "$1" > "$root/installation-state"; printf '%s\n' "$1"; }
    mkdir "$root/install.lock" 2>/dev/null || exit 73
    [ ! -e "$previous" ] && [ ! -L "$previous" ] || exit 74
    [ ! -e "$replacement" ] && [ ! -L "$replacement" ] || exit 75
    target_lock="${target%.app}.update-lock"
    mkdir "$target_lock" 2>/dev/null || { status another_installer_is_running; exit 80; }
    trap 'rm -rf "$replacement"; rmdir "$target_lock" 2>/dev/null || true' EXIT
    launch_new() {
      if [ -n "$test_store" ]; then
        case "$target" in /private/tmp/FinTrack-V13-v144-*|/tmp/FinTrack-V13-v144-*) ;; *) return 81 ;; esac
        /usr/bin/open -n "$target" --env "FINTRACK_V13_TEST_STORE_PATH=$test_store" --env FINTRACK_FX_MOCK=1 --args --fintrack-update-ticket "$ticket" --fintrack-update-token "$token"
      else
        /usr/bin/open -n "$target" --args --fintrack-update-ticket "$ticket" --fintrack-update-token "$token"
      fi
    }
    status preparing
    /usr/bin/ditto "$candidate" "$replacement"
    /usr/bin/codesign --verify --deep --strict "$replacement"
    status waiting_for_exit
    count=0
    while kill -0 "$old_pid" 2>/dev/null; do
      count=$((count + 1))
      if [ "$count" -ge 60 ]; then
        rm -rf "$replacement"
        status exit_timeout
        exit 76
      fi
      sleep 1
    done
    status replacing
    mv "$target" "$previous"
    if mv "$replacement" "$target" && /usr/bin/codesign --verify --deep --strict "$target"; then
      status starting
      if launch_new; then
        count=0
        while [ ! -f "$root/launch-confirmed" ]; do
          count=$((count + 1))
          if [ "$count" -ge 60 ]; then status launch_unconfirmed; exit 77; fi
          sleep 1
        done
        [ "$(cat "$root/launch-confirmed")" = "$token" ] || exit 78
        rm -rf "$previous" "${candidate%/FinTrack.app}"
        rm -f "$root/FinTrack-update.dmg" "$root/FinTrack-update.zip"
        status success
        exit 0
      fi
    fi
    status restoring
    rm -rf "$target"
    mv "$previous" "$target"
    /usr/bin/open -n "$target"
    status rolled_back
    exit 79
    """#

    /// Only a matching private installer ticket may override normal launch visibility.
    static func launchReceipt(bundle: Bundle = .main, arguments: [String] = CommandLine.arguments) -> (file: URL, token: String)? {
        let updates = FileManager.default.temporaryDirectory.appendingPathComponent("FinTrack-Updates", isDirectory: true).standardizedFileURL
        let current = bundle.bundleURL.standardizedFileURL
        guard !current.path.hasPrefix(updates.path + "/"), bundle.bundleIdentifier == "dev.agumuzi.fintrack.macos",
              let index = arguments.firstIndex(of: "--fintrack-update-ticket"), arguments.indices.contains(index + 1),
              let tokenIndex = arguments.firstIndex(of: "--fintrack-update-token"), arguments.indices.contains(tokenIndex + 1) else { return nil }
        let file = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
        guard file.lastPathComponent == "launch.json", file.deletingLastPathComponent().deletingLastPathComponent() == updates,
              (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
              let data = try? Data(contentsOf: file), let ticket = try? JSONDecoder().decode(Ticket.self, from: data),
              ticket.token == arguments[tokenIndex + 1], UUID(uuidString: ticket.token) != nil,
              ticket.target == current.path, ticket.version == bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              String(ticket.build) == bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String else { return nil }
        return (file,ticket.token)
    }
    static func confirmLaunch(bundle: Bundle = .main, arguments: [String] = CommandLine.arguments) {
        let fm = FileManager.default
        let updates = fm.temporaryDirectory.appendingPathComponent("FinTrack-Updates", isDirectory: true).standardizedFileURL
        let current = bundle.bundleURL.standardizedFileURL
        guard !current.path.hasPrefix(updates.path + "/"), bundle.bundleIdentifier == "dev.agumuzi.fintrack.macos" else { return }
        if let receipt = launchReceipt(bundle: bundle, arguments: arguments) {
            try? Data(receipt.token.utf8).write(to: receipt.file.deletingLastPathComponent().appendingPathComponent("launch-confirmed"), options: .atomic)
        }
        // Older updaters cannot send a receipt. Only clean their private staging
        // copies after the installed executable exactly matches a prepared one.
        guard let executable = bundle.executableURL, let hash = try? MacUpdatePackage.digest(executable),
              let folders = try? fm.contentsOfDirectory(at: updates, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return }
        for folder in folders.prefix(100) {
            guard (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
                  !fm.fileExists(atPath: folder.appendingPathComponent("launch.json").path),
                  fm.fileExists(atPath: folder.appendingPathComponent("install.sh").path),
                  let contents = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { continue }
            let prepared = contents.filter { $0.lastPathComponent.hasPrefix("prepared-") && (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false }
            guard prepared.contains(where: { (try? MacUpdatePackage.digest($0.appendingPathComponent("FinTrack.app/Contents/MacOS/FinTrack"))) == hash }) else { continue }
            let old = folder.appendingPathComponent("FinTrack-previous.app")
            guard let previous = Bundle(url: old), previous.bundleIdentifier == bundle.bundleIdentifier,
                  let oldBuild = previous.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                  let oldNumber = Int(oldBuild), let number = Int(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""), oldNumber < number else { continue }
            try? fm.removeItem(at: old)
            for item in prepared { try? fm.removeItem(at: item) }
            for name in ["FinTrack-update.dmg", "FinTrack-update.zip"] { try? fm.removeItem(at: folder.appendingPathComponent(name)) }
        }
    }
}
