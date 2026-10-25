import SwiftUI
import AppKit

enum MacFontSizeTier: String, CaseIterable, Identifiable {
    static let preferenceKey = "v2_font_tier"
    static let legacyPreferenceKey = "v2_font_size"

    case small
    case standard
    case large

    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: "缩小"
        case .standard: "标准"
        case .large: "放大"
        }
    }
    var bodySize: CGFloat {
        switch self {
        case .small: 14
        case .standard: 16
        case .large: 18
        }
    }
    var captionSize: CGFloat {
        switch self {
        case .small: 10
        case .standard: 12
        case .large: 14
        }
    }
    var bodyAdjustment: CGFloat { bodySize - 16 }

    /// The former continuous scale used 13 for 100%. Map its nearest value
    /// to one of the new body-size tiers; all values around 13 remain standard.
    static func migratingLegacyValue(_ value: Double) -> Self {
        if value < 12.1875 { return .small }
        if value > 13.8125 { return .large }
        return .standard
    }
}

/// Shared Mac typography roles. Layout measurements stay in logical points.
enum MacUI {
    static var fontTier: MacFontSizeTier {
        MacFontSizeTier(rawValue: MacPreferences.defaults.string(forKey: MacFontSizeTier.preferenceKey) ?? "standard") ?? .standard
    }
    static func fontSize(_ role: TextRole, tier: MacFontSizeTier) -> CGFloat {
        role == .caption ? tier.captionSize : role.rawValue + tier.bodyAdjustment
    }
    static func space(_ value: CGFloat) -> CGFloat { value }
    static func filterColumnWidth(available: CGFloat, wide: Bool) -> CGFloat {
        let preferred: CGFloat = wide ? 205 : 185
        return min(preferred, max(145, available * 0.36))
    }
    enum TextRole: CGFloat { case caption = 12, label = 14, body = 16, section = 18, dialogTitle = 20, pageTitle = 24, amount = 28 }
    static var accent: Color { MacOverviewStyle.accent }
    static func dialogWidth(_ preferred: CGFloat, available: CGFloat) -> CGFloat {
        let base: CGFloat = preferred <= 480 ? 420 : preferred <= 650 ? 560 : 760
        return min(base, max(1, available - 40))
    }
    static func dialogHeight(available: CGFloat) -> CGFloat { max(1, min(available * 0.85, available - 48)) }
    static var available: CGSize {
        let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first {
            $0.isVisible && !$0.isSheet && $0.styleMask.contains(.titled)
        }
        return available(from: window)
    }
    static func available(from presentedWindow: NSWindow?) -> CGSize {
        let window = rootWindow(for: presentedWindow)
        let screen = window?.screen?.visibleFrame.size ?? NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
        let content = window?.contentLayoutRect.size ?? screen
        let width = content.width > 1 ? min(content.width, screen.width) : screen.width
        let height = content.height > 1 ? min(content.height, screen.height) : screen.height
        return CGSize(width: max(1, width), height: max(1, height))
    }
    static func rootWindow(for window: NSWindow?) -> NSWindow? {
        var result = window
        while let parent = result?.sheetParent { result = parent }
        return result
    }
}

/// Semantic appearance tokens shared by the overview, settings, and finance pages.
enum MacOverviewStyle {
    static var accent: Color { MacAccent.color(MacPreferences.defaults.string(forKey: "v2_accent") ?? "terracotta") }
    static let income = Color(red: 0.16, green: 0.60, blue: 0.39)
    static let expense = Color(red: 0.94, green: 0.36, blue: 0.29)
    static let palette: [Color] = [expense, .pink, income, .blue, .purple, .orange, .cyan, .gray]
    static var canvas: Color { adaptive(light: 0.965, dark: 0.105) }
    static var navigation: Color { adaptive(light: 0.927, dark: 0.135) }
    static var filters: Color { adaptive(light: 0.946, dark: 0.12) }
    static var card: Color { adaptive(light: 1, dark: 0.17) }
    private static func adaptive(light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: dark, alpha: 1) : NSColor(white: light, alpha: 1) })
    }
    static func money(_ amount: Double) -> String { MacDisplayPreferences.money(amount) }
    static func category(_ name: String) -> String { CategoryUsageHelper.localizedDisplayName(for: name) }
}

enum MacShapeTokens {
    static let filterRow: CGFloat = 8
    static let financeRow: CGFloat = 12
    static let financeCard: CGFloat = 14
    static let overviewCard: CGFloat = 15
}
private struct MacFontModifier: ViewModifier {
    @AppStorage(MacInterfaceFonts.preferenceKey, store: MacPreferences.defaults) private var selectedFontName = ""
    @AppStorage("v2_font_tier", store: MacPreferences.defaults) private var selectedTier = MacFontSizeTier.standard.rawValue
    var size: CGFloat
    var role: MacUI.TextRole?
    var weight: Font.Weight
    var design: Font.Design
    func body(content: Content) -> some View {
        let tier = MacFontSizeTier(rawValue: selectedTier) ?? .standard
        let renderedSize = role.map { MacUI.fontSize($0, tier: tier) } ?? size
        if role != nil, !selectedFontName.isEmpty, NSFont(name: selectedFontName, size: renderedSize) != nil {
            content.font(.custom(selectedFontName, fixedSize: renderedSize).weight(weight))
        } else { content.font(.system(size: renderedSize, weight: weight, design: design)) }
    }
}
private struct MacPaddingModifier: ViewModifier {
    var edges: Edge.Set; var value: CGFloat
    func body(content: Content) -> some View { content.padding(edges, value) }
}
private struct MacHeightModifier: ViewModifier {
    var height: CGFloat
    func body(content: Content) -> some View { content.frame(minHeight: height) }
}
extension View {
    func appFont(_ role: MacUI.TextRole, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(MacFontModifier(size: role.rawValue, role: role, weight: weight, design: design))
    }
    func appIconFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(MacFontModifier(size: size, role: nil, weight: weight, design: design))
    }
    func appPadding(_ value: CGFloat) -> some View { modifier(MacPaddingModifier(edges: .all, value: value)) }
    func appPadding(_ edges: Edge.Set, _ value: CGFloat) -> some View { modifier(MacPaddingModifier(edges: edges, value: value)) }
    func appMinHeight(_ height: CGFloat) -> some View { modifier(MacHeightModifier(height: height)) }
    func appFormControl() -> some View {
        appFont(.body).appPadding(.horizontal, 12).appMinHeight(40)
            .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.gray.opacity(0.2)))
    }
}
struct MacStandardButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.appFont(.body, weight: .semibold).appPadding(.horizontal, 20).appMinHeight(40)
            .foregroundStyle(primary ? .white : .primary)
            .background(primary ? MacUI.accent : MacOverviewStyle.filters, in: RoundedRectangle(cornerRadius: 9))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Shared hover and selection treatment for large clickable surfaces.
private struct MacHoverSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat
    var selected: Bool
    var selectedFillOpacity: Double
    var selectedBorderOpacity: Double
    var hoverBorderOpacity: Double
    var idleBorderOpacity: Double
    var idleShadowOpacity: Double
    var hoverShadowOpacity: Double
    @State private var hovered = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        content
            .background(selected ? MacOverviewStyle.accent.opacity(selectedFillOpacity) : MacOverviewStyle.card, in: shape)
            .overlay(shape.strokeBorder(
                selected ? MacOverviewStyle.accent.opacity(selectedBorderOpacity) :
                    (hovered ? MacOverviewStyle.accent.opacity(hoverBorderOpacity) : .primary.opacity(idleBorderOpacity))
            ))
            .shadow(color: .black.opacity(hovered ? hoverShadowOpacity : idleShadowOpacity), radius: hovered ? 8 : 5, y: 3)
            .contentShape(shape)
            .onHover { hovered = $0 }
    }
}

/// Shared filter row treatment used by the finance list pages.
private struct MacFinanceFilterRowModifier: ViewModifier {
    var selected: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: MacShapeTokens.filterRow)
        content
            .background(selected ? MacOverviewStyle.accent.opacity(0.13) : .clear, in: shape)
            .foregroundStyle(selected ? MacOverviewStyle.accent : .primary)
            .contentShape(Rectangle())
    }
}

/// Shared detail-card treatment for deposits, recurring items, and loans.
private struct MacFinanceCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: MacShapeTokens.financeCard)
        content
            .background(MacOverviewStyle.card, in: shape)
            .overlay(shape.strokeBorder(.primary.opacity(0.035)))
    }
}

extension View {
    func macFinanceSelectableRow(selected: Bool) -> some View {
        modifier(MacHoverSurfaceModifier(cornerRadius: MacShapeTokens.financeRow, selected: selected,
            selectedFillOpacity: 0.08, selectedBorderOpacity: 0.45, hoverBorderOpacity: 0.24,
            idleBorderOpacity: 0.04, idleShadowOpacity: 0, hoverShadowOpacity: 0.035))
    }

    func macHoverCardSurface() -> some View {
        modifier(MacHoverSurfaceModifier(cornerRadius: MacShapeTokens.overviewCard, selected: false,
            selectedFillOpacity: 0, selectedBorderOpacity: 0.4, hoverBorderOpacity: 0.4,
            idleBorderOpacity: 0.035, idleShadowOpacity: 0.015, hoverShadowOpacity: 0.045))
    }

    func macFinanceFilterRow(selected: Bool) -> some View {
        modifier(MacFinanceFilterRowModifier(selected: selected))
    }

    func macFinanceDetailCard() -> some View {
        modifier(MacFinanceCardModifier())
    }
}

struct MacLabeledFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(6)) {
            configuration.textFieldStyle(.plain).appFormControl()
        }
    }
}
private struct MacShellMeasurements: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
private extension View {
    func shellMeasure(_ key: String) -> some View {
        background(GeometryReader { geometry in Color.clear.preference(key: MacShellMeasurements.self, value: [key: geometry.size.height]) })
    }
}
private struct MacWindowAvailabilityReader: NSViewRepresentable {
    var onChange: (CGSize) -> Void

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.onChange = onChange
        return probe
    }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.onChange = onChange
        probe.observeWindow()
    }

    static func dismantleNSView(_ probe: Probe, coordinator: ()) {
        probe.stopObserving()
    }

    final class Probe: NSView {
        var onChange: ((CGSize) -> Void)?
        private weak var observedWindow: NSWindow?
        private var resizeObserver: NSObjectProtocol?
        private var screenObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observeWindow()
        }

        func observeWindow() {
            let window = MacUI.rootWindow(for: self.window)
            guard window !== observedWindow else { reportSize(); return }
            stopObserving()
            observedWindow = window
            if let window {
                resizeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification, object: window, queue: .main
                ) { [weak self] _ in self?.reportSize() }
                screenObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeScreenNotification, object: window, queue: .main
                ) { [weak self] _ in self?.reportSize() }
            }
            reportSize()
        }

        func stopObserving() {
            if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
            if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
            resizeObserver = nil
            screenObserver = nil
            observedWindow = nil
        }

        private func reportSize() {
            let size = MacUI.available(from: observedWindow)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.onChange?(size)
            }
        }

        deinit { stopObserving() }
    }
}
/// Intrinsic content height with a shared viewport cap; only the form body scrolls.
struct MacFormShell<Header: View, Fields: View, Footer: View>: View {
    var width: CGFloat = 560
    @ViewBuilder var header: Header
    @ViewBuilder var fields: Fields
    @ViewBuilder var footer: Footer
    @State private var measurements: [String: CGFloat] = [:]
    @State private var available = MacUI.available
    var body: some View {
        let padding: CGFloat = 20, gap: CGFloat = 16
        let maximum = MacUI.dialogHeight(available: available.height)
        let reserved = (measurements["header"] ?? 56) + (measurements["footer"] ?? 44) + 2 * padding + 2 * gap
        let bodyHeight = min(measurements["fields"] ?? 280, max(40, maximum - reserved))
        VStack(alignment: .leading, spacing: gap) {
            header.fixedSize(horizontal: false, vertical: true).shellMeasure("header")
            ScrollView {
                fields.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    .padding(2).shellMeasure("fields")
            }.frame(height: bodyHeight).accessibilityIdentifier("formFieldsScroll")
            footer.fixedSize(horizontal: false, vertical: true).shellMeasure("footer")
        }.padding(padding).frame(width: MacUI.dialogWidth(width, available: available.width))
            .background(MacOverviewStyle.card).appFont(.body).tint(MacUI.accent).controlSize(.regular).buttonStyle(MacStandardButtonStyle())
            .overlay(alignment: .topLeading) {
                MacWindowAvailabilityReader { size in if available != size { available = size } }
                    .frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)
            }
            .onPreferenceChange(MacShellMeasurements.self) { if $0 != measurements { measurements = $0 } }
    }
}
/// Compact confirmations and secondary editors use the same bounded, intrinsic sizing.
private struct MacDialogModifier: ViewModifier {
    var width: CGFloat
    @State private var height: CGFloat = 200
    @State private var available = MacUI.available
    func body(content: Content) -> some View {
        ScrollView {
            content.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).shellMeasure("dialog")
        }.frame(width: MacUI.dialogWidth(width, available: available.width), height: min(height, MacUI.dialogHeight(available: available.height)))
            .background(MacOverviewStyle.card).appFont(.body).tint(MacUI.accent).buttonStyle(MacStandardButtonStyle())
            .overlay(alignment: .topLeading) {
                MacWindowAvailabilityReader { size in if available != size { available = size } }
                    .frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)
            }
            .onPreferenceChange(MacShellMeasurements.self) { if let value = $0["dialog"], abs(height - value) > 0.5 { height = value } }
    }
}
extension View { func appDialog(width: CGFloat) -> some View { modifier(MacDialogModifier(width: width)) } }

struct MacFormTextField: View {
    var title: LocalizedStringKey
    @Binding var text: String
    init(_ title: LocalizedStringKey, text: Binding<String>) { self.title = title; _text = text }
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(6)) {
            Text(title).appFont(.body, weight: .medium).foregroundStyle(.secondary)
            TextField(title, text: $text).textFieldStyle(.plain).appFormControl()
        }
    }
}
private struct MacPanelModifier: ViewModifier {
    var width: CGFloat; var height: CGFloat
    @State private var available = MacUI.available
    func body(content: Content) -> some View {
        content.frame(width: MacUI.dialogWidth(width, available: available.width), height: min(height, MacUI.dialogHeight(available: available.height)))
            .background(MacOverviewStyle.card).appFont(.body).tint(MacUI.accent).buttonStyle(MacStandardButtonStyle())
            .overlay(alignment: .topLeading) {
                MacWindowAvailabilityReader { size in if available != size { available = size } }
                    .frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)
            }
    }
}
extension View { func appPanel(width: CGFloat, height: CGFloat) -> some View { modifier(MacPanelModifier(width: width, height: height)) } }

/// Keeps related cards equally tall and selects one row only when every
/// card's natural content width fits. Long amounts therefore change the axis.
struct MacAdaptiveEqualCardLayout: Layout {
    var spacing: CGFloat = 14
    var minimumCardWidth: CGFloat = 230
    private func metrics(_ width: CGFloat?, subviews: Subviews) -> (width: CGFloat, cardWidth: CGFloat, height: CGFloat, horizontal: Bool) {
        let count = max(1, subviews.count)
        let ideal = max(minimumCardWidth, subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0)
        let required = ideal * CGFloat(count) + spacing * CGFloat(count - 1)
        let available = max(1, width ?? required)
        let horizontal = available >= required
        let cardWidth = horizontal ? (available - spacing * CGFloat(count - 1)) / CGFloat(count) : available
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: cardWidth, height: nil)).height }.max() ?? 0
        return (available, cardWidth, height, horizontal)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let m = metrics(proposal.width, subviews: subviews)
        return CGSize(width: m.width, height: m.horizontal ? m.height : m.height * CGFloat(subviews.count) + spacing * CGFloat(max(0, subviews.count - 1)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let m = metrics(bounds.width, subviews: subviews)
        for (index, view) in subviews.enumerated() {
            let x = bounds.minX + (m.horizontal ? CGFloat(index) * (m.cardWidth + spacing) : 0)
            let y = bounds.minY + (m.horizontal ? 0 : CGFloat(index) * (m.height + spacing))
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: m.cardWidth, height: m.height))
        }
    }
}

/// Fits short detail cards beside one another, with equal heights within a row.
/// A narrow column stacks cards at their own natural heights.
struct MacFinanceCardRow: Layout {
    var spacing: CGFloat = 14
    var minimumWidth: CGFloat = 540
    var firstFraction: CGFloat = 0.5
    private func sizes(_ width: CGFloat, subviews: Subviews) -> [CGSize] {
        let horizontal = width >= minimumWidth && subviews.count == 2
        return subviews.enumerated().map { index, view in
            let w = horizontal ? (width - spacing) * (index == 0 ? firstFraction : 1 - firstFraction) : width
            return CGSize(width: w, height: view.sizeThatFits(.init(width: w, height: nil)).height)
        }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minimumWidth, values = sizes(width, subviews: subviews)
        return CGSize(width: width, height: width >= minimumWidth && values.count == 2 ? values.map(\.height).max() ?? 0 : values.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, values.count - 1)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let values = sizes(bounds.width, subviews: subviews), horizontal = bounds.width >= minimumWidth && subviews.count == 2
        let height = values.map(\.height).max() ?? 0
        var x = bounds.minX, y = bounds.minY
        for (index, view) in subviews.enumerated() {
            let size = values[index]
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .init(width: size.width, height: horizontal ? height : size.height))
            if horizontal { x += size.width + spacing } else { y += size.height + spacing }
        }
    }
}

/// Common feedback for lightweight controls, including previously plain buttons.
struct MacInteractiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background((hovered || configuration.isPressed) && enabled ? Color.primary.opacity(configuration.isPressed ? 0.09 : 0.035) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .scaleEffect(configuration.isPressed && !reduceMotion && enabled ? 0.985 : 1)
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovered = $0 }
    }
}
private struct MacHelpModifier: ViewModifier {
    var text: Text
    @AppStorage("v141_show_help", store: MacPreferences.defaults) private var enabled = true
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.help(text) } else { content }
    }
}
extension View {
    func appHelp(_ text: String) -> some View { modifier(MacHelpModifier(text: Text(text))) }
    func appHelp(_ text: Text) -> some View { modifier(MacHelpModifier(text: text)) }
}
