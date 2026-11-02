import Foundation

nonisolated enum MacCSVKind: String, CaseIterable, Identifiable {
    case transactions, deposits, loans, recurring
    nonisolated var id: String { rawValue }
    var title: String {
        switch self { case .transactions: L10n.text("mac.cSVFormat.title.23b1604546"); case .deposits: L10n.text("mac.cSVFormat.title.759472586f"); case .loans: L10n.text("mac.cSVFormat.title.f87e87c10a"); case .recurring: L10n.text("mac.cSVFormat.title.c4b89bd158") }
    }
    var sectionTitle: String {
        switch self { case .transactions: "Transactions"; case .deposits: "Deposits"; case .loans: "Loans"; case .recurring: "Recurring Transactions" }
    }
    var sectionKey: String { sectionTitle.lowercased().filter { !$0.isWhitespace } }
    var headers: [String] {
        switch self {
        case .transactions: ["ID", "Date", "Type", "Category", "Currency", "Amount", "BaseCurrency", "ExchangeRate", "Note"]
        case .deposits: ["ID", "BankName", "Principal", "Currency", "BaseCurrency", "ExchangeRate", "AnnualInterestRate", "ExpectedInterest", "InterestExchangeRate", "StartDate", "MaturityDate", "InterestSettlementMode", "Note"]
        case .loans: ["ID", "Title", "Principal", "Currency", "BaseCurrency", "ExchangeRate", "AnnualRate", "TermMonths", "Method", "StartDate", "Category", "Note"]
        case .recurring: ["ID", "Title", "Type", "Category", "Currency", "Amount", "BaseCurrency", "ExchangeRate", "IntervalValue", "IntervalUnit", "NextExecutionDate", "EndDate", "Note"]
        }
    }
    var templateName: String { "FinTrack_\(rawValue)_Template_v1.csv" }
    var exportName: String { "FinTrack_\(rawValue)_Data.csv" }
    @MainActor func blankTemplate(bookCurrency: String) -> String {
        let marker = ["#FinTrackTemplate", "1", rawValue, bookCurrency] + Array(repeating: "", count: headers.count - 4)
        let instructions = ["#AIInstructions", MacCSVFormat.templateInstructions(kind: self, bookCurrency: bookCurrency)] + Array(repeating: "", count: headers.count - 2)
        return MacCSVFormat.csv(headers: marker, rows: [instructions, headers])
    }
}

/// Public contract for four independent Excel/AI tables; each file has exactly one purpose.
@MainActor
enum MacCSVFormat {
    static func escaped(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    static func csv(headers: [String], rows: [[String]]) -> String {
        "\u{FEFF}" + ([headers] + rows).map { $0.map(escaped).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
    static func templateInstructions(kind: MacCSVKind, bookCurrency: String) -> String {
        L10n.format("csv.template.instructions", kind.title, kind.title, bookCurrency, kind.headers.joined(separator: ","), commonInstructions(bookCurrency: bookCurrency), kind.title, L10n.text("csv.guide.\(kind.rawValue).rules"), exampleInstructions(kind: kind, bookCurrency: bookCurrency), kind.title)
    }
    private static func commonInstructions(bookCurrency: String) -> String {
        L10n.format("csv.guide.common", bookCurrency)
    }
    private static func exampleInstructions(kind: MacCSVKind, bookCurrency: String) -> String {
        let key = "csv.guide.\(kind.rawValue).example"
        switch kind {
        case .transactions: return L10n.format(key, bookCurrency, bookCurrency)
        case .deposits: return L10n.format(key, bookCurrency, bookCurrency)
        case .loans: return L10n.format(key, bookCurrency, bookCurrency)
        case .recurring: return L10n.format(key, bookCurrency, bookCurrency)
        }
    }
    static func guide(bookCurrency: String) -> String {
        let tables = MacCSVKind.allCases.map { "\($0.title) · \($0.templateName)\n\($0.headers.joined(separator: ","))" }.joined(separator: "\n\n")
        var sections = [L10n.format("csv.guide.introduction", bookCurrency, tables), L10n.text("csv.guide.commonHeading"), commonInstructions(bookCurrency: bookCurrency)]
        for kind in MacCSVKind.allCases {
            sections += [L10n.text("csv.guide.\(kind.rawValue).ruleTitle"), L10n.text("csv.guide.\(kind.rawValue).rules")]
        }
        sections.append(L10n.text("csv.guide.examplesHeading"))
        for kind in MacCSVKind.allCases {
            sections += [L10n.text("csv.guide.\(kind.rawValue).exampleTitle"), exampleInstructions(kind: kind, bookCurrency: bookCurrency)]
        }
        sections.append(L10n.text("csv.guide.footer"))
        return sections.joined(separator: "\n\n")
    }

}

/// Strict structural preflight prevents legacy readers from silently dropping cells/sections.
nonisolated struct MacCSVDocument: Sendable {
    struct Record: Sendable { let line: Int; let cells: [String] }
    let records: [Record]
    let templateKind: MacCSVKind?
    let templateBaseCurrency: String?
    var isSectioned: Bool { records.first?.cells.first?.lowercased() == "section" }

    init(_ content: String) throws {
        var input = content.hasPrefix("\u{FEFF}") ? String(content.dropFirst()) : content
        input = input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard !input.contains("\0") else { throw MacCSV.Failure.invalid(L10n.text("mac.cSVFormat.copy.b9bf1a729a")) }
        let firstLine = String(input.split(separator: "\n", omittingEmptySubsequences: true).first ?? "")
        var delimiter: Character = ",", best = -1
        for candidate: Character in [",", ";", "\t"] {
            var quoted = false, score = 0
            for c in firstLine { if c == "\"" { quoted.toggle() }; if c == candidate && !quoted { score += 1 } }
            if score > best { delimiter = candidate; best = score }
        }
        var result: [Record] = [], cells: [String] = [], field = ""
        var quoted = false, closed = false, line = 1, startLine = 1
        let chars = Array(input)
        var index = 0
        func appendRecord() {
            cells.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
            if cells.contains(where: { !$0.isEmpty }) { result.append(.init(line: startLine, cells: cells)) }
            cells = []; field = ""; closed = false
        }
        while index < chars.count {
            let c = chars[index]
            if quoted {
                if c == "\"" {
                    if index + 1 < chars.count && chars[index + 1] == "\"" { field.append(c); index += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(c); if c == "\n" { line += 1 } }
            } else if c == delimiter {
                cells.append(field.trimmingCharacters(in: .whitespacesAndNewlines)); field = ""; closed = false
            } else if c == "\n" {
                appendRecord(); line += 1; startLine = line
            } else if c == "\"" && field.isEmpty && !closed {
                quoted = true
            } else {
                guard !closed && c != "\"" else { throw MacCSV.Failure.invalid(L10n.format("mac.cSVFormat.copy.27e2c82879", "\(line)")) }
                field.append(c)
            }
            index += 1
        }
        guard !quoted else { throw MacCSV.Failure.invalid(L10n.format("mac.cSVFormat.copy.30c583129b", "\(startLine)")) }
        if !field.isEmpty || !cells.isEmpty || closed { appendRecord() }
        guard !result.isEmpty else { throw MacCSV.Failure.empty }
        if result[0].cells.first == "#FinTrackTemplate" {
            let marker = result[0].cells
            guard marker.count >= 4, marker[1] == "1", let kind = MacCSVKind(rawValue: marker[2]),
                  marker.count == kind.headers.count, marker.dropFirst(4).allSatisfy({ $0.isEmpty }),
                  marker[3] == marker[3].uppercased(), (try? MacFXPair(base: marker[3], quote: marker[3]).base) == marker[3],
                  result.count >= 3 else { throw MacCSV.Failure.invalid(L10n.text("mac.cSVFormat.copy.ba4c637d2d")) }
            let instructions = result[1].cells
            guard instructions.count == kind.headers.count, instructions[0] == "#AIInstructions",
                  !instructions[1].isEmpty, instructions.dropFirst(2).allSatisfy({ $0.isEmpty }) else {
                throw MacCSV.Failure.invalid(L10n.text("mac.cSVFormat.copy.96e270ed17"))
            }
            templateKind = kind; templateBaseCurrency = marker[3]
            result.removeFirst(2)
            guard Set(result[0].cells) == Set(kind.headers), result[0].cells.count == kind.headers.count else {
                throw MacCSV.Failure.invalid(L10n.format("mac.cSVFormat.copy.b9db0602e2", "\(kind.title)"))
            }
        } else {
            templateKind = nil; templateBaseCurrency = nil
        }
        records = result
        try validateStructure()
    }

    private func validateStructure() throws {
        var headers: [String] = [], sections = Set<String>(), needsHeader = !isSectioned
        for (index, row) in records.enumerated() {
            if isSectioned && row.cells.first?.lowercased() == "section" {
                guard !needsHeader, row.cells.count == 2, !row.cells[1].isEmpty else {
                    throw MacCSV.Failure.invalid(L10n.format("mac.cSVFormat.validateStructure.dd1a6d1710", "\(row.line)"))
                }
                let key = row.cells[1].lowercased().filter { !$0.isWhitespace }
                guard sections.insert(key).inserted else { throw MacCSV.Failure.invalid(L10n.format("mac.cSVFormat.validateStructure.2c2a458fd0", "\(row.line)", "\(row.cells[1])")) }
                needsHeader = true
            } else if needsHeader || (!isSectioned && index == 0) {
                headers = row.cells
                guard headers.allSatisfy({ !$0.isEmpty }), Set(headers.map { $0.lowercased() }).count == headers.count else {
                    throw MacCSV.Failure.invalid(L10n.format("mac.cSVFormat.validateStructure.7a8da9c82a", "\(row.line)"))
                }
                needsHeader = false
            } else {
                guard row.cells.count == headers.count else {
                    throw MacCSV.Failure.invalid(L10n.format("mac.cSVFormat.validateStructure.5a4cfa6888", "\(row.line)", Int64(headers.count), Int64(row.cells.count)))
                }
            }
        }
        guard !needsHeader else { throw MacCSV.Failure.invalid(L10n.text("mac.cSVFormat.validateStructure.64b759d0b6")) }
    }
}
