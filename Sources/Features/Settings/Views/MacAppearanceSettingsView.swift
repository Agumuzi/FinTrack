import SwiftUI
import Charts
import AppKit

struct MacThemeChoices: View {
    @Binding var theme: String
    var body: some View {
        HStack(spacing: MacUI.space(10)) {
            choice("浅色", value: "light", icon: "sun.max")
            choice("深色", value: "dark", icon: "moon")
            choice("跟随系统", value: "system", icon: "desktopcomputer")
        }
    }
    private func choice(_ title: String, value: String, icon: String) -> some View {
        Button { theme = value } label: {
            VStack(spacing: MacUI.space(9)) {
                MacThemeThumbnail(mode: value).appMinHeight(50)
                    .overlay(alignment: .topTrailing) {
                        if theme == value { Image(systemName: "checkmark.circle.fill").appFont(.body, weight: .regular, design: .default).foregroundStyle(.blue).background(.white, in: Circle()).appPadding(4) }
                    }
                Label(title, systemImage: icon).appFont(.body, weight: .semibold, design: .default)
            }.appPadding(8).frame(maxWidth: .infinity)
                .background(theme == value ? MacSettingsVisual.accent.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme == value ? MacSettingsVisual.accent : .gray.opacity(0.15), lineWidth: theme == value ? 1.6 : 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("theme-" + value).accessibilityValue(theme == value ? "已选中" : "未选中")
    }
}

struct MacThemeThumbnail: View {
    var mode: String
    private func window(dark: Bool) -> some View {
        VStack(spacing: MacUI.space(0)) {
            HStack(spacing: MacUI.space(3)) { Circle().fill(.red); Circle().fill(.yellow); Circle().fill(.green); Spacer() }.frame(height: MacUI.space(5)).appPadding(6).background(dark ? Color(white: 0.21) : Color(white: 0.94))
            HStack(spacing: MacUI.space(5)) {
                VStack(spacing: MacUI.space(5)) { ForEach(0..<3) { _ in Capsule().fill(dark ? Color(white: 0.38) : Color(white: 0.82)).frame(height: MacUI.space(4)) }; Spacer(minLength: 0) }.frame(width: MacUI.space(25)).appPadding(5).background(dark ? Color(white: 0.18) : Color(white: 0.94))
                VStack(spacing: MacUI.space(5)) { ForEach(0..<2) { _ in RoundedRectangle(cornerRadius: 3).fill(dark ? Color(white: 0.27) : .white).overlay(alignment: .leading) { Capsule().fill(dark ? Color(white: 0.4) : Color(white: 0.88)).frame(width: MacUI.space(24), height: MacUI.space(4)).appPadding(5) } } }.appPadding(.vertical, 5).appPadding(.trailing, 5)
            }
        }.background(dark ? Color(white: 0.12) : Color(white: 0.97)).clipShape(RoundedRectangle(cornerRadius: 6))
    }
    var body: some View {
        GeometryReader { geo in
            ZStack {
                window(dark: false)
                if mode == "dark" { window(dark: true) }
                if mode == "system" {
                    window(dark: true).mask {
                        Path { p in p.move(to: CGPoint(x: geo.size.width * 0.65, y: 0)); p.addLine(to: CGPoint(x: geo.size.width, y: 0)); p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height)); p.addLine(to: CGPoint(x: geo.size.width * 0.25, y: geo.size.height)); p.closeSubpath() }.fill(.white)
                    }
                }
            }.overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.gray.opacity(0.18)))
        }
    }
}

struct MacAppearanceSettingsView: View {
    var wide: Bool
    @Binding var fontTierValue: String
    @AppStorage("color_theme_mode") private var theme = "system"
    @AppStorage("v2_accent") private var accent = "red"
    @AppStorage("v2_density") private var density = "comfortable"
    @AppStorage("v2_navigation_collapsed") private var collapsed = false
    var body: some View {
        MacSettingsColumns(wide: wide) {
            VStack(spacing: MacUI.space(14)) {
                MacSettingsCard(title: "主题模式", icon: "sun.max", subtitle: "选择应用的整体外观风格。", headerColor: .red) { MacThemeChoices(theme: $theme) }
                MacSettingsCard(title: "强调色", icon: "paintpalette", subtitle: "用于按钮、图表和高亮元素。", headerColor: .red) { MacColorChoices(selection: $accent) }
                MacSettingsCard(title: "界面密度", icon: "rectangle.split.3x1", subtitle: "调整列表、表格和卡片的显示密度。", headerColor: .red) {
                    HStack(spacing: MacUI.space(8)) {
                        densityChoice("舒适", value: "comfortable", icon: "list.bullet")
                        densityChoice("紧凑", value: "compact", icon: "line.3.horizontal")
                        densityChoice("宽松", value: "spacious", icon: "rectangle.grid.1x2")
                    }
                }
                MacInterfaceFontSettings()
                if !wide { fontSizeCard }
                MacSettingsCard(title: "侧边栏外观", icon: "sidebar.left", subtitle: "调整左侧导航栏的显示方式。", headerColor: .red) {
                    HStack(spacing: MacUI.space(10)) {
                        navigationChoice("默认宽度", collapsed: false, icon: "sidebar.left", detail: "显示图标和文字")
                        navigationChoice("仅图标", collapsed: true, icon: "rectangle.lefthalf.inset.filled", detail: "只显示图标，节省空间")
                    }
                }
                HStack { Spacer(); Button("恢复默认外观") { theme = "system"; accent = "red"; density = "comfortable"; fontTierValue = MacFontSizeTier.standard.rawValue; MacPreferences.defaults.removeObject(forKey: MacInterfaceFonts.preferenceKey); collapsed = false }.accessibilityIdentifier("resetAppearance") }
            }
        } right: {
            VStack(spacing: MacUI.space(14)) {
                MacSettingsCard(title: "界面预览", icon: "eye", headerColor: .blue) {
                    MacAppearancePreview(accent: MacAccent.color(accent), collapsed: collapsed, density: density)
                        .frame(height: MacUI.fontTier == .large ? 480 : 420)
                }
                    .accessibilityElement(children: .contain).accessibilityIdentifier("appearanceLivePreview")
                if wide { fontSizeCard }
                MacSettingsCard(title: "语言设置", icon: "globe", subtitle: "应用界面语言。") {
                    MacLanguageChoice()
                }
            }
        }
    }
    private var fontSizeCard: some View {
                MacSettingsCard(title: "字体大小", icon: "textformat.size", subtitle: "正文与说明分别调整字号，页面间距和控件尺寸保持稳定。", headerColor: .red) {
                    HStack(spacing: MacUI.space(8)) {
                        ForEach(MacFontSizeTier.allCases) { tier in
                            Button {
                                fontTierValue = tier.rawValue
                            } label: {
                                VStack(alignment: .leading, spacing: MacUI.space(5)) {
                                    Text(tier.title).appFont(.body, weight: .semibold, design: .default)
                                    Text("正文 \(Int(tier.bodySize)) / 说明 \(Int(tier.captionSize))").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                                .appPadding(8)
                                .contentShape(Rectangle())
                                .background(fontTierValue == tier.rawValue ? MacSettingsVisual.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(fontTierValue == tier.rawValue ? MacSettingsVisual.accent : .gray.opacity(0.18)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("fontTier-\(tier.rawValue)")
                            .accessibilityValue(fontTierValue == tier.rawValue ? "已选中" : "未选中")
                        }
                    }

                }
    }
    private func densityChoice(_ title: String, value: String, icon: String) -> some View {
        Button { density = value } label: {
            HStack(spacing: MacUI.space(7)) { Image(systemName: icon).appIconFont(20); Text(title).appFont(.body, weight: .semibold); Spacer(minLength: 0) }
                .appPadding(8).frame(maxWidth: .infinity, minHeight: MacUI.space(42), alignment: .leading)
                .contentShape(Rectangle())
                .background(density == value ? MacSettingsVisual.accent.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(density == value ? MacSettingsVisual.accent : .gray.opacity(0.18)))
        }.buttonStyle(.plain).accessibilityIdentifier("density-" + value).accessibilityValue(density == value ? "已选中" : "未选中")
    }
    private func navigationChoice(_ title: String, collapsed value: Bool, icon: String, detail: String) -> some View {
        Button { collapsed = value } label: {
            HStack { Image(systemName: icon).appIconFont(21, weight: .regular, design: .default); VStack(alignment: .leading, spacing: MacUI.space(3)) { Text(title).appFont(.body, weight: .semibold, design: .default); Text(detail).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }; Spacer(minLength: 0) }
                .appPadding(10).frame(maxWidth: .infinity).contentShape(Rectangle()).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(collapsed == value ? MacSettingsVisual.accent : .gray.opacity(0.18)))
        }.buttonStyle(.plain).accessibilityIdentifier(value ? "settingsNavigationIcons" : "settingsNavigationFull").accessibilityValue(collapsed == value ? "已选中" : "未选中")
    }
}

struct MacAppearancePreview: View {
    var accent: Color
    var collapsed: Bool
    var density: String
    @AppStorage("base_currency") private var currency = "USD"
    @State private var page = "概览"
    @State private var month = Date()
    private let nav = [("概览", "house"), ("账目", "doc.text"), ("存款", "building.columns"), ("周期", "clock.arrow.circlepath"), ("贷款", "banknote")]
    var body: some View {
        HStack(spacing: MacUI.space(0)) {
            VStack(alignment: .leading, spacing: MacUI.space(9)) {
                HStack(spacing: MacUI.space(4)) { Circle().fill(.red); Circle().fill(.yellow); Circle().fill(.green) }.frame(width: MacUI.space(38), height: MacUI.space(9)).appPadding(.vertical, 7)
                HStack(spacing: MacUI.space(6)) { MacBrandIcon(size: 22); if !collapsed { Text("FinTrack").appFont(.caption, weight: .semibold, design: .default) } }.appPadding(.vertical, 4)
                ForEach(nav, id: \.0) { item in
                    Button { page = item.0 } label: { HStack(spacing: MacUI.space(6)) { Image(systemName: item.1).frame(width: MacUI.space(16)); if !collapsed { Text(item.0) }; Spacer(minLength: 0) }.appFont(.caption, weight: .regular, design: .default).appPadding(7).foregroundStyle(page == item.0 ? accent : .primary).background(page == item.0 ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain)
                }
                Spacer()
            }.appPadding(9).frame(width: collapsed ? 50 : 105).background(MacOverviewStyle.navigation)
            VStack(alignment: .leading, spacing: density == "compact" ? 10 : 15) {
                HStack { Text(page).appFont(.body, weight: .bold, design: .default); Spacer(); Image(systemName: "magnifyingglass"); Image(systemName: "plus") }.appFont(.caption, weight: .regular, design: .default)
                HStack { Button { month = Calendar.current.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left") }; Text(MacDisplayPreferences.month(month)).appFont(.caption, weight: .medium, design: .default); Button { month = Calendar.current.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right") }; Spacer() }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: MacUI.space(9)) {
                    Text(page == "概览" ? "资产总览" : page + "概况").appFont(.caption, weight: .semibold, design: .default)
                    Text("12345 " + MacSettingsVisual.symbol(currency)).appFont(.amount, weight: .semibold, design: .default).fixedSize(horizontal: false, vertical: true)
                    Chart(Array([18.0, 24, 22, 31, 30, 38, 41, 39, 47, 52, 51, 60].enumerated()), id: \.offset) { point in
                        AreaMark(x: .value("日期", point.offset), y: .value("示例资产", point.element)).foregroundStyle(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.01)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.catmullRom)
                        LineMark(x: .value("日期", point.offset), y: .value("示例资产", point.element)).foregroundStyle(accent).interpolationMethod(.catmullRom)
                    }.chartXAxis(.hidden).chartYAxis(.hidden).frame(minHeight: 44, maxHeight: .infinity)
                }.appPadding(13).frame(maxHeight: .infinity).background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: MacUI.space(8)) {
                    Text("最近交易").appFont(.caption, weight: .semibold, design: .default)
                    previewRecord("餐饮", icon: "fork.knife", color: .orange, amount: "−123 " + MacSettingsVisual.symbol(currency))
                    Divider(); previewRecord("购物", icon: "bag", color: .orange, amount: "−1234 " + MacSettingsVisual.symbol(currency))
                    Divider(); previewRecord("住房", icon: "house.fill", color: .blue, amount: "−12345 " + MacSettingsVisual.symbol(currency))
                }.appPadding(13).background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 10))
                Spacer(minLength: 0)
            }.appPadding(12).frame(maxWidth: .infinity, maxHeight: .infinity).background(MacOverviewStyle.canvas)
        }.clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.gray.opacity(0.1)))
    }
    private func previewRecord(_ title: String, icon: String, color: Color, amount: String) -> some View {
        HStack(spacing: MacUI.space(7)) { MacCategoryBadge(name: title, size: 25, filled: false); VStack(alignment: .leading, spacing: MacUI.space(3)) { Text(title).appFont(.caption, weight: .medium, design: .default); Text(MacDateDisplay.string(Date())).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }; Spacer(minLength: 0); Text(amount).appFont(.caption, weight: .semibold, design: .default).foregroundStyle(.red) }
    }
}

enum MacAccent {
    static func color(_ name: String) -> Color {
        if name.hasPrefix("#"), let value = UInt64(name.dropFirst(), radix: 16), name.count == 7 { return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255) }
        switch name { case "red": return .red; case "yellow": return .yellow; case "orange": return .orange; case "green": return .green; case "blue": return .blue; case "purple": return .purple; case "pink": return .pink; default: return Color(red: 0.85, green: 0.47, blue: 0.34) }
    }
    static func hex(_ color: Color) -> String {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return "#FF3B30" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

struct MacLanguageChoice: View {
    @AppStorage("app_language") private var language = "zh-Hans"
    var body: some View {
        MacSettingsMenu(selection: $language, options: [("简体中文", "zh-Hans")])
            .accessibilityIdentifier("settingsLanguageMenu")
    }
}
