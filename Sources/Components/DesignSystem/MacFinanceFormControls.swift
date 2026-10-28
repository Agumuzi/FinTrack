import SwiftUI
import AppKit
import SwiftData

/// The binding stays ungrouped; native editing displays separators without rounding.
enum MacNumberInput {
    static func minimumEditingWidth(large:Bool = false)->CGFloat {max(160,MacUI.fontTier.bodySize*(large ? 10:8))}
    nonisolated static func raw(_ display: String, grouping: String) -> String {
        let separator = grouping == "space" ? " " : ","
        guard display.contains(separator), grouping != "none" else { return display }
        let escaped = NSRegularExpression.escapedPattern(for: separator)
        guard display.range(of: "^[0-9]{1,3}(" + escaped + "[0-9]{3})+(\\.[0-9]*)?$", options: .regularExpression) != nil else { return display }
        return display.replacingOccurrences(of: separator, with: "")
    }
    nonisolated static func display(_ raw: String, grouping: String) -> String {
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
    var accessibilityTitle: String? = nil
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
    @AppStorage(MacCustomTypography.bodyKey, store: MacPreferences.defaults) private var bodyPoints = 16
    @Environment(\.isEnabled) private var enabled
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MacNumericInput
        var editing = false
        var observedText = ""
        init(_ parent: MacNumericInput) { self.parent = parent }
        var lastDisplay = ""
        private var separator: String { parent.grouping == "space" ? " " : "," }
        private func logicalOffset(_ string: String, _ position: Int) -> Int {
            String(string.prefix(max(0, position))).filter { String($0) != separator }.count
        }
        private func displayOffset(_ string: String, _ logical: Int) -> Int {
            guard logical > 0 else { return 0 }
            var digits = 0
            for (index, char) in string.enumerated() {
                if String(char) != separator { digits += 1 }
                if digits == logical { return index + 1 }
            }
            return string.utf16.count
        }
        private func render(_ display: String, in field: NSTextField) {
            let editor = field.currentEditor() as? NSTextView
            let old = field.stringValue
            let selection = editor?.selectedRange() ?? NSRange(location: old.utf16.count, length: 0)
            let start = logicalOffset(old, selection.location)
            let end = logicalOffset(old, NSMaxRange(selection))
            if old != display { field.stringValue = display }
            if let editor {
                let a = displayOffset(display, start), b = displayOffset(display, end)
                editor.setSelectedRange(NSRange(location: a, length: max(0, b - a)))
            }
            lastDisplay = display
        }
        func externalUpdate(_ field: NSTextField) {
            observedText = parent.text
            render(parent.rate ? MacNumberInput.rate(parent.text) : MacNumberInput.display(parent.text, grouping: parent.grouping), in: field)
        }
        func prepareFocus(_ field:NSTextField) {
            editing=true;parent.focus?.wrappedValue=true
            externalUpdate(field)
        }
        func controlTextDidBeginEditing(_ notification: Notification) {
            // AppKit has already captured paste/undo replacement ranges here.
            // Reformatting now can shorten the string beneath those ranges.
            editing = true; parent.focus?.wrappedValue = true
            observedText = parent.text
        }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let value = field.stringValue
            if parent.rate { parent.text = value; observedText = value; lastDisplay = value; return }
            if (field.currentEditor() as? NSTextView)?.hasMarkedText() == true { return }
            // A one-character edit may temporarily break a group, for example
            // 1,000 -> 1,0000. Validate its digits, then rebuild the separators.
            let old = Array(lastDisplay), new = Array(value)
            var prefix = 0, suffix = 0
            while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
            while suffix < min(old.count, new.count) - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
            let ordinaryEdit = max(old.count - prefix - suffix, new.count - prefix - suffix) <= 1
            let grouped = parent.grouping != "none" && value.contains(separator)
            let raw = grouped ? value.replacingOccurrences(of: separator, with: "") : value
            guard raw.range(of: #"^[0-9]*(\.[0-9]*)?$"#, options: .regularExpression) != nil,
                  !grouped || ordinaryEdit || MacNumberInput.raw(value, grouping: parent.grouping) != value else {
                render(lastDisplay, in: field); NSSound.beep(); return
            }
            parent.text = raw; observedText = raw
            if field.formatter == nil {render(MacNumberInput.display(raw,grouping:parent.grouping),in:field)}
            else {lastDisplay=value}
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !parent.rate, parent.grouping != "none", textView.selectedRange().length == 0 else { return false }
            let selection = textView.selectedRange(), value = textView.string as NSString
            let backwards = commandSelector == #selector(NSResponder.deleteBackward(_:))
            let forwards = commandSelector == #selector(NSResponder.deleteForward(_:))
            let index = backwards ? selection.location - 1 : selection.location
            guard (backwards || forwards), index >= 0, index < value.length,
                  value.substring(with: NSRange(location: index, length: 1)) == separator else { return false }
            let start = backwards ? max(0, index - 1) : index
            let count = min(2, value.length - start)
            textView.insertText("", replacementRange: NSRange(location: start, length: count))
            return true
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
        let field = MacNumericTextField()
        field.onFocus = { [weak field,weak coordinator=context.coordinator] in
            if let field {coordinator?.prepareFocus(field)}
        }
        field.isBordered = false; field.drawsBackground = false
        field.focusRingType = .none; field.delegate = context.coordinator; field.target = context.coordinator; field.action = #selector(Coordinator.submitField(_:))
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if rate {field.formatter=nil}
        else if (field.formatter as? MacAmountEditingFormatter)?.grouping != grouping {field.formatter=MacAmountEditingFormatter(grouping:grouping)}
        let coordinator = context.coordinator
        if !coordinator.editing {
            let value = presented(text, editing: false)
            if field.stringValue != value { field.stringValue = value }
        } else if text != coordinator.observedText {
            // External changes (for example inferred interest) may update a field;
            // a redraw must not rewrite an unchanged in-progress keystroke.
            coordinator.externalUpdate(field)
        }
        field.font = MacInterfaceFonts.font(size: MacUI.fontSize(large ? .amount : .body, tier: MacFontSizeTier(rawValue: tier) ?? .standard), monospacedDigits: true)
        field.textColor = .labelColor; field.isEnabled = enabled
        field.setAccessibilityIdentifier(identifier); field.setAccessibilityLabel(accessibilityTitle ?? (rate ? "利率" : "金额"))
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
            MacNumericInput(text: $text, rate: rate, identifier: identifier, digits: title.contains("汇率") ? 6 : nil, accessibilityTitle: title).frame(minHeight: 24).appFormControl()
        }
    }
}

struct MacFinanceCategoryField: View {
    @Environment(\.modelContext) private var context
    @Binding var category: String
    var type: String
    var identifier: String
    @Query private var categories: [Category]
    @State private var usage = MacCategoryUsageSnapshot()
    @AppStorage("v2_category_styles", store: MacPreferences.defaults) private var revision = Data()
    var body: some View {
        let _ = revision
        let styles: [String: MacCategoryStyle] = MacSettingsStore.load("v2_category_styles", fallback: [:])
        let rows = usage.sorted(categories.filter { $0.deletedAt == nil && $0.type == type })
        let names = rows.map(\.name) + (category.isEmpty || rows.contains { $0.name == category } ? [] : [category])
        MacEntryField(title: "分类") {
            MacIconMenu(selection: $category, options: names.map { name in
                let style = MacCategoryCatalog.style(name: name, type: type, in: styles)
                return MacIconMenuOption(title: MacOverviewStyle.category(name), value: name, image: MacCategoryCatalog.menuImage(style: style, name: name))
            }, identifier: identifier, accessibilityTitle: "分类", width: 250)
            if names.isEmpty { Text("请先在分类管理中添加分类").appFont(.caption).foregroundStyle(.secondary) }
        }
        .onAppear { usage = (try? MacCategoryUsageSnapshot.load(in: context)) ?? .init() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in usage = (try? MacCategoryUsageSnapshot.load(in: context)) ?? .init() }
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

/// Format before any native text replacement captures its selection range.
private final class MacNumericTextField:NSTextField {
    var onFocus:(() -> Void)?
    override func becomeFirstResponder() -> Bool {
        let accepted=super.becomeFirstResponder()
        if accepted {onFocus?()}
        return accepted
    }
}
