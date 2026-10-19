import Foundation
import SwiftUI
import SwiftData
import AppKit
import CoreFoundation

/// V2 presentation settings live beside the original, unchanged financial schema.
enum MacSettingsStore {
    static var defaults: UserDefaults { MacPreferences.defaults }
    static func load<T: Decodable>(_ key: String, fallback: T) -> T {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
        return value
    }
    static func save<T: Encodable>(_ value: T, key: String) throws {
        defaults.set(try JSONEncoder().encode(value), forKey: key)
    }
    static let keys = ["base_currency", "color_theme_mode", "app_date_format", "fintrack_initial_setup_complete",
        "fintrack_auto_posting", "v2_navigation_collapsed", "v2_accent", "v2_density", "v2_font_tier", "v2_font_size",
        "v2_week_start", "v2_month_format", "v2_time_format", "v2_decimals", "v2_grouping", "v2_negative",
        "v2_zero", "v2_sort", "v2_page_size", "v2_chart_months", "v2_notes", "v2_resume_page", "v2_last_page", "v2_settings_page",
        "v2_confirm_records", "v2_confirm_categories", "v2_confirm_clear", "v2_remind_recurring", "v2_remind_goals",
        "v2_remind_budgets", "v2_display_name", "v2_avatar", "v2_budgets", "v2_category_styles", "v2_fx_sources",
        "v2_currencies", "v2_fx_quotes", "v2_disabled_currencies", "v2_region", "v2_fx_preferred_source", "v2_goal_presentation", "v2_backup_folder", "v2_backup_naming", "v2_update_auto", "v2_update_frequency", "v2_update_download", MacAppEntryConfiguration.storageKey, MacFXConfiguration.storageKey]
    static func snapshot() throws -> Data {
        migrateFontPreference()
        let machineLocalKeys: Set<String> = ["v2_backup_folder"]
        var values: [String: Any] = [:]
        for key in keys where !machineLocalKeys.contains(key) {
            if let value = defaults.object(forKey: key) { values[key] = value }
        }
        return try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
    }
    static func validateSettings(_ data: Data) throws -> [String: Any] {
        guard var values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              Set(values.keys).isSubset(of: Set(keys)) else { throw MacSettingsFailure.invalid("备份设置格式无效") }
        guard !(values["v2_font_tier"] != nil && values["v2_font_size"] != nil) else {
            throw MacSettingsFailure.invalid("备份包含冲突的字号设置")
        }
        // Optional fields may be absent in older backups, but present values must
        // match their storage type. Conditional casts alone silently skip bad data.
        let binaryKeys: Set<String> = ["v2_avatar", "v2_budgets", "v2_category_styles", "v2_fx_sources",
            "v2_currencies", "v2_fx_quotes", "v2_disabled_currencies", "v2_goal_presentation", MacAppEntryConfiguration.storageKey, MacFXConfiguration.storageKey]
        let booleanKeys: Set<String> = ["fintrack_initial_setup_complete", "fintrack_auto_posting", "v2_navigation_collapsed",
            "v2_notes", "v2_resume_page", "v2_confirm_records", "v2_confirm_categories", "v2_confirm_clear",
            "v2_remind_recurring", "v2_remind_goals", "v2_remind_budgets", "v2_update_auto", "v2_update_download"]
        let integerChoices: [String: Set<Int>] = ["v2_decimals": Set(0...4), "v2_week_start": [1, 2],
            "v2_page_size": [25, 50, 100], "v2_chart_months": [3, 6, 12]]
        for (key, value) in values {
            let valid: Bool
            if binaryKeys.contains(key) { valid = value is Data }
            else if booleanKeys.contains(key) {
                valid = (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            } else if let choices = integerChoices[key] {
                if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                   number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue {
                    valid = choices.contains { Double($0) == number.doubleValue }
                } else { valid = false }
            } else if key == "v2_font_tier" {
                valid = (value as? String).map { MacFontSizeTier(rawValue: $0) != nil } ?? false
            } else if key == "v2_font_size" {
                valid = (value as? NSNumber).map {
                    CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite && (10.4...19.5).contains($0.doubleValue)
                } ?? false
            } else { valid = value is String }
            guard valid else { throw MacSettingsFailure.invalid("备份中的设置类型或选项无效，请选择完整有效的备份文件") }
        }
        if let data = values[MacAppEntryConfiguration.storageKey] as? Data {
            let configuration = try JSONDecoder().decode(MacAppEntryConfiguration.self, from: data)
            values[MacAppEntryConfiguration.storageKey] = try JSONEncoder().encode(configuration.normalized())
        }
        if let data = values[MacFXConfiguration.storageKey] as? Data {
            values[MacFXConfiguration.storageKey] = try JSONEncoder().encode(try JSONDecoder().decode(MacFXConfiguration.self, from: data).normalized())
        }
        if let currency = values["base_currency"] as? String { _ = try MacCurrency.code(currency) }
        if let budgets = values["v2_budgets"] as? Data {
            let rows = try JSONDecoder().decode([MacBudget].self, from: budgets)
            guard Set(rows.map(\.id)).count == rows.count else { throw MacSettingsFailure.invalid("预算编号重复") }
            for row in rows { try row.validate() }
        }
        if let data = values["v2_avatar"] as? Data, !data.isEmpty { try MacImageAssets.validatePreparedPNG(data) }
        if let data = values["v2_fx_sources"] as? Data { let rows = try JSONDecoder().decode([MacFXSource].self, from: data); guard rows.count <= 50 else { throw MacSettingsFailure.invalid("汇率源数量过多") }; for row in rows { try row.validate() } }
        if let data = values["v2_fx_quotes"] as? Data {
            let rows = try JSONDecoder().decode([MacFXQuote].self, from: data)
            guard rows.count <= 2000 else { throw MacSettingsFailure.invalid("报价记录数量过多") }
            for row in rows { _ = try MacCurrency.code(row.from); _ = try MacCurrency.code(row.to); guard row.rate.isFinite, row.rate > 0, row.rate <= 1e9 else { throw MacSettingsFailure.invalid("报价记录无效") } }
        }
        if let data = values["v2_goal_presentation"] as? Data {
            let rows = try JSONDecoder().decode([String: MacGoalPresentation].self, from: data)
            for row in rows.values {
                guard MacPresentationOptions.icons.contains(where: { $0.0 == row.icon }), MacPresentationOptions.validColor(row.color),
                      ["高", "普通", "低"].contains(row.priority), row.note.count <= 200 else {
                    throw MacSettingsFailure.invalid("目标图标、颜色或备注无效")
                }
            }
        }
        if let data = values["v2_category_styles"] as? Data {
            let rows = try JSONDecoder().decode([String: MacCategoryStyle].self, from: data)
            for row in rows.values { guard row.emoji == nil || MacCategoryEmoji.isValid(row.emoji!), MacCategoryCatalog.symbols.contains(row.symbol), (MacCategoryCatalog.colors.contains(row.color) || row.color.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil) else { throw MacSettingsFailure.invalid("分类显示设置无效") } }
        }
        return values
    }
    static let restoreCompleted = Notification.Name("FinTrack.settingsRestoreCompleted")
    static func restorationNotice(_ data: Data) -> String? {
        guard let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bytes = values[MacAppEntryConfiguration.storageKey] as? Data,
              (try? JSONDecoder().decode(MacAppEntryConfiguration.self, from: bytes)) != nil,
              let raw = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let menu = raw["showMenuBar"] as? NSNumber, CFGetTypeID(menu) == CFBooleanGetTypeID(), !menu.boolValue,
              let dock = raw["showDock"] as? NSNumber, CFGetTypeID(dock) == CFBooleanGetTypeID(), !dock.boolValue else { return nil }
        return "备份中的菜单栏和 Dock 均关闭；恢复后会启用两个入口，确保可以重新打开应用。"
    }
    static func restoreSettings(_ values: [String: Any]) {
        let machineLocalKeys: Set<String> = ["v2_backup_folder"]
        for key in keys where !machineLocalKeys.contains(key) { defaults.removeObject(forKey: key) }
        for (key, value) in values where !machineLocalKeys.contains(key) { defaults.set(value, forKey: key) }
        migrateFontPreference()
        // A restored ledger never starts posting money without an explicit opt-in.
        defaults.set(false, forKey: "fintrack_auto_posting")
    }

    /// Convert the former 80–150% continuous setting once, keeping old backups readable.
    static func migrateFontPreference() {
        if let saved = defaults.string(forKey: MacFontSizeTier.preferenceKey) {
            let tier = MacFontSizeTier(rawValue: saved) ?? .standard
            defaults.set(tier.rawValue, forKey: MacFontSizeTier.preferenceKey)
            defaults.removeObject(forKey: MacFontSizeTier.legacyPreferenceKey)
            return
        }

        guard let legacy = defaults.object(forKey: MacFontSizeTier.legacyPreferenceKey) else { return }
        let number = legacy as? NSNumber
        let isValidNumber = number.map {
            CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite && (10.4...19.5).contains($0.doubleValue)
        } ?? false
        let tier: MacFontSizeTier
        if isValidNumber, let number { tier = MacFontSizeTier.migratingLegacyValue(number.doubleValue) }
        else { tier = .standard }
        defaults.set(tier.rawValue, forKey: MacFontSizeTier.preferenceKey)
        defaults.removeObject(forKey: MacFontSizeTier.legacyPreferenceKey)
    }
}

enum MacSettingsFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

struct MacBudget: Codable, Identifiable, Hashable {
    var id = UUID()
    var month: String
    var categoryID: UUID?
    var categoryName: String?
    var currency: String
    var amount: Double
    var enabled = true
    var note = ""
    // Optional fields keep budgets from older native backups readable.
    var icon: String? = nil
    var color: String? = nil
    var displayIcon: String { icon ?? categoryName.map { MacCategoryCatalog.emoji(name: $0) } ?? "chart.pie.fill" }
    var displayColor: String { color ?? "red" }
    func validate() throws {
        _ = try MacCurrency.code(currency)
        guard amount.isFinite, amount > 0, amount <= 1_000_000_000_000,
              month.range(of: #"^\d{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil,
              note.count <= 500,
              icon == nil || MacPresentationOptions.icons.contains(where: { $0.0 == icon }),
              color == nil || MacPresentationOptions.validColor(color!) else { throw MacSettingsFailure.invalid("请检查预算月份、金额与备注") }
    }
}

enum MacBudgetData {
    static func month(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year!, c.month!)
    }
    static func spent(_ budget: MacBudget, rows: [Transaction], categories: [Category]) -> Double {
        let name = budget.categoryID.flatMap { id in categories.first { $0.id == id }?.name } ?? budget.categoryName
        return FinancialPrecision.roundAmountForStorage(rows.filter {
            $0.deletedAt == nil && $0.typedType == .expense && $0.baseCurrencyCode == budget.currency &&
            month($0.date) == budget.month && (name == nil || $0.category == name)
        }.reduce(0) { $0 + $1.baseAmount })
    }
    static func save(_ row: MacBudget) throws {
        try row.validate()
        var all: [MacBudget] = MacSettingsStore.load("v2_budgets", fallback: [])
        guard !all.contains(where: { $0.id != row.id && $0.month == row.month && $0.currency == row.currency && ($0.categoryID != nil ? $0.categoryID == row.categoryID : row.categoryID == nil && $0.categoryName == row.categoryName) })
        else { throw MacSettingsFailure.invalid("该月份已有相同预算，请编辑现有条目") }
        if let index = all.firstIndex(where: { $0.id == row.id }) { all[index] = row } else { all.append(row) }
        try MacSettingsStore.save(all, key: "v2_budgets")
    }
}

struct MacCategoryStyle: Codable {
    var symbol = "tag"
    var color = "orange"
    var order = 0
    var emoji: String? = nil
}

enum MacDisplayPreferences {
    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = MacPreferences.defaults.integer(forKey: "v2_week_start") == 1 ? 1 : 2
        return calendar
    }
    static func money(_ amount: Double, decimals selectedDecimals: Int? = nil, grouping selectedGrouping: String? = nil, negative selectedNegative: String? = nil, zero selectedZero: String? = nil) -> String {
        let d = MacPreferences.defaults
        let decimals = min(4, max(0, selectedDecimals ?? (d.object(forKey: "v2_decimals") == nil ? 2 : d.integer(forKey: "v2_decimals"))))
        let grouping = selectedGrouping ?? d.string(forKey: "v2_grouping") ?? "comma"
        let negative = selectedNegative ?? d.string(forKey: "v2_negative") ?? "minus"
        if amount == 0 && (selectedZero ?? d.string(forKey: "v2_zero")) == "dash" { return "—" }
        let f = NumberFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.numberStyle = .decimal
        f.minimumFractionDigits = decimals; f.maximumFractionDigits = decimals
        f.usesGroupingSeparator = grouping != "none"
        f.groupingSeparator = grouping == "space" ? " " : ","
        let result = f.string(from: NSNumber(value: amount)) ?? String(amount)
        return amount < 0 && negative == "parentheses" ? "(\(String(result.dropFirst())))" : result
    }
    static func month(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = MacPreferences.defaults.string(forKey: "v2_month_format") ?? "yyyy年M月"
        return f.string(from: date)
    }
    static func time(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = MacPreferences.defaults.string(forKey: "v2_time_format") ?? "HH:mm"
        return f.string(from: date)
    }
}

struct MacSettingsCard<Content: View>: View {
    @AppStorage("v2_density") private var density = "comfortable"
    var title: String
    var icon: String
    var subtitle: String = ""
    var headerColor: Color? = nil
    var action: AnyView? = nil
    var compactHeader = false
    var heading: AnyView? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(12)) {
            if !title.isEmpty {
            HStack(spacing: MacUI.space(12)) {
                if compactHeader { MacSettingsSymbol(symbol: icon, size: 20).frame(width: MacUI.space(25)) }
                else { MacSettingsIcon(symbol: icon, color: headerColor ?? MacSettingsVisual.headerColor(title), size: 36) }
                VStack(alignment: .leading, spacing: MacUI.space(4)) {
                    if let heading { heading } else { Text(title).appFont(.section, weight: .semibold, design: .default) }
                    if !subtitle.isEmpty { Text(subtitle).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer(minLength: 0)
                if let action { action }
            }
            }
            content
        }.appFont(.body, weight: .regular, design: .default)
            .appPadding(density == "compact" ? 16 : density == "spacious" ? 24 : 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.035)))
    }
}

struct MacSettingsColumns<Left: View, Right: View>: View {
    var wide: Bool
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right
    var body: some View {
        if wide {
            HStack(alignment: .top, spacing: MacUI.space(16)) { left.frame(maxWidth: .infinity); right.frame(maxWidth: .infinity) }
        } else { VStack(alignment: .leading, spacing: MacUI.space(16)) { left; right } }
    }
}

struct MacBrandIcon: View {
    var size: CGFloat = 34
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
    }
}
