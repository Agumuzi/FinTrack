import SwiftUI
import Charts
import AppKit

struct MacThemeChoices: View {
    @AppStorage(MacCustomTypography.bodyKey, store: MacPreferences.defaults) private var bodyPoints = 16
    @Binding var theme: String
    var body: some View {
        let _ = bodyPoints
        HStack(spacing: MacUI.space(10)) {
            choice("浅色", value: "light", icon: "sun.max")
            choice("深色", value: "dark", icon: "moon")
            choice("跟随系统", value: "system", icon: "desktopcomputer")
        }
    }
    private func choice(_ title: String, value: String, icon: String) -> some View {
        Button { theme = value } label: {
            VStack(spacing: MacUI.space(9)) {
                MacThemePreviewLayout { MacThemeThumbnail(mode: value) }
                    .overlay(alignment: .topTrailing) {
                        if theme == value { Image(systemName: "checkmark.circle.fill").appFont(.body, weight: .regular, design: .default).foregroundStyle(.blue).background(.white, in: Circle()).appPadding(4) }
                    }
                Label(title, systemImage: icon).appFont(.body, weight: .semibold, design: .default).fixedSize(horizontal: false, vertical: true).frame(height: max(32, MacUI.fontTier.bodySize * 2.4))
            }.appPadding(8).frame(maxWidth: .infinity)
                .background(theme == value ? MacSettingsVisual.accent.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme == value ? MacSettingsVisual.accent : .gray.opacity(0.15), lineWidth: theme == value ? 1.6 : 1))
                .contentShape(Rectangle())
        }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("theme-" + value).accessibilityValue(theme == value ? "已选中" : "未选中")
    }
}

/// Give the thumbnail a definite aspect before its GeometryReader is measured.
struct MacThemePreviewLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(1, proposal.width ?? 120)
        return CGSize(width: width, height: min(130, max(54, width / 1.65)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: .init(bounds.size))
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
    @AppStorage(MacCustomTypography.bodyKey, store: MacPreferences.defaults) private var bodyPoints = 16
    @AppStorage(MacCustomTypography.captionKey, store: MacPreferences.defaults) private var captionPoints = 12
    @AppStorage(MacInterfaceZoom.key, store: MacPreferences.defaults) private var zoomPercent = 100
    @AppStorage("color_theme_mode") private var theme = "system"
    @AppStorage("v2_accent") private var accent = "red"
    @AppStorage("v2_density") private var density = "comfortable"
    @AppStorage("v2_navigation_collapsed") private var collapsed = false
    var body: some View {
        let _ = bodyPoints; let _ = captionPoints
        MacSettingsColumns(wide: wide) {
            VStack(spacing: MacUI.space(14)) {
                MacSettingsCard(title: "主题模式", icon: "sun.max", subtitle: "选择应用的整体外观风格。", headerColor: .red) { MacThemeChoices(theme: $theme) }
                HStack(spacing: 12) {
                    MacSettingsIcon(symbol: "paintpalette", color: .red, size: 36)
                    VStack(alignment: .leading, spacing: 4) { Text("强调色").appFont(.section, weight: .semibold); Text("用于按钮、图表和高亮元素。").appFont(.caption).foregroundStyle(.secondary) }
                    Spacer(minLength: 8); MacColorChoices(selection: $accent)
                }.padding(16).background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 13))
                MacSettingsCard(title: "界面密度", icon: "rectangle.split.3x1", subtitle: "调整列表、表格和卡片的显示密度。", headerColor: .red) {
                    HStack(spacing: MacUI.space(8)) {
                        densityChoice("舒适", value: "comfortable", icon: "list.bullet")
                        densityChoice("紧凑", value: "compact", icon: "line.3.horizontal")
                        densityChoice("宽松", value: "spacious", icon: "rectangle.grid.1x2")
                    }
                }
                MacSettingsCard(title: "界面缩放", icon: "plus.magnifyingglass", subtitle: "等比例调整界面、间距和控件。字体大小独立设置。") {
                    HStack {
                        Text("缩放比例").appFont(.body)
                        Spacer()
                        Button { MacInterfaceZoom.adjust(-1) } label: { Image(systemName: "minus") }.accessibilityIdentifier("zoomDecrease").disabled(MacInterfaceZoom.percent <= 50)
                        Text("\(MacInterfaceZoom.percent)%").appFont(.body, weight: .semibold).monospacedDigit().frame(minWidth: 64).accessibilityIdentifier("interfaceZoomValue")
                        Button { MacInterfaceZoom.adjust(1) } label: { Image(systemName: "plus") }.accessibilityIdentifier("zoomIncrease").disabled(MacInterfaceZoom.percent >= 150)
                        Button("100%") { MacInterfaceZoom.reset() }.accessibilityIdentifier("zoomReset")
                    }
                    Text("⌘＋ / ⌘－ 每次调整 10%；⌘0 恢复 100%。").appFont(.caption).foregroundStyle(.secondary)
                }
                MacInterfaceFontSettings()
                if !wide { fontSizeCard }
                MacSettingsCard(title: "侧边栏外观", icon: "sidebar.left", subtitle: "调整左侧导航栏的显示方式。", headerColor: .red) {
                    HStack(spacing: MacUI.space(10)) {
                        navigationChoice("默认宽度", collapsed: false, icon: "sidebar.left", detail: "显示图标和文字")
                        navigationChoice("仅图标", collapsed: true, icon: "rectangle.lefthalf.inset.filled", detail: "只显示图标，节省空间")
                    }
                }
                HStack { Spacer(); Button("恢复默认外观") { theme = "system"; accent = "red"; density = "comfortable"; MacCustomTypography.reset(); MacInterfaceZoom.reset(); fontTierValue = MacFontSizeTier.standard.rawValue; MacPreferences.defaults.removeObject(forKey: MacInterfaceFonts.preferenceKey); collapsed = false }.accessibilityIdentifier("resetAppearance") }
            }
        } right: {
            VStack(spacing: MacUI.space(14)) {
                MacSettingsCard(title: "界面预览", icon: "eye", headerColor: .blue) {
                    MacAppearancePreview(accent: MacAccent.color(accent), collapsed: collapsed, density: density)
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
        MacSettingsCard(title: "字体大小", icon: "textformat.size", subtitle: "单独调整正文和说明文字；不改变界面缩放比例。", headerColor: .red) {
            MacFontSizeInputRow(title: "正文字号", detail: "10–32 点", value: Binding(get: { Int(MacUI.fontTier.bodySize) }, set: { MacCustomTypography.set(body: $0, caption: Int(MacUI.fontTier.captionSize)) }), range: MacCustomTypography.bodyRange, identifier: "bodyFontSize")
            Divider()
            MacFontSizeInputRow(title: "说明字号", detail: "8–28 点", value: Binding(get: { Int(MacUI.fontTier.captionSize) }, set: { MacCustomTypography.set(body: Int(MacUI.fontTier.bodySize), caption: $0) }), range: MacCustomTypography.captionRange, identifier: "captionFontSize")
            HStack(spacing: 8) {
                ForEach(MacFontSizeTier.allCases.filter { $0 != .custom }) { tier in
                    Button(tier.title) { fontTierValue = tier.rawValue }.buttonStyle(.bordered)
                        .accessibilityIdentifier("fontTier-" + tier.rawValue).accessibilityValue(fontTierValue == tier.rawValue ? "已选中" : "未选中")
                }
                Spacer()
                Button("恢复默认") { MacCustomTypography.reset(); fontTierValue = "standard" }.accessibilityIdentifier("resetFontSizes")
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
        }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("density-" + value).accessibilityValue(density == value ? "已选中" : "未选中")
    }
    private func navigationChoice(_ title: String, collapsed value: Bool, icon: String, detail: String) -> some View {
        Button { collapsed = value } label: {
            HStack { Image(systemName: icon).appIconFont(21, weight: .regular, design: .default); VStack(alignment: .leading, spacing: MacUI.space(3)) { Text(title).appFont(.body, weight: .semibold, design: .default); Text(detail).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }; Spacer(minLength: 0) }
                .appPadding(10).frame(maxWidth: .infinity).contentShape(Rectangle()).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(collapsed == value ? MacSettingsVisual.accent : .gray.opacity(0.18)))
        }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier(value ? "settingsNavigationIcons" : "settingsNavigationFull").accessibilityValue(collapsed == value ? "已选中" : "未选中")
    }
}

struct MacAppearancePreview: View {
    @AppStorage(MacCustomTypography.captionKey, store: MacPreferences.defaults) private var captionPoints = 12
    var accent: Color
    var collapsed: Bool
    var density: String
    @AppStorage("base_currency") private var currency = "USD"
    @State private var page = "概览"
    @State private var month = Date()
    private let nav = [("概览", "house"), ("账目", "doc.text"), ("存款", "building.columns"), ("周期", "clock.arrow.circlepath"), ("贷款", "banknote")]
    var body: some View {
        let _ = captionPoints
        HStack(alignment: .top, spacing: MacUI.space(0)) {
            VStack(alignment: .leading, spacing: MacUI.space(9)) {
                HStack(spacing: MacUI.space(4)) { Circle().fill(.red); Circle().fill(.yellow); Circle().fill(.green) }.frame(width: MacUI.space(38), height: MacUI.space(9)).appPadding(.vertical, 7)
                HStack(spacing: MacUI.space(6)) { MacBrandIcon(size: 22); if !collapsed { Text("FinTrack").appFont(.caption, weight: .semibold, design: .default) } }.appPadding(.vertical, 4)
                ForEach(nav, id: \.0) { item in
                    Button { page = item.0 } label: { HStack(spacing: MacUI.space(6)) { Image(systemName: item.1).frame(width: MacUI.space(16)); if !collapsed { Text(item.0) }; Spacer(minLength: 0) }.appFont(.caption, weight: .regular, design: .default).appPadding(7).foregroundStyle(page == item.0 ? accent : .primary).background(page == item.0 ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(MacInteractiveButtonStyle())
                }
                Spacer()
            }.appPadding(9).frame(width: collapsed ? 50 : 105 + max(0, MacUI.fontTier.captionSize - 12) * 4).frame(maxHeight: .infinity).background(MacOverviewStyle.navigation)
            VStack(alignment: .leading, spacing: density == "compact" ? 10 : 15) {
                HStack { Text(page).appFont(.body, weight: .bold, design: .default); Spacer(); Image(systemName: "magnifyingglass"); Image(systemName: "plus") }.appFont(.caption, weight: .regular, design: .default)
                HStack { Button { month = Calendar.current.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left") }; Text(MacDisplayPreferences.month(month)).appFont(.caption, weight: .medium, design: .default); Button { month = Calendar.current.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right") }; Spacer() }.buttonStyle(MacInteractiveButtonStyle())
                VStack(alignment: .leading, spacing: MacUI.space(9)) {
                    Text(page == "概览" ? "资产总览" : page + "概况").appFont(.caption, weight: .semibold, design: .default)
                    Text("12345 " + MacSettingsVisual.symbol(currency)).appFont(.amount, weight: .semibold, design: .default).fixedSize(horizontal: false, vertical: true)
                    Chart(Array([18.0, 24, 22, 31, 30, 38, 41, 39, 47, 52, 51, 60].enumerated()), id: \.offset) { point in
                        AreaMark(x: .value("日期", point.offset), y: .value("示例资产", point.element)).foregroundStyle(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.01)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.catmullRom)
                        LineMark(x: .value("日期", point.offset), y: .value("示例资产", point.element)).foregroundStyle(accent).interpolationMethod(.catmullRom)
                    }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 96).clipped()
                }.appPadding(13).background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: MacUI.space(8)) {
                    Text("最近交易").appFont(.caption, weight: .semibold, design: .default)
                    previewRecord("餐饮", icon: "fork.knife", color: .orange, amount: "−123 " + MacSettingsVisual.symbol(currency))
                    Divider(); previewRecord("购物", icon: "bag", color: .orange, amount: "−1234 " + MacSettingsVisual.symbol(currency))
                    Divider(); previewRecord("住房", icon: "house.fill", color: .blue, amount: "−12345 " + MacSettingsVisual.symbol(currency))
                }.appPadding(13).background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 10))
            }.appPadding(12).frame(maxWidth: .infinity).background(MacOverviewStyle.canvas)
        }.fixedSize(horizontal: false, vertical: true).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.gray.opacity(0.1)))
    }
    private func previewRecord(_ title: String, icon: String, color: Color, amount: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { MacCategoryBadge(name: title, size: 25, filled: false); Text(title).appFont(.caption, weight: .medium); Spacer(minLength: 0) }
            HStack { Text(MacDateDisplay.string(Date())).foregroundStyle(.secondary); Spacer(minLength: 4); Text(amount).foregroundStyle(.red) }
                .appFont(.caption).lineLimit(1).minimumScaleFactor(0.6)
        }

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

private struct MacFontSizeInputRow: View {
    let title: String
    let detail: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let identifier: String
    @State private var draft = ""
    @FocusState private var editing: Bool
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) { Text(title).appFont(.body, weight: .medium); Text(detail).appFont(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 8)
            TextField("字号", text: $draft).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 66).focused($editing).onSubmit(commit).accessibilityIdentifier(identifier + "Input")
            Text("pt").foregroundStyle(.secondary)
            Stepper(title, value: Binding(get: { value }, set: { value = $0; draft = String($0) }), in: range).labelsHidden().accessibilityIdentifier(identifier + "Stepper")
        }.onAppear { draft = String(value) }.onChange(of: value) { _, next in draft = String(next) }.onChange(of: editing) { _, active in if !active { commit() } }
    }
    private func commit() { if let number = Int(draft) { value = min(range.upperBound, max(range.lowerBound, number)) }; draft = String(value) }
}
