import SwiftUI
import AppKit
import SwiftData

/// Keep the editing value ungrouped. Presentation never rounds a stored amount.
enum MacNumberInput {
    static func raw(_ display: String, grouping: String) -> String {
        let separator = grouping == "space" ? " " : ","
        guard display.contains(separator), grouping != "none" else { return display }
        let escaped = NSRegularExpression.escapedPattern(for: separator)
        guard display.range(of: "^[0-9]{1,3}(" + escaped + "[0-9]{3})+(\\.[0-9]*)?$", options: .regularExpression) != nil else { return display }
        return display.replacingOccurrences(of: separator, with: "")
    }
    static func display(_ raw: String, grouping: String) -> String {
        guard grouping != "none", raw.range(of: #"^[0-9]+(\.[0-9]*)?$"#, options: .regularExpression) != nil else { return raw }
        let pieces = raw.split(separator: ".", omittingEmptySubsequences: false)
        let digits = Array(String(pieces[0])), separator = grouping == "space" ? " " : ","
        let integer = digits.enumerated().map { index, digit in
            (index > 0 && (digits.count - index).isMultiple(of: 3) ? separator : "") + String(digit)
        }.joined()
        return integer + (pieces.count == 2 ? "." + pieces[1] : "")
    }
    static func rate(_ raw: String) -> String {
        guard var value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else { return raw }
        var rounded = Decimal(); NSDecimalRound(&rounded, &value, 2, .plain)
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.numberStyle = .decimal; formatter.usesGroupingSeparator = false; formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: rounded)) ?? raw
    }
}

struct MacNumericInput: NSViewRepresentable {
    @Binding var text: String
    var rate = false
    var identifier: String
    var focus: Binding<Bool>? = nil
    var submit: (() -> Void)? = nil
    var large = false
    var digits: Int? = nil
    @AppStorage("v2_decimals", store: MacPreferences.defaults) private var decimals = 2
    private func presented(_ raw: String, editing: Bool) -> String {
        if rate { return editing ? raw : MacNumberInput.rate(raw) }
        if !editing, let value = Double(raw), value.isFinite,
           digits != nil || raw.range(of: #"^[0-9]+(\.[0-9]*)?$"#, options: .regularExpression) != nil {
            return MacDisplayPreferences.money(value, decimals: digits ?? decimals, grouping: grouping, negative: "minus", zero: "number")
        }
        return MacNumberInput.display(raw, grouping: grouping)
    }
    @AppStorage("v2_grouping", store: MacPreferences.defaults) private var grouping = "comma"
    @AppStorage(MacInterfaceFonts.preferenceKey, store: MacPreferences.defaults) private var interfaceFont = ""
    @AppStorage("v2_font_tier", store: MacPreferences.defaults) private var tier = "standard"
    @Environment(\.isEnabled) private var enabled
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MacNumericInput
        var editing = false
        init(_ parent: MacNumericInput) { self.parent = parent }
        func controlTextDidBeginEditing(_ notification: Notification) {
            editing = true; parent.focus?.wrappedValue = true
            if let field = notification.object as? NSTextField { field.stringValue = parent.presented(parent.text, editing: true) }
        }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let value = field.stringValue
            let raw = parent.rate ? value : MacNumberInput.raw(value, grouping: parent.grouping)
            if !parent.rate && raw.contains(parent.grouping == "space" ? " " : ",") && parent.grouping != "none" {
                field.stringValue = MacNumberInput.display(parent.text, grouping: parent.grouping)
                NSSound.beep(); return
            }
            let editor = field.currentEditor() as? NSTextView
            let selection = editor?.selectedRange() ?? NSRange(location: value.utf16.count, length: 0)
            let prefix = String(value.prefix(min(selection.location, value.count)))
            let meaningful = prefix.filter { $0 != "," && $0 != " " }.count
            parent.text = raw
            let formatted = parent.rate ? raw : MacNumberInput.display(raw, grouping: parent.grouping)
            guard formatted != value else { return }
            field.stringValue = formatted
            var count = 0, position = 0
            for character in formatted {
                if count >= meaningful { break }
                position += String(character).utf16.count
                if character != "," && character != " " { count += 1 }
            }
            editor?.setSelectedRange(NSRange(location: position, length: 0))
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            editing = false; parent.focus?.wrappedValue = false
            guard let field = notification.object as? NSTextField else { return }
            field.stringValue = parent.presented(parent.text, editing: false)
        }
        @objc func submitField(_ field: NSTextField) {
            if let submit = parent.submit { submit() }
            else { field.window?.defaultButtonCell?.performClick(nil) }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(); field.isBordered = false; field.drawsBackground = false
        field.focusRingType = .none; field.delegate = context.coordinator; field.target = context.coordinator; field.action = #selector(Coordinator.submitField(_:))
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        let value = presented(text, editing: context.coordinator.editing)
        if field.stringValue != value { field.stringValue = value }
        field.font = MacInterfaceFonts.font(size: MacUI.fontSize(large ? .amount : .body, tier: MacFontSizeTier(rawValue: tier) ?? .standard), monospacedDigits: true)
        field.textColor = .labelColor; field.isEnabled = enabled
        field.setAccessibilityIdentifier(identifier); field.setAccessibilityLabel(identifier)
        if focus?.wrappedValue == true && !context.coordinator.editing {
            DispatchQueue.main.async { if self.focus?.wrappedValue == true, let window = field.window { window.makeFirstResponder(field) } }
        }
    }
}

struct MacFinanceNumberField: View {
    var title: String
    @Binding var text: String
    var rate = false
    var identifier: String
    var body: some View {
        MacEntryField(title: title) {
            MacNumericInput(text: $text, rate: rate, identifier: identifier, digits: title.contains("汇率") ? 6 : nil).frame(minHeight: 24).appFormControl()
        }
    }
}

struct MacFinanceCategoryField: View {
    @Binding var category: String
    var type: String
    var identifier: String
    @Query private var categories: [Category]
    @AppStorage("v2_category_styles", store: MacPreferences.defaults) private var revision = Data()
    var body: some View {
        let _ = revision
        let styles: [String: MacCategoryStyle] = MacSettingsStore.load("v2_category_styles", fallback: [:])
        let rows = categories.filter { $0.deletedAt == nil && $0.type == type }.sorted {
            let a = MacCategoryCatalog.style(name: $0.name, type: type, in: styles).order
            let b = MacCategoryCatalog.style(name: $1.name, type: type, in: styles).order
            return a == b ? $0.name < $1.name : a < b
        }
        let names = rows.map(\.name) + (category.isEmpty || rows.contains { $0.name == category } ? [] : [category])
        MacEntryField(title: "分类") {
            MacIconMenu(selection: $category, options: names.map { name in
                let style = MacCategoryCatalog.style(name: name, type: type, in: styles)
                return MacIconMenuOption(title: MacOverviewStyle.category(name), value: name, image: MacCategoryCatalog.menuImage(style: style, name: name))
            }, identifier: identifier, accessibilityTitle: "分类", width: 250)
            if names.isEmpty { Text("请先在分类管理中添加分类").appFont(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct MacReminderEditor: View {
    @Binding var enabled: Bool
    @Binding var days: Int
    @Binding var time: Date
    var showsToggle = true
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsToggle { Toggle("提醒", isOn: $enabled) }
            if enabled {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { daysField; Spacer(minLength: 16); timeField }
                    VStack(alignment: .leading, spacing: 10) { daysField; timeField }
                }
            }
        }
    }
    private var daysField: some View { Stepper("提前 \(days) 天", value: $days, in: 0...365).fixedSize() }
    private var timeField: some View { HStack(spacing: 10) { Text("提醒时间").appFont(.caption).foregroundStyle(.secondary); MacTimeMenu(date: $time, identifier: "financeReminderTime").frame(width: 140) } }
}
