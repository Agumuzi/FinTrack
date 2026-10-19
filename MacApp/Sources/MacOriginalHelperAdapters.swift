import Foundation

/// Platform interfaces for the unchanged original category/date/comparison helpers.
@MainActor
final class LanguageManager {
    static let shared = LanguageManager()
    var currentLocale: Locale { Locale(identifier: MacPreferences.defaults.string(forKey: "app_language") ?? "en") }
    func ui(_ key: String) -> String { MacLocalization.value(UIStringCatalogKeyResolver.resolve(key)) }
    func uiFormat(_ key: String) -> String { ui(key) }
}

struct DateFormatManager {
    func string(from date: Date) -> String { MacDateDisplay.string(date) }
}

struct CategoryChipItem: Identifiable, Hashable {
    let title: String
    let value: String
    var id: String { value }
}
