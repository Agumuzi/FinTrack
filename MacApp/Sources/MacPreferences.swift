import Foundation

enum MacPreferences {
    static let isTesting: Bool = {
        let e = ProcessInfo.processInfo.environment
        #if FINTRACK_MENU_PROTOTYPE
        return true
        #else
        return e["FINTRACK_V12_UI_TEST"] == "1" || e["FINTRACK_V13_TEST_STORE_PATH"] != nil
        #endif
    }()

    static let defaults: UserDefaults = {
        guard isTesting else { return .standard }
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
        return store
    }()
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
