import Foundation

/// Query-only draft. Calculated values never become editable text.
nonisolated struct MacFXConverterState {
    enum InputStatus: Equatable { case empty, editing, valid, invalid, overflow }
    private(set) var activeCode: String?
    private(set) var inputText = ""

    init(currency: String? = nil) { activeCode = currency }
    mutating func select(_ code: String) {
        guard activeCode != code else { return }
        activeCode = code
        inputText = ""
    }
    mutating func edit(_ text: String) { inputText = text }
    mutating func reconcile(_ codes: [String]) {
        guard let activeCode, codes.contains(activeCode) else {
            self.activeCode = codes.first
            inputText = ""
            return
        }
    }
    func parsed(locale: Locale = .current) -> (status: InputStatus, amount: Double?) {
        MacFXAmountDraft.parse(inputText, locale: locale)
    }
    func amount(defaultUnits: Int, locale: Locale = .current) -> Double? {
        let parsed = parsed(locale: locale)
        return parsed.status == .empty ? Double(defaultUnits == 100 ? 100 : 1) : parsed.amount
    }
    func result(_ code: String, quotes: [MacFXEvidenceQuote], units: Int, digits: Int, grouping: String = "comma") -> String? {
        guard let activeCode, let amount = amount(defaultUnits: units),
              let conversion = MacFXMath.resolve(from: activeCode, to: code, quotes: quotes),
              let value = try? conversion.amount(amount) else { return nil }
        return MacFXMath.formatted(value, digits: digits, grouping: grouping != "none", groupingSeparator: grouping == "space" ? " " : ",")
    }
    func failureText(_ code: String, quotes: [MacFXEvidenceQuote], units: Int) -> String {
        let status = parsed().status
        if status == .editing { return "等待输入" }
        if status == .invalid || status == .overflow { return "输入无效" }
        if let activeCode, let value = amount(defaultUnits: units), let route = MacFXMath.resolve(from: activeCode, to: code, quotes: quotes), (try? route.amount(value)) == nil { return "结果超出范围" }
        return "缺少报价"
    }
}

/// Tolerates editing states without normalizing the user's field in place.
nonisolated enum MacFXAmountDraft {
    static func parse(_ text: String, locale: Locale) -> (status: MacFXConverterState.InputStatus, amount: Double?) {
        var raw = text.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return (.empty, nil) }
        if [".", ",", "+", "+.", "+,"].contains(raw) { return (.editing, nil) }
        guard raw.count <= 128 else { return (.overflow, nil) }
        if raw.hasPrefix("+") { raw.removeFirst() }
        guard !raw.isEmpty, raw.allSatisfy({ "0123456789., '’".contains($0) }) else { return (.invalid, nil) }
        // Spaces/apostrophes are grouping separators, never ignored arbitrary text.
        if raw.contains(" ") || raw.contains("'") || raw.contains("’") {
            let pattern = #"^\d{1,3}(?:[ '’]\d{3})+(?:[.,]\d*)?$"#
            guard raw.range(of: pattern, options: .regularExpression) != nil else { return (.invalid, nil) }
            raw.removeAll { " '’".contains($0) }
        }
        let dots = raw.filter { $0 == "." }.count, commas = raw.filter { $0 == "," }.count
        if dots > 0 && commas > 0 {
            let decimal: Character = raw.lastIndex(of: ".")! > raw.lastIndex(of: ",")! ? "." : ","
            let grouping: Character = decimal == "." ? "," : "."
            let parts = raw.split(separator: decimal, omittingEmptySubsequences: false)
            guard parts.count == 2, groupedInteger(String(parts[0]), separator: grouping), parts[1].allSatisfy(\.isNumber) else { return (.invalid, nil) }
            raw = parts[0].filter { $0 != grouping } + "." + parts[1]
        } else if commas > 0 {
            if locale.decimalSeparator != ",", groupedInteger(raw, separator: ",") {
                raw.removeAll { $0 == "," }
            } else {
                guard commas == 1 else { return (.invalid, nil) }
                raw = raw.replacingOccurrences(of: ",", with: ".")
            }
        } else if dots > 1 {
            guard locale.decimalSeparator == ",", groupedInteger(raw, separator: ".") else { return (.invalid, nil) }
            raw.removeAll { $0 == "." }
        }
        guard raw.range(of: #"^(?:\d+(?:\.\d*)?|\.\d+)$"#, options: .regularExpression) != nil else { return (.invalid, nil) }
        guard let value = Double(raw), value.isFinite, value >= 0 else { return (.overflow, nil) }
        return (.valid, value)
    }
    private static func groupedInteger(_ raw: String, separator: Character) -> Bool {
        let groups = raw.split(separator: separator, omittingEmptySubsequences: false)
        return groups.count > 1 && (1...3).contains(groups[0].count) && groups[0].allSatisfy(\.isNumber)
            && groups.dropFirst().allSatisfy { $0.count == 3 && $0.allSatisfy(\.isNumber) }
    }
}

nonisolated enum MacFXCardMode: String { case history, converter }
