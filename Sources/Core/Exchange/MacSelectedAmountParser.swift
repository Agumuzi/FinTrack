import Foundation

/// Selected text has locale ambiguities that normal ledger entry does not.
nonisolated enum MacSelectedAmountParser {
    struct Parsed: Equatable {
        var amounts: [Decimal]
        var currencies: [String]
    }
    static func parse(_ text: String) -> Parsed? {
        guard text.count <= 500 else { return nil }
        let normalized = text.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "\u{00a0}", with: " ").replacingOccurrences(of: "\u{202f}", with: " ")
        let pattern = #"[+-]?\d+(?:[.,' ]\d+)*"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = expression.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized))
        guard matches.count == 1, let range = Range(matches[0].range, in: normalized) else { return nil }
        let raw = String(normalized[range]).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "'", with: "")
        let comma = raw.lastIndex(of: ","), dot = raw.lastIndex(of: ".")
        var variants: [String] = []
        if let comma, let dot {
            let decimal: Character = comma > dot ? "," : "."
            let grouping: Character = decimal == "," ? "." : ","
            let pieces = raw.split(separator: decimal, omittingEmptySubsequences: false)
            guard pieces.count == 2, validGrouped(String(pieces[0]), separator: grouping), !pieces[1].contains(grouping) else { return nil }
            variants = [raw.replacingOccurrences(of: String(grouping), with: "").replacingOccurrences(of: String(decimal), with: ".")]
        } else if let separator: Character = comma != nil ? "," : dot != nil ? "." : nil {
            let pieces = raw.split(separator: separator, omittingEmptySubsequences: false)
            if pieces.count > 2 {
                guard validGrouped(raw, separator: separator) else { return nil }
                variants = [raw.replacingOccurrences(of: String(separator), with: "")]
            } else {
                guard pieces.count == 2, !pieces[1].isEmpty else { return nil }
                variants = [raw.replacingOccurrences(of: String(separator), with: ".")]
                if pieces[1].count == 3 && pieces[0].filter(\.isNumber).count <= 3 { variants.append(raw.replacingOccurrences(of: String(separator), with: "")) }
            }
        } else { variants = [raw] }
        let amounts = Array(Set(variants.compactMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }))
            .sorted { $0 < $1 }
        guard !amounts.isEmpty else { return nil }
        let upper = normalized.uppercased()
        let codeRegex = try? NSRegularExpression(pattern: #"(?<![A-Z])[A-Z]{3}(?![A-Z])"#)
        let iso = Set(Locale.Currency.isoCurrencies.map(\.identifier))
        let explicit = codeRegex?.matches(in: upper, range: NSRange(upper.startIndex..., in: upper)).compactMap { match -> String? in
            guard let r = Range(match.range, in: upper) else { return nil }; let code = String(upper[r]); return iso.contains(code) ? code : nil
        } ?? []
        var currencies = Array(Set(explicit)).sorted()
        if currencies.isEmpty {
            let mappings: [(String, [String])] = [("US$",["USD"]),("HK$",["HKD"]),("CA$",["CAD"]),("AU$",["AUD"]),("CN¥",["CNY"]),("JP¥",["JPY"]),("€",["EUR"]),("£",["GBP"]),("₽",["RUB"]),("₺",["TRY"]),("₩",["KRW"]),("$",["USD","CAD","AUD","HKD","SGD","NZD"]),("¥",["CNY","JPY"]),("￥",["CNY","JPY"])]
            currencies = mappings.first { upper.contains($0.0) }?.1 ?? []
            if currencies.isEmpty {
                let names = [("人民币","CNY"),("美元","USD"),("欧元","EUR"),("卢布","RUB"),("里拉","TRY"),("日元","JPY"),("英镑","GBP"),("港币","HKD")]
                currencies = names.filter { normalized.contains($0.0) }.map(\.1)
            }
        }
        guard currencies.count <= 6 else { return nil }
        return Parsed(amounts: amounts, currencies: currencies)
    }
    private static func validGrouped(_ input: String, separator: Character) -> Bool {
        let parts = input.trimmingCharacters(in: CharacterSet(charactersIn: "+-")).split(separator: separator, omittingEmptySubsequences: false)
        return !parts.isEmpty && (1...3).contains(parts[0].count) && parts.allSatisfy { $0.allSatisfy(\.isNumber) } && parts.dropFirst().allSatisfy { $0.count == 3 }
    }
}
