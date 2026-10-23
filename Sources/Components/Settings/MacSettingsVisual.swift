import SwiftUI
import AppKit
import Charts


/// Native, reusable controls measured from the selected settings references.
enum MacSettingsVisual {
    static let previewRates: [String: Double] = ["USD":1, "RUB":92.35, "CNY":7.25, "EUR":0.92, "GBP":0.78, "JPY":151.3, "CHF":0.88, "HKD":7.81]
    static var accent: Color { MacAccent.color(MacPreferences.defaults.string(forKey: "v2_accent") ?? "red") }
    static var bodySize: CGFloat { MacUI.fontTier.bodySize }
    static var preview: Bool { MacPreferences.isTesting && ProcessInfo.processInfo.environment["FINTRACK_V2_SETTINGS_VISUAL"] == "1" }
    static var rowHeight: CGFloat { MacPreferences.defaults.string(forKey: "v2_density") == "compact" ? 42 : MacPreferences.defaults.string(forKey: "v2_density") == "spacious" ? 58 : 49 }
    static func headerColor(_ title: String) -> Color {
        if title.contains("日期") || title.contains("危险") || title.contains("主题") { return .red }
        if title.contains("金额") || title.contains("导出") || title.contains("版本") { return .orange }
        if title.contains("提醒") || title.contains("恢复") || title.contains("行为") { return .purple }
        if title.contains("记录") || title.contains("反馈") { return .green }
        if title.contains("存储") { return .gray }
        return .blue
    }
    static func currencyName(_ code: String) -> String {
        ["USD":"美元", "RUB":"俄罗斯卢布", "CNY":"人民币", "EUR":"欧元", "GBP":"英镑", "JPY":"日元", "CHF":"瑞士法郎", "HKD":"港币"][code] ?? code
    }
    static func currencyLabel(_ raw: String) -> String {
        let code = raw.uppercased()
        let region = ["EUR":"EU","USD":"US","GBP":"GB"][code] ?? String(code.prefix(2))
        let isRegion = Locale.commonISOCurrencyCodes.contains(code) && (region == "EU" || Locale.Region.isoRegions.contains { $0.identifier == region })
        let flag = isRegion ? String(String.UnicodeScalarView(region.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) })) : "🌐"
        return flag + " " + code
    }

    static func money(_ amount: Double) -> String { amount.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US"))) }
    static func symbol(_ currency: String) -> String {
        if let symbol = ["USD":"$", "RUB":"₽", "CNY":"¥", "EUR":"€", "GBP":"£", "JPY":"¥", "HKD":"HK$", "CHF":"CHF", "CAD":"CA$", "AUD":"A$", "SGD":"S$", "TRY":"₺", "INR":"₹", "KRW":"₩"][currency] { return symbol }
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency; formatter.currencyCode = currency
        return formatter.currencySymbol ?? currency
    }
}

struct MacSettingsIcon: View {
    var symbol: String
    var color: Color = .blue
    var size: CGFloat = 42
    var body: some View {
        MacSettingsSymbol(symbol: symbol, size: size * 0.5)
            .foregroundStyle(color).frame(width: MacUI.space(size), height: MacUI.space(size))
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
    }
}

enum MacPresentationOptions {
    static let icons: [(String, String)] = [
        ("target", "目标"), ("house.fill", "住房"), ("graduationcap.fill", "教育"), ("airplane", "旅行"),
        ("car.fill", "车辆"), ("heart.fill", "健康"), ("suitcase.fill", "储蓄"), ("cross.case.fill", "医疗"),
        ("banknote.fill", "现金"), ("chart.line.uptrend.xyaxis", "增长"), ("gift.fill", "礼物"), ("leaf.fill", "生活"),
        ("cart.fill", "购物"), ("fork.knife", "餐饮"), ("cup.and.saucer.fill", "咖啡"), ("basket.fill", "日用"),
        ("building.columns.fill", "银行"), ("creditcard.fill", "信用卡"), ("wallet.bifold.fill", "钱包"), ("chart.pie.fill", "预算"),
        ("bicycle", "骑行"), ("tram.fill", "通勤"), ("fuelpump.fill", "燃油"), ("bolt.fill", "能源"),
        ("gamecontroller.fill", "娱乐"), ("book.fill", "阅读"), ("laptopcomputer", "数码"), ("camera.fill", "摄影"),
        ("pawprint.fill", "宠物"), ("figure.2.and.child.holdinghands", "家庭"), ("wrench.and.screwdriver.fill", "维修"),
        ("sportscourt.fill", "运动"), ("music.note", "音乐"), ("tshirt.fill", "服饰"), ("shield.fill", "保障"), ("palm.tree.fill", "度假")
    ]
    static func validColor(_ value: String) -> Bool {
        ["red", "orange", "yellow", "green", "blue", "purple", "pink", "terracotta"].contains(value) ||
            value.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil
    }
}

struct MacSymbolColorPicker: View {
    @Binding var icon: String
    @Binding var color: String
    var title: String
    var identifierPrefix: String
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(9)) {
            Text(title + "图标").appFont(.body).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 38, maximum: 46), spacing: 6)], spacing: 6) {
                    ForEach(MacPresentationOptions.icons, id: \.0) { symbol, name in
                        Button { icon = symbol } label: {
                            MacSettingsIcon(symbol: symbol, color: MacAccent.color(color), size: 36)
                                .frame(maxWidth: .infinity).contentShape(Rectangle())
                                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(icon == symbol ? MacAccent.color(color) : .clear, lineWidth: 2))
                        }.buttonStyle(.plain).help(name).accessibilityLabel(title + "图标：" + name)
                            .accessibilityValue(icon == symbol ? "已选择" : "未选择")
                            .accessibilityIdentifier(identifierPrefix + "-" + symbol)
                    }
                }.padding(2)
            }.frame(height: 146)
            Text(title + "颜色").appFont(.body).foregroundStyle(.secondary)
            MacColorChoices(selection: $color, identifierPrefix: identifierPrefix + "Color")
        }.accessibilityIdentifier(identifierPrefix)
    }
}

struct MacGoalIconPicker: View {
    @Binding var presentation: MacGoalPresentation
    var identifierPrefix = "goalIconOption"
    var body: some View {
        MacSymbolColorPicker(icon: $presentation.icon, color: $presentation.color, title: "目标", identifierPrefix: identifierPrefix)
    }
}

/// The selected travel pictogram is absent from this macOS SF Symbols catalog.
/// Draw that glyph locally and provide a visible fallback for older systems.
struct MacSettingsSymbol: View {
    var symbol: String
    var size: CGFloat
    var body: some View {
        Group {
            if MacCategoryEmoji.isValid(symbol) {
                Text(symbol).appIconFont(size, weight: .regular, design: .default)
            } else if symbol == "github.mark" {
                Image(systemName: "link").appIconFont(size, weight: .medium, design: .default)
                    .accessibilityLabel("GitHub")
            } else if symbol == "palm.tree.fill" {
                MacPalmTreeGlyph().fill().frame(width: MacUI.space(size), height: MacUI.space(size))
            } else {
                Image(systemName: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil ? "tag" : symbol)
                    .appIconFont(size, weight: .medium, design: .default)
            }
        }
    }
}
private struct MacPalmTreeGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 11, y: 9))
        path.addQuadCurve(to: CGPoint(x: 8, y: 23), control: CGPoint(x: 12, y: 16))
        path.addLine(to: CGPoint(x: 14, y: 23))
        path.addQuadCurve(to: CGPoint(x: 13, y: 9), control: CGPoint(x: 12, y: 17))
        path.closeSubpath()
        for points: [CGPoint] in [
            [.init(x: 12, y: 9), .init(x: 2, y: 0), .init(x: 0, y: 9), .init(x: 7, y: 5)],
            [.init(x: 12, y: 9), .init(x: 8, y: -2), .init(x: 17, y: 2), .init(x: 12, y: 3)],
            [.init(x: 12, y: 9), .init(x: 23, y: -1), .init(x: 24, y: 9), .init(x: 18, y: 5)],
            [.init(x: 12, y: 9), .init(x: 22, y: 6), .init(x: 23, y: 16), .init(x: 18, y: 11)],
            [.init(x: 12, y: 9), .init(x: 3, y: 5), .init(x: 1, y: 16), .init(x: 6, y: 11)]
        ] {
            path.move(to: points[0]); path.addQuadCurve(to: points[2], control: points[1])
            path.addQuadCurve(to: points[0], control: points[3]); path.closeSubpath()
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}
struct MacSettingsButtonStyle: ButtonStyle {
    var primary = false
    var height: CGFloat = 34
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let destructive = configuration.role == .destructive
        configuration.label.appFont(.body, weight: .semibold, design: .default)
            .foregroundStyle(primary ? .white : destructive ? .red : .primary)
            .appPadding(.horizontal, 13).frame(minHeight: MacUI.space(height))
            .background(primary ? MacUI.accent : destructive ? Color.red.opacity(0.035) : MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(destructive ? .red.opacity(0.2) : .gray.opacity(0.18)))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
    }
}
struct MacSettingsFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain).appFont(.body, weight: .regular, design: .default).appPadding(.horizontal, 12).appMinHeight(40)
            .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.2)))
    }
}
/// Multiline notes reserve their own height instead of inheriting the 36pt field.
struct MacSettingsNoteField: View {
    var placeholder: String
    @Binding var text: String
    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain).appFont(.body, weight: .regular, design: .default)
            .lineLimit(3...4).appPadding(.horizontal, 12).appPadding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: MacUI.space(78), alignment: .topLeading)
            .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.2)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
struct MacSettingsRow<Content: View>: View {
    var label: String
    var labelWidth: CGFloat = 128
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: MacUI.space(14)) {
            Text(label).appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary).lineLimit(1).frame(width: MacUI.space(labelWidth), alignment: .leading)
            content.frame(maxWidth: .infinity, alignment: .trailing)
        }.appMinHeight(40).frame(maxWidth: .infinity, alignment: .leading)
    }
}
private final class MacSettingsPopupCoordinator: NSObject {
    var onSelection: ((Int) -> Void)?
    var titles: [String] = []
    var values: [AnyHashable] = []
    @objc func didSelect(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem, commit = onSelection
        DispatchQueue.main.async { commit?(index) }
    }
}

/// Draw the whole native hit area as one field, matching currency/date controls.
private final class MacSettingsPopUp: NSPopUpButton {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill(); path.fill()
        NSColor.gray.withAlphaComponent(0.2).setStroke(); path.lineWidth = 1; path.stroke()
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 16),
            .foregroundColor: isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor, .paragraphStyle: paragraph]
        let text = titleOfSelectedItem ?? "请选择"
        let height = (text as NSString).size(withAttributes: attributes).height
        (text as NSString).draw(in: NSRect(x: 12, y: (bounds.height - height) / 2, width: max(0, bounds.width - 43), height: height), withAttributes: attributes)
        if let image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) {
            let glyph = image.withSymbolConfiguration(.init(paletteColors: [isEnabled ? NSColor.secondaryLabelColor : NSColor.disabledControlTextColor])) ?? image
            glyph.draw(in: NSRect(x: bounds.width - 25, y: (bounds.height - 12) / 2, width: 12, height: 12))
        }
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 7, yRadius: 7)
            ring.lineWidth = 2; ring.stroke()
        }
    }
}

private struct MacSettingsPopupButton<Value: Hashable>: NSViewRepresentable {
    @Binding var selection: Value
    var options: [(String, Value)]
    @Environment(\.isEnabled) private var isEnabled
    @AppStorage("v2_font_tier",store:MacPreferences.defaults) private var tier = "standard"

    func makeCoordinator() -> MacSettingsPopupCoordinator { MacSettingsPopupCoordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = MacSettingsPopUp(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(MacSettingsPopupCoordinator.didSelect(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        button.isEnabled = isEnabled
        let titles = options.map { $0.0 }, values = options.map { AnyHashable($0.1) }
        if context.coordinator.titles != titles || context.coordinator.values != values {
            button.removeAllItems()
            for (index, option) in options.enumerated() {
                button.addItem(withTitle: option.0)
                button.item(at: index)?.tag = index
            }
            context.coordinator.titles = titles; context.coordinator.values = values
        }
        if let index = options.firstIndex(where: { $0.1 == selection }) { button.selectItem(at: index) }
        let size = MacUI.fontSize(.body,tier:MacFontSizeTier(rawValue:tier) ?? .standard)
        let font = NSFont.systemFont(ofSize:size,weight:.medium), menuFont = NSFont.systemFont(ofSize:size,weight:.regular)
        if button.font != font { button.font = font }
        if button.menu?.font != menuFont { button.menu?.font = menuFont }
        button.cell?.alignment = .left
        button.needsDisplay = true
        button.target = context.coordinator
        button.action = #selector(MacSettingsPopupCoordinator.didSelect(_:))
        context.coordinator.onSelection = { index in
            guard options.indices.contains(index) else { return }
            selection = options[index].1
        }
    }
}

struct MacSettingsMenu<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(String, Value)]
    var minimumWidth: CGFloat = 0
    private var selectedTitle: String { options.first { $0.1 == selection }?.0 ?? "请选择" }
    var body: some View {
        MacSettingsPopupButton(selection: $selection, options: options)
            .frame(minWidth: MacUI.space(minimumWidth), maxWidth: .infinity)
            .frame(height: MacUI.space(40))
            .accessibilityLabel(selectedTitle)
            .accessibilityValue(selectedTitle)
    }
}
struct MacSettingsToggleRow: View {
    var title: String
    var subtitle: String = ""
    var icon: String? = nil
    var color: Color = .purple
    @Binding var value: Bool
    var body: some View {
        HStack(spacing: MacUI.space(12)) {
            if let icon { MacSettingsIcon(symbol: icon, color: color, size: 31) }
            VStack(alignment: .leading, spacing: MacUI.space(4)) {
                Text(title).appFont(.body, weight: .medium, design: .default)
                if !subtitle.isEmpty { Text(subtitle).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: $value).labelsHidden().toggleStyle(.switch).tint(.blue).accessibilityIdentifier("settingsToggle-" + title)
        }.frame(minHeight: MacUI.space(39))
    }
}
struct MacSettingsSegments: View {
    @Binding var selection: String
    var options: [String]
    var minimumOptionWidth: CGFloat = 0
    var body: some View {
        HStack(spacing: MacUI.space(3)) {
            ForEach(options, id: \.self) { title in
                Button { selection = title } label: {
                    Text(title).appFont(.body, weight: .semibold, design: .default).lineLimit(1)
                        .frame(minWidth: MacUI.space(minimumOptionWidth), maxWidth: .infinity).appMinHeight(40)
                        .foregroundStyle(selection == title ? MacSettingsVisual.accent : .secondary)
                        .background(selection == title ? MacSettingsVisual.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).accessibilityIdentifier("settingsSegment-" + title)
                    .accessibilityValue(selection == title ? "已选中" : "未选中")
            }
        }.appPadding(3).background(.gray.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
    }
}
struct MacSettingsProgress: View {
    var value: Double
    var color: Color = .green
    var height: CGFloat = 9
    var body: some View {
        GeometryReader { geo in
            Capsule().fill(.gray.opacity(0.15))
                .overlay(alignment: .leading) { Capsule().fill(color).frame(width: geo.size.width * min(1, max(0, value))) }
        }.frame(height: height).accessibilityValue(value.formatted(.percent))
    }
}
struct MacCurrencyFlag: View {
    var code: String
    var width: CGFloat = 30
    var body: some View {
        Image(nsImage:MacCurrencyGlyph.image(code)).resizable().scaledToFit()
            .frame(width: MacUI.space(width), height: MacUI.space(width * 0.7)).clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.gray.opacity(0.12))).accessibilityLabel(MacSettingsVisual.currencyName(code))
    }
}
struct MacColorChoices: View {
    @Binding var selection: String
    var identifierPrefix = "accent"
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: MacUI.space(34)))], spacing: MacUI.space(8)) {
            ForEach(["red", "orange", "yellow", "green", "blue", "purple", "pink"], id: \.self) { name in
                Button { selection = name } label: {
                    Circle().fill(MacAccent.color(name)).frame(width: MacUI.space(25), height: MacUI.space(25)).appPadding(4)
                        .overlay(Circle().strokeBorder(selection == name ? MacAccent.color(name) : .clear, lineWidth: 2))
                }.buttonStyle(.plain).contentShape(Rectangle()).accessibilityLabel("选择" + name + "色").accessibilityIdentifier(identifierPrefix + "-" + name).accessibilityValue(selection == name ? "已选中" : "未选中")
            }
            ColorPicker("自定义", selection: Binding(get: { MacAccent.color(selection) }, set: { selection = MacAccent.hex($0) }), supportsOpacity: false).labelsHidden().help("自定义颜色")
        }
    }
}

/// Shared calendar grid for transaction, settings and overview date popovers.
struct MacCalendarPickerPopover: View {
    var title: String
    @Binding var selection: Date
    var pickerIdentifier: String
    var width: CGFloat = 330
    var doneIdentifier: String? = nil
    var onDone: (() -> Void)? = nil
    var precision: TargetDatePrecision = .day
    @AppStorage("v2_font_tier", store: MacPreferences.defaults) private var fontTierValue = MacFontSizeTier.standard.rawValue
    @AppStorage("v2_week_start", store: MacPreferences.defaults) private var weekStart = 2
    @State private var displayedMonth = Date()
    @FocusState private var focusedCellIdentifier: String?

    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = weekStart == 1 ? 1 : 2
        return value
    }
    private var monthStart: Date { startOfMonth(containing: displayedMonth) }
    private var periodTitle: String {
        let year = calendar.component(.year, from: monthStart)
        if precision == .year { return "\((year / 12) * 12) — \((year / 12) * 12 + 11) 年" }
        return precision == .month ? "\(year) 年" : MacDisplayPreferences.month(monthStart)
    }
    private var previousTitle: String { precision == .day ? "上个月" : precision == .month ? "上一年" : "上一组年份" }
    private var nextTitle: String { precision == .day ? "下个月" : precision == .month ? "下一年" : "下一组年份" }
    private var weekdayLabels: [String] {
        let labels = ["日", "一", "二", "三", "四", "五", "六"]
        let offset = max(0, min(6, calendar.firstWeekday - 1))
        return (0..<7).map { labels[($0 + offset) % 7] }
    }
    private var displayedDays: [Date] {
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7
        guard let firstCell = calendar.date(byAdding: .day, value: -offset, to: monthStart) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: firstCell) }
    }

    var body: some View {
        let tier = MacFontSizeTier(rawValue: fontTierValue) ?? .standard
        VStack(alignment: .leading, spacing: MacUI.space(10)) {
            HStack {
                Text(title).appFont(.body, weight: .semibold)
                    .accessibilityIdentifier("calendarPopoverTitle")
                Spacer(minLength: 8)
                if let onDone {
                    Button("完成", action: onDone)
                        .buttonStyle(.plain)
                        .keyboardShortcut(.defaultAction)
                        .appFont(.body, weight: .semibold)
                        .accessibilityIdentifier(doneIdentifier ?? "calendarPopoverDone")
                }
            }
            HStack(spacing: 4) {
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).help(previousTitle).accessibilityLabel(previousTitle).accessibilityIdentifier("calendarPreviousMonth")
                Spacer(minLength: 0)
                Text(periodTitle).appFont(.body, weight: .semibold)
                    .accessibilityIdentifier("calendarDisplayedMonth")
                Spacer(minLength: 0)
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain).help(nextTitle).accessibilityLabel(nextTitle).accessibilityIdentifier("calendarNextMonth")
            }
            Group {
                if precision == .day {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            ForEach(weekdayLabels.indices, id: \.self) { index in
                                Text(weekdayLabels[index]).appFont(.caption, weight: .semibold)
                                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 22)
                                    .accessibilityIdentifier("calendarWeekday-\(index)")
                            }
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                            ForEach(displayedDays, id: \.self) { day in dayButton(day, tier: tier) }
                        }
                    }
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(0..<12, id: \.self) { index in periodButton(index) }
                    }
                }
            }
            Button(precision == .day ? "今天" : precision == .month ? "本月" : "今年") {
                let now = Date()
                let delta = calendar.dateComponents([.day], from: calendar.startOfDay(for: selection), to: calendar.startOfDay(for: now)).day ?? 0
                if let value = calendar.date(byAdding: .day, value: delta, to: selection) { selection = value }
            }.buttonStyle(.plain).foregroundStyle(MacUI.accent).accessibilityIdentifier("calendarToday")
        }
        .appPadding(14)
        .frame(width: width)
        .background(MacOverviewStyle.card)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(pickerIdentifier)
        .onExitCommand { onDone?() }
        .onMoveCommand { direction in
            let stride = precision == .day ? 7 : 3
            let offset: Int
            switch direction { case .left: offset = -1; case .right: offset = 1; case .up: offset = -stride; case .down: offset = stride; default: return }
            let component: Calendar.Component = precision == .day ? .day : precision == .month ? .month : .year
            if let value = calendar.date(byAdding: component, value: offset, to: selection) { selection = value }
        }
        .onAppear {
            displayedMonth = startOfMonth(containing: selection)
            DispatchQueue.main.async { focusedCellIdentifier = cellIdentifier(selection) }
        }
        .onChange(of: selection) { _, value in
            let newMonth = startOfMonth(containing: value)
            if !calendar.isDate(newMonth, equalTo: monthStart, toGranularity: .month) { displayedMonth = newMonth }
            DispatchQueue.main.async {
                if selection == value { focusedCellIdentifier = cellIdentifier(value) }
            }
        }
    }

    private func moveMonth(_ offset: Int) {
        if let month = calendar.date(byAdding: precision == .day ? .month : .year, value: precision == .year ? offset * 12 : offset, to: monthStart) {
            displayedMonth = startOfMonth(containing: month)
        }
    }

    private func periodButton(_ index: Int) -> some View {
        let year = calendar.component(.year, from: displayedMonth)
        let value = precision == .month ? index + 1 : (year / 12) * 12 + index
        let label = "\(value)" + (precision == .month ? " 月" : " 年")
        let selected = precision == .month
            ? calendar.component(.year, from: selection) == year && calendar.component(.month, from: selection) == value
            : calendar.component(.year, from: selection) == value
        return Button {
            var parts = calendar.dateComponents([.era, .hour, .minute, .second, .nanosecond], from: selection)
            parts.year = precision == .month ? year : value
            parts.month = precision == .month ? value : 1; parts.day = 1
            if let date = calendar.date(from: parts) { selection = date }
        } label: {
            Text(label).appFont(.body, weight: selected ? .semibold : .regular)
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? MacUI.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).focusable()
            .focused($focusedCellIdentifier, equals: precision == .month ? "calendarMonth-\(value)" : "calendarYear-\(value)")
            .disabled(precision == .year && !(1...9999).contains(value)).accessibilityLabel(label)
            .accessibilityValue(selected ? "已选择" : "")
            .accessibilityIdentifier(precision == .month ? "calendarMonth-\(value)" : "calendarYear-\(value)")
    }

    private func startOfMonth(containing date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.era, .year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    private func cellIdentifier(_ date: Date) -> String {
        switch precision {
        case .day: return dayIdentifier(date)
        case .month: return "calendarMonth-\(calendar.component(.month, from: date))"
        case .year: return "calendarYear-\(calendar.component(.year, from: date))"
        }
    }

    private func dayIdentifier(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "calendarDay-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private func dayButton(_ date: Date, tier: MacFontSizeTier) -> some View {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let day = components.day ?? 1
        let identifier = dayIdentifier(date)
        let selected = calendar.isDate(date, inSameDayAs: selection)
        let inDisplayedMonth = calendar.isDate(date, equalTo: monthStart, toGranularity: .month)
        let weekday = calendar.component(.weekday, from: date)
        let weekdayName = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"][weekday - 1]
        let label = "\(components.year ?? 0)年\(components.month ?? 0)月\(day)日 \(weekdayName)"
        return Button {
            let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: selection)
            var chosen = calendar.dateComponents([.era, .year, .month, .day], from: date)
            chosen.hour = time.hour; chosen.minute = time.minute; chosen.second = time.second; chosen.nanosecond = time.nanosecond
            selection = calendar.date(from: chosen) ?? date
            displayedMonth = startOfMonth(containing: date)
            focusedCellIdentifier = identifier
        } label: {
            Text(String(day))
                .font(.system(size: MacUI.fontSize(.body, tier: tier), weight: selected ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.white : inDisplayedMonth ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(selected ? MacUI.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(calendar.isDateInToday(date) && !selected ? MacUI.accent.opacity(0.6) : .clear))
        .help(calendar.isDateInToday(date) ? "今天 · " + label : label)
        .buttonStyle(.plain).focusable()
        .focused($focusedCellIdentifier, equals: identifier)
        .accessibilityLabel(label)
        .accessibilityValue(selected ? "已选择" : inDisplayedMonth ? "" : "其他月份")
        .accessibilityIdentifier(identifier)
    }
}

struct MacSettingsDateButton: View {
    @Binding var date: Date
    var monthOnly = false
    var identifier: String? = nil
    var precision: TargetDatePrecision? = nil
    private var effectivePrecision: TargetDatePrecision { precision ?? (monthOnly ? .month : .day) }
    @State private var showing = false
    @FocusState private var dateButtonFocused: Bool
    var body: some View {
        Button { showing = true } label: { HStack { Text(effectivePrecision == .day ? MacDateDisplay.string(date) : MacGoalTargetDate.label(GoalTargetTime(date: date, precision: effectivePrecision))); Spacer(); Image(systemName: "chevron.down").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }.appFont(.body, weight: .medium, design: .default).appPadding(.horizontal, 12).appMinHeight(40).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.2))).contentShape(Rectangle()) }
            .buttonStyle(.plain).focusable().focused($dateButtonFocused)
            .accessibilityIdentifier(identifier ?? (monthOnly ? "settingsMonthDateButton" : "settingsDateButton"))
            .accessibilityValue(showing ? "已展开" : "已折叠")
            .popover(isPresented: $showing) {
                MacCalendarPickerPopover(
                    title: effectivePrecision == .year ? "选择年份" : effectivePrecision == .month ? "选择月份" : "选择日期",
                    selection: $date,
                    pickerIdentifier: "settingsDatePicker",
                    doneIdentifier: "settingsDateDone",
                    onDone: { showing = false },
                    precision: effectivePrecision
                )
            }
            .onChange(of: showing) { _, isPresented in
                guard !isPresented else { return }
                DispatchQueue.main.async { dateButtonFocused = true }
            }
    }
}

/// Selection is a draft; only the separate conversion action changes ledger data.
struct MacBookCurrencyChoice: View {
    @Binding var currency: String
    @AppStorage("v2_currencies") private var currencyBytes = Data()
    @State private var custom = false
    private var codes: [String] {
        let saved = (try? JSONDecoder().decode([String].self, from: currencyBytes)) ?? []
        return Array(Set(saved)).sorted()
    }
    var body: some View {
        MacEditableCurrencyMenu(currency:$currency,custom:$custom,codes:codes,identifier:"bookCurrencyChoiceMenu",textIdentifier:"bookCurrencyCustomCode")
    }
}


struct MacDateTimeField: View {
    var title: String
    @Binding var date: Date
    var includesTime = false
    var identifier: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).appFont(.caption, weight: .medium).foregroundStyle(.secondary)
            MacSettingsDateButton(date: $date, identifier: identifier)
            if includesTime { DatePicker("时间", selection: $date, displayedComponents: .hourAndMinute).labelsHidden() }
        }
    }
}

struct MacGoalTargetTimeField: View {
    @Binding var hasDate: Bool
    @Binding var precision: TargetDatePrecision
    @Binding var date: Date
    var identifier = "goalTargetTime"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("期望时间精度", selection: Binding(get: { hasDate ? precision.rawValue : "none" }, set: { value in
                hasDate = value != "none"
                if let selected = TargetDatePrecision(rawValue: value) { precision = selected }
            })) {
                Text("无").tag("none")
                ForEach(TargetDatePrecision.allCases, id: \.self) { value in Text(value.title).tag(value.rawValue) }
            }.accessibilityIdentifier(identifier + "Precision")
            if hasDate { MacSettingsDateButton(date: $date, identifier: identifier + "Date", precision: precision) }
            Text("期望时间用于规划，超过时间不会使目标失败。").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
        }
    }
}
