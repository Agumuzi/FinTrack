import SwiftUI
import AppKit
import Charts


/// Native, reusable controls measured from the selected settings references.
enum MacSettingsVisual {
    static let previewRates: [String: Double] = ["USD":1, "RUB":92.35, "CNY":7.25, "EUR":0.92, "GBP":0.78, "JPY":151.3, "CHF":0.88, "HKD":7.81]
    static var accent: Color { MacAccent.color(MacPreferences.defaults.string(forKey: "v2_accent") ?? "terracotta") }
    static var bodySize: CGFloat { MacUI.fontTier.bodySize }
    static var preview: Bool { MacPreferences.isTesting && ProcessInfo.processInfo.environment["FINTRACK_V2_SETTINGS_VISUAL"] == "1" }
    static var rowHeight: CGFloat { MacPreferences.defaults.string(forKey: "v2_density") == "compact" ? 42 : MacPreferences.defaults.string(forKey: "v2_density") == "spacious" ? 58 : 49 }
    static func headerColor(for icon: String) -> Color {
        switch icon {
        case "calendar", "exclamationmark.triangle", "paintpalette": .red
        case "banknote", "square.and.arrow.up", "info.circle": .orange
        case "bell", "arrow.counterclockwise", "gearshape": .purple
        case "clock.arrow.circlepath", "bubble.left": .green
        case "externaldrive": .gray
        default: .blue
        }
    }
    static func currencyName(_ code: String) -> String {
        L10n.locale.localizedString(forCurrencyCode: code) ?? code
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
    static let legacyIcons: [(String, String)] = [
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
    static let groups: [(String, [(String, String)])] = [
        ("通用", [("target", "目标"), ("tag", "标签"), ("star.fill", "收藏"), ("flag.fill", "标记"), ("checkmark.seal.fill", "完成"), ("shield.fill", "保障")]),
        ("住房家庭", [("house.fill", "住房"), ("sofa.fill", "家具"), ("lightbulb.fill", "照明"), ("pawprint.fill", "宠物"), ("figure.2.and.child.holdinghands", "家庭"), ("wrench.and.screwdriver.fill", "维修")]),
        ("交通旅行", [("car.fill", "车辆"), ("airplane", "旅行"), ("bicycle", "骑行"), ("tram.fill", "通勤"), ("fuelpump.fill", "燃油"), ("palm.tree.fill", "度假"), ("suitcase.fill", "行李"), ("map.fill", "地图")]),
        ("餐饮购物", [("fork.knife", "餐饮"), ("cup.and.saucer.fill", "咖啡"), ("cart.fill", "购物"), ("basket.fill", "日用"), ("bag.fill", "购物袋"), ("birthday.cake.fill", "生日"), ("gift.fill", "礼物"), ("tshirt.fill", "服饰")]),
        ("健康教育", [("heart.fill", "健康"), ("cross.case.fill", "医疗"), ("pills.fill", "药品"), ("book.fill", "阅读"), ("graduationcap.fill", "教育"), ("sportscourt.fill", "运动")]),
        ("金融工作", [("banknote.fill", "现金"), ("building.columns.fill", "银行"), ("creditcard.fill", "信用卡"), ("wallet.bifold.fill", "钱包"), ("chart.pie.fill", "预算"), ("chart.line.uptrend.xyaxis", "增长"), ("briefcase.fill", "工作"), ("doc.text.fill", "文件")]),
        ("数码娱乐", [("laptopcomputer", "数码"), ("camera.fill", "摄影"), ("gamecontroller.fill", "游戏"), ("music.note", "音乐"), ("tv.fill", "电视"), ("wifi", "通讯"), ("bolt.fill", "能源")]),
        ("日常生活", [("drop.fill", "用水"), ("flame.fill", "燃气"), ("sun.max.fill", "日间"), ("moon.fill", "夜间"), ("umbrella.fill", "雨具"), ("bed.double.fill", "住宿"), ("washer.fill", "洗衣"), ("refrigerator.fill", "家电"), ("key.fill", "钥匙"), ("lock.fill", "安全"), ("scissors", "理发"), ("eyeglasses", "眼镜")]),
        ("账单服务", [("receipt.fill", "票据"), ("doc.text.fill", "账单"), ("calendar", "日历"), ("clock.fill", "周期"), ("bell.fill", "提醒"), ("phone.fill", "电话"), ("envelope.fill", "邮件"), ("shippingbox.fill", "快递"), ("printer.fill", "打印"), ("network", "网络"), ("antenna.radiowaves.left.and.right", "通信"), ("checkmark.circle.fill", "已结清")]),
        ("资产规划", [("dollarsign.circle.fill", "美元"), ("yensign.circle.fill", "人民币"), ("eurosign.circle.fill", "欧元"), ("sterlingsign.circle.fill", "英镑"), ("rublesign.circle.fill", "卢布"), ("percent", "利率"), ("chart.bar.fill", "统计"), ("chart.xyaxis.line", "走势"), ("arrow.triangle.2.circlepath", "循环"), ("arrow.left.arrow.right", "转账"), ("building.2.fill", "房产"), ("archivebox.fill", "储备")]),
        ("个人工作", [("person.fill", "个人"), ("person.2.fill", "共同"), ("person.3.fill", "团队"), ("folder.fill", "项目"), ("pencil", "记录"), ("paperclip", "附件"), ("hammer.fill", "工具"), ("paintbrush.fill", "设计"), ("stethoscope", "诊疗"), ("figure.walk", "步行"), ("figure.run", "跑步"), ("ticket.fill", "票务")])
    ]
    static let icons: [(String, String)] = {
        var seen = Set<String>()
        return (legacyIcons + groups.flatMap { $0.1 }).filter { seen.insert($0.0).inserted }
    }()
    static let palette = ["red", "orange", "yellow", "green", "blue", "purple", "pink", "terracotta", "#30B0C7", "#00A896", "#5856D6", "#8E8E93", "#A2845E", "#34495E", "#C27BA0", "#7CB342"]
    static func validColor(_ value: String) -> Bool {
        ["red", "orange", "yellow", "green", "blue", "purple", "pink", "terracotta"].contains(value) ||
            value.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil
    }
}

struct MacSymbolColorPicker: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @Binding var icon: String
    @Binding var color: String
    var title: String
    var identifierPrefix: String
    @State private var choosingIcon = false
    var body: some View {
        HStack(spacing: 10) {
            Text(L10n.text("mac.settingsVisual.body.0d720eeea2")).appFont(.body).foregroundStyle(.secondary).fixedSize()
            Button { choosingIcon = true } label: {
                HStack(spacing: 8) {
                    MacSettingsIcon(symbol: icon, color: MacAccent.color(color), size: 30)
                    Text(MacPresentationOptions.icons.first { $0.0 == icon }.map { L10n.builtIn($0.1) } ?? L10n.text("mac.settingsVisual.body.6d8adad124")).appFont(.body).lineLimit(1)
                    Image(systemName: "chevron.right").appFont(.caption).foregroundStyle(.secondary)
                }.padding(8).background(.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
            }.buttonStyle(MacInteractiveButtonStyle()).fixedSize(horizontal: true, vertical: false).accessibilityIdentifier(identifierPrefix + "Open")
            Spacer(minLength: 16)
            Text(L10n.text("mac.settingsVisual.body.070a8016fc")).appFont(.body).foregroundStyle(.secondary).fixedSize()
            MacColorChoices(selection: $color, identifierPrefix: identifierPrefix + "Color").fixedSize()
        }.accessibilityElement(children: .contain).accessibilityIdentifier(identifierPrefix)
            .sheet(isPresented: $choosingIcon) { MacIconLibraryChooser(icon: $icon, color: color, title: title, identifierPrefix: identifierPrefix) }
    }
}

struct MacGoalIconPicker: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @Binding var presentation: MacGoalPresentation
    var identifierPrefix = "goalIconOption"
    var body: some View {
        MacSymbolColorPicker(icon: $presentation.icon, color: $presentation.color, title: L10n.text("mac.settingsVisual.MacSymbolColorPicker.57060c88a3"), identifierPrefix: identifierPrefix)
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
                Image(systemName: "tag").appIconFont(size, weight: .medium, design: .default)
            } else if symbol == "github.mark" {
                Image("GitHubMark").resizable().renderingMode(.template).scaledToFit().frame(width: size, height: size)
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
            .foregroundStyle(primary ? MacAccent.primaryForeground : destructive ? .red : .primary)
            .lineLimit(1)
            .appPadding(.horizontal, 13).frame(minHeight: MacUI.space(height))
            .background(primary ? MacUI.accent : destructive ? Color.red.opacity(0.035) : MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(destructive ? .red.opacity(0.2) : .gray.opacity(0.18)))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
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
        MacSettingsRowLayout(labelWidth: MacUI.space(labelWidth), spacing: MacUI.space(14), minimumControl: MacUI.space(190)) {
                Text(label).appFont(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content.frame(maxWidth: .infinity, alignment: .leading)
        }.appMinHeight(40).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Every row uses the same columns at a given card width. Narrow cards stack;
/// neither a long translation nor an AppKit intrinsic size may escape its column.
private struct MacSettingsRowLayout: Layout {
    var labelWidth: CGFloat
    var spacing: CGFloat
    var minimumControl: CGFloat
    private func columns(_ width: CGFloat) -> (CGFloat, CGFloat)? {
        let label = max(labelWidth, width * 0.42)
        let control = width - label - spacing
        return control >= minimumControl ? (label, control) : nil
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = proposal.width ?? 480
        if let (label, control) = columns(width) {
            return CGSize(width: width, height: max(subviews[0].sizeThatFits(.init(width: label, height: nil)).height, subviews[1].sizeThatFits(.init(width: control, height: nil)).height))
        }
        return CGSize(width: width, height: subviews[0].sizeThatFits(.init(width: width, height: nil)).height + spacing + subviews[1].sizeThatFits(.init(width: width, height: nil)).height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        if let (label, control) = columns(bounds.width) {
            subviews[0].place(at: .init(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: .init(width: label, height: nil))
            subviews[1].place(at: .init(x: bounds.minX + label + spacing, y: bounds.midY), anchor: .leading, proposal: .init(width: control, height: nil))
        } else {
            let height = subviews[0].sizeThatFits(.init(width: bounds.width, height: nil)).height
            subviews[0].place(at: bounds.origin, proposal: .init(width: bounds.width, height: nil))
            subviews[1].place(at: .init(x: bounds.minX, y: bounds.minY + height + spacing), proposal: .init(width: bounds.width, height: nil))
        }
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
        let text = titleOfSelectedItem ?? L10n.text("mac.settingsVisual.text.da590a8fe3")
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
    @AppStorage(MacInterfaceFonts.preferenceKey, store: MacPreferences.defaults) private var interfaceFont = ""
        @AppStorage("v2_font_tier",store:MacPreferences.defaults) private var tier = "standard"

    func makeCoordinator() -> MacSettingsPopupCoordinator { MacSettingsPopupCoordinator() }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: max(40, proposal.height ?? 40))
    }

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

    @AppStorage(MacCustomTypography.bodyKey, store: MacPreferences.defaults) private var bodyPoints = 16
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let _ = bodyPoints
        button.isEnabled = isEnabled
        let titles = options.map { $0.0 }, values = options.map { AnyHashable($0.1) }
        if context.coordinator.titles != titles || context.coordinator.values != values {
            button.removeAllItems()
            if button.menu == nil { button.menu = NSMenu() }
            for (index, option) in options.enumerated() {
                // NSPopUpButton.addItem(withTitle:) merges duplicate titles.
                // Values remain distinct even when translated labels coincide.
                let item = NSMenuItem(title: option.0, action: nil, keyEquivalent: "")
                item.tag = index
                button.menu?.addItem(item)
            }
            context.coordinator.titles = titles; context.coordinator.values = values
        }
        if let index = options.firstIndex(where: { $0.1 == selection }) { button.selectItem(at: index) }
        let size = MacUI.fontSize(.body,tier:MacFontSizeTier(rawValue:tier) ?? .standard)
        let font = MacInterfaceFonts.font(size:size,weight:.medium), menuFont = MacInterfaceFonts.font(size:size,weight:.regular)
        if button.font != font { button.font = font }
        let scaledMenuFont = MacInterfaceFonts.font(size:size * MacInterfaceZoom.factor,weight:.regular)
        if button.menu?.font != scaledMenuFont { button.menu?.font = scaledMenuFont }
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
    @ObservedObject private var localizationState = LocalizationController.shared
    @AppStorage(MacInterfaceFonts.preferenceKey, store: MacPreferences.defaults) private var interfaceFont = ""
    @Binding var selection: Value
    var options: [(String, Value)]
    var minimumWidth: CGFloat = 0
    @AppStorage(MacCustomTypography.bodyKey, store: MacPreferences.defaults) private var bodyPoints = 16
    private var selectedTitle: String { options.first { $0.1 == selection }?.0 ?? L10n.text("mac.settingsVisual.selectedTitle.da590a8fe3") }
    var body: some View {
        MacSettingsPopupButton(selection: $selection, options: options)
            .frame(minWidth: MacUI.space(minimumWidth), maxWidth: .infinity)
            .frame(height: MacInterfaceFonts.controlHeight())
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
            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 12)
            Toggle(title, isOn: $value).labelsHidden().toggleStyle(.switch).tint(MacUI.accent).fixedSize().accessibilityIdentifier("settingsToggle-" + title)
        }.frame(minHeight: MacUI.space(39))
    }
}
struct MacSettingsSegments: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @Binding var selection: String
    var options: [String]
    var minimumOptionWidth: CGFloat = 0
    var body: some View {
        HStack(spacing: MacUI.space(3)) {
            ForEach(options, id: \.self) { title in
                Button { selection = title } label: {
                    Text(L10n.builtIn(title)).appFont(.body, weight: .semibold, design: .default).lineLimit(1)
                        .frame(minWidth: MacUI.space(minimumOptionWidth), maxWidth: .infinity).appMinHeight(40).contentShape(Rectangle())
                        .foregroundStyle(selection == title ? MacSettingsVisual.accent : .secondary)
                        .background(selection == title ? MacSettingsVisual.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("settingsSegment-" + title)
                    .accessibilityValue(selection == title ? L10n.text("mac.settingsVisual.ForEach.a737fd72b0") : L10n.text("mac.settingsVisual.ForEach.0e0c21de69"))
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
    @ObservedObject private var localizationState = LocalizationController.shared
    @Binding var selection: String
    var identifierPrefix = "accent"
    @State private var choosing = false
    var body: some View {
        Button { choosing = true } label: {
            HStack(spacing: 10) {
                Circle().fill(MacAccent.color(selection)).frame(width: 26, height: 26)
                Image(systemName: "chevron.right").appFont(.caption).foregroundStyle(.secondary)
            }.padding(8).background(.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
        }.buttonStyle(MacInteractiveButtonStyle()).accessibilityLabel(L10n.text("mac.settingsVisual.body.369b82fa07")).accessibilityIdentifier(identifierPrefix + "Open")
            .sheet(isPresented: $choosing) { MacColorLibraryChooser(selection: $selection, identifierPrefix: identifierPrefix) }
    }
}

struct MacColorSwatches: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @Binding var selection: String
    var identifierPrefix = "accent"
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: MacUI.space(34)))], spacing: MacUI.space(8)) {
            ForEach(MacPresentationOptions.palette, id: \.self) { name in
                Button { selection = name } label: {
                    Circle().fill(MacAccent.color(name)).frame(width: MacUI.space(25), height: MacUI.space(25)).appPadding(4)
                        .overlay(Circle().strokeBorder(selection == name ? MacAccent.color(name) : .clear, lineWidth: 2))
                }.buttonStyle(MacInteractiveButtonStyle()).contentShape(Rectangle()).accessibilityLabel(L10n.text("mac.settingsVisual.ForEach.c11330b852") + (["red":L10n.text("mac.settingsVisual.ForEach.0eb7ee7e38"), "orange":L10n.text("mac.settingsVisual.ForEach.1ad702b18a"), "yellow":L10n.text("mac.settingsVisual.ForEach.c732e4d7e3"), "green":L10n.text("mac.settingsVisual.ForEach.84b34ffba5"), "blue":L10n.text("mac.settingsVisual.ForEach.52f354ecfc"), "purple":L10n.text("mac.settingsVisual.ForEach.3d0158cb7c"), "pink":L10n.text("mac.settingsVisual.ForEach.d00069a5d3"), "terracotta":L10n.text("mac.settingsVisual.ForEach.0752623ccd")][name] ?? name) + L10n.text("mac.settingsVisual.ForEach.2b3611f71d")).accessibilityIdentifier(identifierPrefix + "-" + name).accessibilityValue(selection == name ? L10n.text("mac.settingsVisual.ForEach.a737fd72b0") : L10n.text("mac.settingsVisual.ForEach.0e0c21de69"))
            }
            ColorPicker(L10n.text("mac.settingsVisual.ColorPicker.4eafa9e925"), selection: Binding(get: { MacAccent.color(selection) }, set: { selection = MacAccent.hex($0) }), supportsOpacity: false).labelsHidden().appHelp(L10n.text("mac.settingsVisual.LazyVGrid.781b07fdcb"))
        }
    }
}

/// Shared calendar grid for transaction, settings and overview date popovers.
struct MacCalendarPickerPopover: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    var title: String
    @Binding var selection: Date
    var pickerIdentifier: String
    var width: CGFloat = 330
    var doneIdentifier: String? = nil
    var onDone: (() -> Void)? = nil
    var precision: TargetDatePrecision = .day
    @State private var navigation: TargetDatePrecision?
    @State private var hovered: String?
    private var navigationPrecision: TargetDatePrecision { navigation ?? precision }
    @AppStorage(MacInterfaceFonts.preferenceKey, store: MacPreferences.defaults) private var interfaceFont = ""
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
        if navigationPrecision == .year { return L10n.format("mac.settingsVisual.periodTitle.cd2bb9bd7d", "\((year / 12) * 12)", "\((year / 12) * 12 + 11)") }
        return navigationPrecision == .month ? L10n.format("mac.settingsVisual.periodTitle.604c261367", "\(year)") : MacDisplayPreferences.month(monthStart)
    }
    private var previousTitle: String { navigationPrecision == .day ? L10n.text("mac.settingsVisual.previousTitle.f9e7272234") : navigationPrecision == .month ? L10n.text("mac.settingsVisual.previousTitle.43cecd06c5") : L10n.text("mac.settingsVisual.previousTitle.818b8e0e29") }
    private var nextTitle: String { navigationPrecision == .day ? L10n.text("mac.settingsVisual.nextTitle.3e0b634699") : navigationPrecision == .month ? L10n.text("mac.settingsVisual.nextTitle.30fd49298c") : L10n.text("mac.settingsVisual.nextTitle.260526616c") }
    private var weekdayLabels: [String] {
        let formatter = DateFormatter(); formatter.locale = L10n.locale
        let labels = formatter.veryShortWeekdaySymbols!
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
                    Button(L10n.text("mac.settingsVisual.body.c0b3fbff51"), action: onDone)
                        .buttonStyle(MacInteractiveButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .appFont(.body, weight: .semibold)
                        .accessibilityIdentifier(doneIdentifier ?? "calendarPopoverDone")
                }
            }
            HStack(spacing: 4) {
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(MacInteractiveButtonStyle()).appHelp(previousTitle).accessibilityLabel(previousTitle).accessibilityIdentifier("calendarPreviousMonth")
                Spacer(minLength: 0)
                if navigationPrecision == .day {
                    HStack(spacing: 5) {
                        Button { navigation = .year } label: { Text(verbatim: String(calendar.component(.year, from: displayedMonth)) + " 年") }.accessibilityIdentifier("calendarChooseYear")
                        Button { navigation = .month } label: { Text(verbatim: String(calendar.component(.month, from: displayedMonth)) + " 月") }.accessibilityIdentifier("calendarChooseMonth")
                    }.buttonStyle(MacInteractiveButtonStyle()).appFont(.body, weight: .semibold).accessibilityElement(children: .contain).accessibilityIdentifier("calendarDisplayedMonth")
                } else {
                    Button(periodTitle) { navigation = navigationPrecision == .month ? .year : nil }.buttonStyle(MacInteractiveButtonStyle()).appFont(.body, weight: .semibold).accessibilityIdentifier("calendarDisplayedMonth")
                }
                Spacer(minLength: 0)
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(MacInteractiveButtonStyle()).appHelp(nextTitle).accessibilityLabel(nextTitle).accessibilityIdentifier("calendarNextMonth")
            }
            Group {
                if navigationPrecision == .day {
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
            Button(navigationPrecision == .day ? L10n.text("mac.settingsVisual.body.d5f5a7a010") : navigationPrecision == .month ? L10n.text("mac.settingsVisual.body.0eeecd26f2") : L10n.text("mac.settingsVisual.body.3a7ddf6c86")) {
                let now = Date()
                let delta = calendar.dateComponents([.day], from: calendar.startOfDay(for: selection), to: calendar.startOfDay(for: now)).day ?? 0
                if let value = calendar.date(byAdding: .day, value: delta, to: selection) { selection = value }
            }.buttonStyle(MacInteractiveButtonStyle()).foregroundStyle(MacUI.accent).accessibilityIdentifier("calendarToday")
        }
        .appPadding(14)
        .frame(width: width)
        .background(MacOverviewStyle.card)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(pickerIdentifier)
        .background(MacPopoverKeyboardActions(cancel: { onDone?() }, done: { onDone?() }).frame(width: 0, height: 0)).interfaceZoom()
        .onExitCommand { onDone?() }
        .onMoveCommand { direction in
            let stride = navigationPrecision == .day ? 7 : 3
            let offset: Int
            switch direction { case .left: offset = -1; case .right: offset = 1; case .up: offset = -stride; case .down: offset = stride; default: return }
            let component: Calendar.Component = navigationPrecision == .day ? .day : navigationPrecision == .month ? .month : .year
            if navigation != nil {
                if let value = calendar.date(byAdding: component, value: offset, to: displayedMonth) { displayedMonth = startOfMonth(containing: value) }
            } else if let value = calendar.date(byAdding: component, value: offset, to: selection) { selection = value }
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
        if let month = calendar.date(byAdding: navigationPrecision == .day ? .month : .year, value: navigationPrecision == .year ? offset * 12 : offset, to: monthStart) {
            displayedMonth = startOfMonth(containing: month)
        }
    }

    private func periodButton(_ index: Int) -> some View {
        let year = calendar.component(.year, from: displayedMonth)
        let value = navigationPrecision == .month ? index + 1 : (year / 12) * 12 + index
        let label = "\(value)" + (navigationPrecision == .month ? " 月" : " 年")
        let selected = navigationPrecision == .month
            ? calendar.component(.year, from: selection) == year && calendar.component(.month, from: selection) == value
            : calendar.component(.year, from: selection) == value
        return Button {
            if navigation != nil {
                var chosen = calendar.dateComponents([.year, .month], from: displayedMonth)
                if navigationPrecision == .year { chosen.year = value; navigation = precision == .day ? .month : nil }
                else { chosen.month = value; navigation = nil }
                chosen.day = 1
                displayedMonth = calendar.date(from: chosen) ?? displayedMonth
                return
            }
            var parts = calendar.dateComponents([.era, .hour, .minute, .second, .nanosecond], from: selection)
            parts.year = navigationPrecision == .month ? year : value
            parts.month = navigationPrecision == .month ? value : 1; parts.day = 1
            if let date = calendar.date(from: parts) { selection = date }
        } label: {
            Text(label).appFont(.body, weight: selected ? .semibold : .regular)
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? MacUI.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(MacInteractiveButtonStyle()).focusable().focusEffectDisabled()
            .focused($focusedCellIdentifier, equals: navigationPrecision == .month ? "calendarMonth-\(value)" : "calendarYear-\(value)")
            .disabled(navigationPrecision == .year && !(1...9999).contains(value)).accessibilityLabel(label)
            .accessibilityValue(selected ? L10n.text("mac.settingsVisual.periodButton.3f4ebc4aad") : "")
            .accessibilityIdentifier(navigationPrecision == .month ? "calendarMonth-\(value)" : "calendarYear-\(value)")
    }

    private func startOfMonth(containing date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.era, .year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    private func cellIdentifier(_ date: Date) -> String {
        switch navigationPrecision {
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
        let formatter = DateFormatter(); formatter.locale = L10n.locale
        let weekdayName = formatter.weekdaySymbols[weekday - 1]
        let label = L10n.format("mac.settingsVisual.label.52c3030da2", "\(components.year ?? 0)", "\(components.month ?? 0)", "\(day)", "\(weekdayName)")
        return Button {
            let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: selection)
            var chosen = calendar.dateComponents([.era, .year, .month, .day], from: date)
            chosen.hour = time.hour; chosen.minute = time.minute; chosen.second = time.second; chosen.nanosecond = time.nanosecond
            selection = calendar.date(from: chosen) ?? date
            displayedMonth = startOfMonth(containing: date)
            focusedCellIdentifier = identifier
        } label: {
            Text(String(day))
                .font(Font(MacInterfaceFonts.font(size: MacUI.fontSize(.body, tier: tier), weight: selected ? .semibold : .regular)))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.white : inDisplayedMonth ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(selected ? MacUI.accent : hovered == identifier ? MacUI.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(!selected && (calendar.isDateInToday(date) || focusedCellIdentifier == identifier) ? MacUI.accent.opacity(0.6) : .clear))
        .appHelp(calendar.isDateInToday(date) ? L10n.text("mac.settingsVisual.dayButton.13ecc2133a") + label : label)
        .buttonStyle(MacInteractiveButtonStyle()).focusable().focusEffectDisabled()
        .onHover { hovered = $0 ? identifier : nil }
        .focused($focusedCellIdentifier, equals: identifier)
        .accessibilityLabel(label)
        .accessibilityValue(selected ? L10n.text("mac.settingsVisual.dayButton.3f4ebc4aad") : inDisplayedMonth ? "" : L10n.text("mac.settingsVisual.dayButton.90892bd47e"))
        .accessibilityIdentifier(identifier)
    }
}

struct MacSettingsDateButton: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @Binding var date: Date
    var monthOnly = false
    var identifier: String? = nil
    var precision: TargetDatePrecision? = nil
    private var effectivePrecision: TargetDatePrecision { precision ?? (monthOnly ? .month : .day) }
    @State private var showing = false
    @FocusState private var dateButtonFocused: Bool
    var body: some View {
        Button { showing = true } label: { HStack { Text(effectivePrecision == .day ? MacDateDisplay.string(date) : MacGoalTargetDate.label(GoalTargetTime(date: date, precision: effectivePrecision))); Spacer(); Image(systemName: "chevron.down").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }.appFont(.body, weight: .medium, design: .default).appPadding(.horizontal, 12).appMinHeight(40).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.2))).contentShape(Rectangle()) }
            .buttonStyle(MacInteractiveButtonStyle()).focusable().focused($dateButtonFocused)
            .accessibilityIdentifier(identifier ?? (monthOnly ? "settingsMonthDateButton" : "settingsDateButton"))
            .accessibilityValue(showing ? L10n.text("mac.settingsVisual.body.df647b73b9") : L10n.text("mac.settingsVisual.body.ee60469308"))
            .popover(isPresented: $showing) {
                MacCalendarPickerPopover(
                    title: effectivePrecision == .year ? L10n.text("mac.settingsVisual.MacCalendarPickerPopover.22aa0abd89") : effectivePrecision == .month ? L10n.text("mac.settingsVisual.MacCalendarPickerPopover.17c701cc32") : L10n.text("mac.settingsVisual.MacCalendarPickerPopover.680c78ec60"),
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
    @ObservedObject private var localizationState = LocalizationController.shared
    var title: String
    @Binding var date: Date
    var includesTime = false
    var identifier: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).appFont(.caption, weight: .medium).foregroundStyle(.secondary)
            MacSettingsDateButton(date: $date, identifier: identifier)
            if includesTime { HStack { Text(L10n.text("mac.settingsVisual.body.8b6ff49851")).appFont(.caption).foregroundStyle(.secondary); Spacer(); MacTimeMenu(date: $date, identifier: (identifier ?? "date") + "Time").frame(width: 160) } }
        }
    }
}

struct MacGoalTargetTimeField: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @Binding var hasDate: Bool
    @Binding var precision: TargetDatePrecision
    @Binding var date: Date
    var identifier = "goalTargetTime"
    var includesAssets: Binding<Bool>? = nil
    @AppStorage(MacCustomTypography.bodyKey,store:MacPreferences.defaults) private var bodyPoints=16
    @AppStorage("v2_font_tier",store:MacPreferences.defaults) private var tier="standard"
    @AppStorage(MacInterfaceFonts.preferenceKey,store:MacPreferences.defaults) private var interfaceFont=""
    private var precisionOptions:[(String,String)] {[(L10n.text("mac.settingsVisual.precisionOptions.484d556139"),"none")]+TargetDatePrecision.allCases.map{($0.title,$0.rawValue)}}
    private var precisionWidth:CGFloat {
        let _=bodyPoints;let _=tier;let _=interfaceFont
        let font=MacInterfaceFonts.font(size:MacUI.fontTier.bodySize)
        return max(130,ceil(precisionOptions.map{($0.0 as NSString).size(withAttributes:[.font:font]).width}.max() ?? 0)+64)
    }
    private var precisionMenu:some View {
        MacSettingsMenu(selection:precisionBinding,options:precisionOptions).frame(width:precisionWidth).accessibilityIdentifier(identifier+"Precision")
    }
    private var precisionBinding: Binding<String> {
        Binding(get: { hasDate ? precision.rawValue : "none" }, set: { value in
            hasDate = value != "none"
            if let selected = TargetDatePrecision(rawValue: value) { precision = selected }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in:.horizontal) {
                HStack(spacing:12) {
                    if let includesAssets {Toggle(L10n.text("mac.settingsVisual.ViewThatFits.ec9f0e27f2"),isOn:includesAssets).toggleStyle(.switch).fixedSize()}
                    else {Text(L10n.text("mac.settingsVisual.ViewThatFits.02e4931415")).appFont(.body).foregroundStyle(.secondary).fixedSize()}
                    Spacer(minLength:12)
                    if includesAssets != nil {Text(L10n.text("mac.settingsVisual.ViewThatFits.bf2cb28701")).appFont(.caption).foregroundStyle(.secondary).fixedSize()}
                    precisionMenu
                }
                VStack(alignment:.leading,spacing:8) {
                    if let includesAssets {Toggle(L10n.text("mac.settingsVisual.ViewThatFits.ec9f0e27f2"),isOn:includesAssets).toggleStyle(.switch).fixedSize()}
                    Text(L10n.text("mac.settingsVisual.ViewThatFits.02e4931415")).appFont(.body).foregroundStyle(.secondary)
                    precisionMenu
                }
            }
            if hasDate { MacSettingsDateButton(date: $date, identifier: identifier + "Date", precision: precision) }
            Text(L10n.text("mac.settingsVisual.body.420ed568fe")).appFont(.caption).foregroundStyle(.secondary)
        }
    }
}
