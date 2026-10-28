import Foundation

enum MacPreferences {
    static let blankInitialStateKey = "v11_blank_initial_state"
    static let officialUpdateSourceKey = "v11_official_update_source"
    static let isTesting: Bool = {
        let e = ProcessInfo.processInfo.environment
        #if FINTRACK_MENU_PROTOTYPE
        return true
        #else
        return e["FINTRACK_V12_UI_TEST"] == "1" || e["FINTRACK_V13_TEST_STORE_PATH"] != nil || MacTestStore.requiresExplicitIsolation(bundleURL:Bundle.main.bundleURL)
        #endif
    }()

    static let defaults: UserDefaults = {
        guard isTesting else {
            prepareInitialState(in: .standard)
            return .standard
        }
        let e = ProcessInfo.processInfo.environment
        #if FINTRACK_MENU_PROTOTYPE
        let defaultPrototypeToken: String? = "menu-prototype"
        #else
        let defaultPrototypeToken: String? = nil
        #endif
        let token = e["FINTRACK_MENU_PROTOTYPE_TOKEN"] ?? defaultPrototypeToken ?? e["FINTRACK_V13_TEST_STORE_PATH"].map {
            URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent
        } ?? "process-\(ProcessInfo.processInfo.processIdentifier)"
        let store = UserDefaults(suiteName: "dev.agumuzi.fintrack.tests.\(token)")!
        if store.object(forKey: "app_language") == nil {
            store.set(e["FINTRACK_TEST_LANGUAGE"] ?? "en", forKey: "app_language")
        }
        if store.object(forKey: "base_currency") == nil { store.set("USD", forKey: "base_currency") }
        #if FINTRACK_LOCAL_VALIDATION
        MacLocalValidationPreferences.apply(to: store)
        #endif
        prepareInitialState(in: store)
        #if FINTRACK_LOCAL_VALIDATION
        if e["FINTRACK_MENU_ONLY"] == "1" {
            var entries = MacAppEntryConfiguration.load(from: store)
            entries.showMainOnLaunch = false; entries.showMenuBar = true
            entries.defaultPage = .rates
            if let bytes = try? JSONEncoder().encode(entries) { store.set(bytes, forKey: MacAppEntryConfiguration.storageKey) }
        }
        #endif
        return store
    }()

    /// Preserve the implicit v1.0 currency directory for existing installations.
    /// Record the decision before onboarding so a new user remains empty afterward.
    static func prepareInitialState(in defaults: UserDefaults) {
        if !defaults.bool(forKey: officialUpdateSourceKey) {
            let url = defaults.string(forKey: "v2_update_url") ?? ""
            let key = defaults.string(forKey: "v2_update_public_key") ?? ""
            if url.isEmpty && key.isEmpty {
                defaults.set(MacUpdateService.officialManifestURL, forKey: "v2_update_url")
                defaults.set(MacUpdateService.officialPublicKey, forKey: "v2_update_public_key")
            }
            defaults.set(true, forKey: officialUpdateSourceKey)
        }
        let marker = blankInitialStateKey
        if defaults.object(forKey:"v141_background") == nil {
            let existing = defaults.bool(forKey:marker) || defaults.bool(forKey:"fintrack_initial_setup_complete") || defaults.data(forKey:MacFXConfiguration.storageKey) != nil
            defaults.set(existing,forKey:"v141_background")
        }
        guard !defaults.bool(forKey: marker) else { return }
        let existingInstallation = defaults.bool(forKey: "fintrack_initial_setup_complete") ||
            defaults.data(forKey: MacFXConfiguration.storageKey) != nil
        if existingInstallation {
            let legacy = ["USD", "RUB", "CNY", "EUR", "GBP", "JPY", "CHF", "HKD"]
            if defaults.data(forKey: "v2_currencies") == nil,
               let data = try? JSONEncoder().encode(legacy) {
                defaults.set(data, forKey: "v2_currencies")
            }
            // v1.0 showed these lists without persisting them until the user
            // edited FX settings. Materialize that visible state once on upgrade.
            if defaults.data(forKey: MacFXConfiguration.storageKey) == nil {
                let codes = defaults.data(forKey: "v2_currencies")
                    .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
                var config = MacFXConfiguration()
                config.referenceCurrency = codes.contains("USD") ? "USD" : codes.first ?? "USD"
                config.converterCurrencies = codes
                let reference = codes.contains("CNY") ? "CNY" : config.referenceCurrency
                config.watchedPairs = codes.filter { $0 != reference }.prefix(6)
                    .compactMap { try? MacFXPair(base: $0, quote: reference) }
                if let data = try? JSONEncoder().encode(config) {
                    defaults.set(data, forKey: MacFXConfiguration.storageKey)
                }
            }
        }
        defaults.set(true, forKey: marker)
    }
}

enum MacLocalization {
    static func value(_ key: String) -> String {
        let language = MacPreferences.isTesting ? (MacPreferences.defaults.string(forKey: "app_language") ?? "en") : "zh-Hans"
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    static func error(_ error: Error) -> String { value(error.localizedDescription) }
}

enum MacDateDisplay {
    static func string(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = MacPreferences.defaults.string(forKey: "app_date_format") ?? "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}
