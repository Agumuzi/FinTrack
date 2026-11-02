import Foundation
import Combine
import SwiftUI

/// Only this manifest enables a language. Draft catalog translations are retained.
nonisolated struct LocalizationManifest: Codable {
    struct Language: Codable, Equatable, Identifiable {
        var id: String
        var nativeName: String
    }
    var schemaVersion: Int
    var catalogVersion: String
    var languages: [Language]

    static func load(bundle: Bundle = .main) -> Self {
        guard let url = bundle.url(forResource: "LocalizationRelease", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.schemaVersion == 1,
              value.languages.contains(where: { $0.id == "en" }) else {
            return Self(schemaVersion: 1, catalogVersion: "fintrack-v1.5", languages: [.init(id: "en", nativeName: "English")])
        }
        return Self(schemaVersion: value.schemaVersion, catalogVersion: value.catalogVersion,
                    languages: value.languages.filter { bundle.path(forResource: $0.id, ofType: "lproj") != nil })
    }
}

/// Pure preference policy: no model context, accounting action, or financial write.
nonisolated enum LocalizationPolicy {
    static let selectionKey = "app_language"
    static let migrationKey = "v150_language_initialized"

    static func prepare(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: migrationKey) || defaults.object(forKey: selectionKey) == nil else { return }
        if defaults.object(forKey: selectionKey) == nil {
            let existing = defaults.bool(forKey: "fintrack_initial_setup_complete") ||
                defaults.bool(forKey: "v11_blank_initial_state") || defaults.object(forKey: "v2_last_page") != nil ||
                defaults.data(forKey: "v3_fx_monitor") != nil
            defaults.set(existing ? "zh-Hans" : "system", forKey: selectionKey)
        }
        // Explicit old choices, including a disabled draft locale, are never erased.
        defaults.set(true, forKey: migrationKey)
    }

    static func match(_ identifier: String, supported: [String]) -> String? {
        let canonical = identifier.replacingOccurrences(of: "_", with: "-")
        if let exact = supported.first(where: { $0.caseInsensitiveCompare(canonical) == .orderedSame }) { return exact }
        let parts = canonical.lowercased().split(separator: "-").map(String.init)
        guard let language = parts.first else { return nil }
        if language == "zh" {
            // Traditional Chinese has no release language in v1.5.
            if parts.contains("hant") || (!parts.contains("hans") && parts.contains(where: { ["tw", "hk", "mo"].contains($0) })) { return nil }
            if (parts.contains("hans") || parts.contains("cn") || parts.contains("sg")), supported.contains("zh-Hans") { return "zh-Hans" }
            return nil
        }
        return supported.first { $0.lowercased() == language }
    }

    static func resolve(selection: String, preferred: [String], supported: [String]) -> String {
        if selection != "system" { return match(selection, supported: supported) ?? "en" }
        return preferred.lazy.compactMap { match($0, supported: supported) }.first ?? "en"
    }
}

/// All UI hosts observe the same controller without replacing view identity.
@MainActor
final class LocalizationController: ObservableObject {
    static let shared = LocalizationController()
    @Published private(set) var selection: String
    @Published private(set) var effectiveLanguage: String
    @Published private(set) var revision = 0
    let manifest: LocalizationManifest
    private let defaults: UserDefaults
    private let preferredLanguages: () -> [String]
    private var subscriptions: [AnyCancellable] = []

    var locale: Locale { Locale(identifier: effectiveLanguage) }
    var choices: [(String, String)] {
        [(L10n.text("app.language.system"), "system")] + manifest.languages.map { ($0.nativeName, $0.id) }
    }

    init(defaults: UserDefaults = MacPreferences.defaults, manifest: LocalizationManifest = .load(),
         preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }, observe: Bool = true) {
        self.defaults = defaults; self.manifest = manifest; self.preferredLanguages = preferredLanguages
        LocalizationPolicy.prepare(in: defaults)
        let initialSelection = defaults.string(forKey: LocalizationPolicy.selectionKey) ?? "system"
        selection = initialSelection
        effectiveLanguage = LocalizationPolicy.resolve(selection: initialSelection, preferred: preferredLanguages(), supported: manifest.languages.map(\.id))
        L10n.setLanguage(effectiveLanguage)
        if observe {
            for name in [UserDefaults.didChangeNotification, NSLocale.currentLocaleDidChangeNotification,
                         NSApplication.didBecomeActiveNotification] {
                subscriptions.append(NotificationCenter.default.publisher(for: name).receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() })
            }
        }
    }

    func select(_ value: String) {
        guard value == "system" || manifest.languages.contains(where: { $0.id == value }) else { return }
        defaults.set(value, forKey: LocalizationPolicy.selectionKey)
        refresh()
    }

    func refresh() {
        let saved = defaults.string(forKey: LocalizationPolicy.selectionKey) ?? "system"
        let effective = LocalizationPolicy.resolve(selection: saved, preferred: preferredLanguages(), supported: manifest.languages.map(\.id))
        let changed = effective != effectiveLanguage
        L10n.setLanguage(effective)
        if selection != saved { selection = saved }
        if changed {
            DateHelper.clearFormatterCache()
            effectiveLanguage = effective
            revision += 1
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }
    static let didChange = Notification.Name("FinTrack.localizationDidChange")
}

/// Formatting can also run in nonisolated error descriptions. A locked snapshot
/// avoids consulting standard preferences from workers or from isolated tests.
nonisolated enum L10n {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var language = "en"
        var bundles: [String: Bundle] = [:]
        var missingKeys: Set<String> = []
    }
    private static let state = State()
    static func setLanguage(_ language: String) { state.lock.lock(); defer { state.lock.unlock() }; state.language = language }
    static var language: String { state.lock.lock(); defer { state.lock.unlock() }; return state.language }
    static var locale: Locale { Locale(identifier: language) }

    static func text(_ key: String) -> String { value(key, language: language) }
    static func value(_ key: String, language: String, bundle: Bundle = .main) -> String {
        let resolved = UIStringCatalogKeyResolver.resolve(key)
        let missing = "\u{001F}FinTrack.missing\u{001F}"
        func lookup(_ language: String) -> String? {
            guard let path = bundle.path(forResource: language, ofType: "lproj") else { return nil }
            state.lock.lock()
            let cached = state.bundles[path] ?? Bundle(path: path)
            if let cached { state.bundles[path] = cached }
            state.lock.unlock()
            guard let localized = cached else { return nil }
            let result = localized.localizedString(forKey: resolved, value: missing, table: "Localizable")
            let semanticKey = resolved.hasPrefix("mac.") || resolved.hasPrefix("legacy.")
            return result == missing || result.isEmpty || (semanticKey && result == resolved) ? nil : result
        }
        if let result = lookup(language) ?? lookup("en") { return result }
        // English legacy catalog keys are their own English default text.
        let semanticKey = ["mac.", "legacy.", "workspace.", "records.sort.", "app.language."].contains { key.hasPrefix($0) }
        if resolved != key || !semanticKey { return resolved }
        state.lock.lock(); let first = state.missingKeys.insert(key).inserted; state.lock.unlock()
        if first { NSLog("FinTrack localization missing key: %@", key) }
        return "[Missing translation]"
    }
    private static let builtInAliases: [String: String] = {
        guard let url = Bundle.main.url(forResource: "LocalizationLegacyAliases", withExtension: "json"),
              let data = try? Data(contentsOf: url), let aliases = try? JSONDecoder().decode([String:String].self, from: data) else { return [:] }
        return aliases
    }()
    /// Only for enumerated legacy identities. Never apply to user-entered text.
    static func builtIn(_ identity: String) -> String {
        builtInAliases[identity].map(text) ?? identity
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }
}

struct LocalizationEnvironment: ViewModifier {
    @ObservedObject private var localization = LocalizationController.shared
    func body(content: Content) -> some View {
        content.environment(\.locale, localization.locale)
    }
}

/// Keep the v1.4.8 preference bytes for rollback; accept stable IDs on read too.
enum MacRecordSort: String, CaseIterable {
    case newest, oldest, amountDescending
    var legacyValue: String {
        switch self { case .newest: "最新优先"; case .oldest: "最早优先"; case .amountDescending: "金额从高到低" }
    }
    var title: String { L10n.text("records.sort.\(rawValue)") }
    static func stored(_ value: String?) -> Self {
        allCases.first { $0.rawValue == value || $0.legacyValue == value } ?? .newest
    }
}

nonisolated enum MacClearConfirmation {
    static let token = "DELETE"
    static func accepts(_ input: String) -> Bool { input == token }
}

/// Exact confirmation follows the active UI resource; switching language never
/// replaces text already entered by the user or grants destructive consent.
nonisolated enum MacRestoreConfirmation {
    static var token: String { L10n.text("backup.restore.confirmation.token") }
    static var prompt: String { L10n.format("backup.restore.confirmation.prompt", token) }
    static func accepts(_ input: String) -> Bool {
        let expected=token
        guard !expected.isEmpty, expected != "[Missing translation]", expected.count<=64,
              expected.rangeOfCharacter(from:.newlines)==nil else { return false }
        return input == expected
    }
}
