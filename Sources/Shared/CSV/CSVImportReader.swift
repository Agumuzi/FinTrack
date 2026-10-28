import Foundation

nonisolated struct CSVImportTable: Hashable, Sendable {
    struct RawRow: Hashable, Sendable {
        let rowIndex: Int
        let values: [String: String]
    }

    let headers: [String]
    let rows: [RawRow]
}

nonisolated struct CSVImportSectionTable: Hashable, Sendable {
    struct RawRow: Hashable, Sendable {
        let rowIndex: Int
        let values: [String: String]
    }

    let sectionTitle: String
    let headers: [String]
    let rows: [RawRow]
}

nonisolated struct CSVImportReader {
    enum ReaderError: LocalizedError {
        case emptyFile
        case malformedCSV

        var errorDescription: String? {
            switch self {
            case .emptyFile:
                return "CSV file is empty."
            case .malformedCSV:
                return "CSV file could not be parsed."
            }
        }
    }

    func read(contents: String) throws -> CSVImportTable {
        let sanitizedContents = contents
            .removingUTF8BOM()
            .normalizingCSVLineEndings()
        let delimiter = detectDelimiter(in: sanitizedContents)
        let parsedRows = try parseCSVRows(from: sanitizedContents, delimiter: delimiter)
        guard parsedRows.isEmpty == false else {
            throw ReaderError.emptyFile
        }

        if let sectionTable = extractFinTrackTransactionsSection(from: parsedRows) {
            return sectionTable
        }

        guard let headerRow = parsedRows.first else {
            throw ReaderError.emptyFile
        }

        let headers = headerRow.map(normalizeHeader)
        guard headers.isEmpty == false else {
            throw ReaderError.emptyFile
        }

        let rows = parsedRows.dropFirst().enumerated().compactMap { offset, values -> CSVImportTable.RawRow? in
            let mappedValues = mapValues(values, to: headers)
            guard mappedValues.values.contains(where: { $0.isEmpty == false }) else {
                return nil
            }
            return CSVImportTable.RawRow(rowIndex: offset + 2, values: mappedValues)
        }

        return CSVImportTable(headers: headers, rows: rows)
    }

    func readSections(contents: String) throws -> [String: CSVImportSectionTable] {
        let sanitizedContents = contents
            .removingUTF8BOM()
            .normalizingCSVLineEndings()
        let delimiter = detectDelimiter(in: sanitizedContents)
        let parsedRows = try parseCSVRows(from: sanitizedContents, delimiter: delimiter)
        guard parsedRows.isEmpty == false else {
            throw ReaderError.emptyFile
        }

        var sections: [String: CSVImportSectionTable] = [:]
        var index = 0

        while index < parsedRows.count {
            let row = parsedRows[index]
            guard isSectionHeaderRow(row), row.count >= 2 else {
                index += 1
                continue
            }

            let sectionTitle = row[1].removingUTF8BOM().trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedSectionTitle = normalizedSectionLabel(sectionTitle)
            let headerIndex = index + 1
            guard headerIndex < parsedRows.count else { break }

            let headerRow = parsedRows[headerIndex].map {
                $0.removingUTF8BOM().trimmingCharacters(in: .whitespacesAndNewlines)
            }

            var dataRows: [CSVImportSectionTable.RawRow] = []
            var cursor = headerIndex + 1

            while cursor < parsedRows.count {
                let values = parsedRows[cursor]
                if isSectionHeaderRow(values) {
                    break
                }

                let mappedValues = mapValues(values, toRawHeaders: headerRow)
                if mappedValues.values.contains(where: { $0.isEmpty == false }) {
                    dataRows.append(
                        CSVImportSectionTable.RawRow(
                            rowIndex: cursor + 1,
                            values: mappedValues
                        )
                    )
                }
                cursor += 1
            }

            sections[normalizedSectionTitle] = CSVImportSectionTable(
                sectionTitle: sectionTitle,
                headers: headerRow,
                rows: dataRows
            )
            index = cursor
        }

        return sections
    }

    private func extractFinTrackTransactionsSection(from parsedRows: [[String]]) -> CSVImportTable? {
        guard let sectionIndex = parsedRows.firstIndex(where: isTransactionsSectionHeader) else {
            return nil
        }

        let headerIndex = sectionIndex + 1
        guard headerIndex < parsedRows.count else {
            return CSVImportTable(headers: [], rows: [])
        }

        let headerRow = parsedRows[headerIndex]
        let headers = headerRow.map(normalizeHeader)
        guard headers.isEmpty == false else {
            return CSVImportTable(headers: [], rows: [])
        }

        var rows: [CSVImportTable.RawRow] = []
        var currentIndex = headerIndex + 1

        while currentIndex < parsedRows.count {
            let values = parsedRows[currentIndex]
            if isSectionHeaderRow(values) {
                break
            }

            let mappedValues = mapValues(values, to: headers)
            if mappedValues.values.contains(where: { $0.isEmpty == false }) {
                rows.append(
                    CSVImportTable.RawRow(
                        rowIndex: currentIndex + 1,
                        values: mappedValues
                    )
                )
            }
            currentIndex += 1
        }

        return CSVImportTable(headers: headers, rows: rows)
    }

    private func isTransactionsSectionHeader(_ row: [String]) -> Bool {
        guard row.count >= 2 else { return false }
        return normalizedSectionLabel(row[0]) == "section"
            && normalizedSectionLabel(row[1]) == "transactions"
    }

    private func isSectionHeaderRow(_ row: [String]) -> Bool {
        guard row.isEmpty == false else { return false }
        return normalizedSectionLabel(row[0]) == "section"
    }

    private func normalizedSectionLabel(_ value: String) -> String {
        value
            .removingUTF8BOM()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private func normalizeHeader(_ header: String) -> String {
        let trimmed = header.removingUTF8BOM().trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }

        let simplified = trimmed
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let canonicalKey = simplified.headerAliasKey()

        if let directMatch = Self.headerAliases[canonicalKey] {
            return directMatch
        }

        return Self.keywordHeaderAliases.first { canonicalKey.contains($0.key) }?.value ?? ""
    }

    private func mapValues(_ values: [String], to headers: [String]) -> [String: String] {
        var mapped: [String: String] = [:]
        for (index, header) in headers.enumerated() {
            guard header.isEmpty == false else { continue }
            let rawValue = index < values.count ? values[index] : ""
            mapped[header] = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return mapped
    }

    private func mapValues(_ values: [String], toRawHeaders headers: [String]) -> [String: String] {
        var mapped: [String: String] = [:]
        for (index, header) in headers.enumerated() {
            guard header.isEmpty == false else { continue }
            let rawValue = index < values.count ? values[index] : ""
            mapped[header] = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return mapped
    }

    private func detectDelimiter(in contents: String) -> Character {
        let candidateLines = contents
            .split(whereSeparator: \.isNewline)
            .prefix(5)

        let candidateDelimiters: [Character] = [",", ";", "\t"]
        let detected = candidateDelimiters.max { lhs, rhs in
            let lhsScore = candidateLines.reduce(0) { $0 + countOccurrences(of: lhs, in: String($1)) }
            let rhsScore = candidateLines.reduce(0) { $0 + countOccurrences(of: rhs, in: String($1)) }
            return lhsScore < rhsScore
        }

        return detected ?? ","
    }

    private func countOccurrences(of delimiter: Character, in line: String) -> Int {
        var count = 0
        var insideQuotes = false

        for character in line {
            if character == "\"" {
                insideQuotes.toggle()
            } else if character == delimiter, insideQuotes == false {
                count += 1
            }
        }

        return count
    }

    private func parseCSVRows(from contents: String, delimiter: Character) throws -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false

        let characters = Array(contents)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if insideQuotes {
                if character == "\"" {
                    let nextIndex = index + 1
                    if nextIndex < characters.count, characters[nextIndex] == "\"" {
                        currentField.append("\"")
                        index = nextIndex
                    } else {
                        insideQuotes = false
                    }
                } else {
                    currentField.append(character)
                }
            } else {
                switch character {
                case "\"":
                    insideQuotes = true
                case delimiter:
                    currentRow.append(currentField)
                    currentField = ""
                case "\n":
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                case "\r":
                    let nextIndex = index + 1
                    if nextIndex < characters.count, characters[nextIndex] == "\n" {
                        break
                    }

                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                default:
                    currentField.append(character)
                }
            }

            index += 1
        }

        if insideQuotes {
            throw ReaderError.malformedCSV
        }

        if currentField.isEmpty == false || currentRow.isEmpty == false {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return rows.filter { row in
            row.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        }
    }

    private static let headerAliases: [String: String] = [
        "date": "date",
        "transactiondate": "date",
        "postingdate": "date",
        "occurreddate": "date",
        "datetime": "date",
        "time": "date",
        "日期": "date",
        "时间": "date",
        "交易日期": "date",
        "发生日期": "date",
        "记账日期": "date",

        "type": "type",
        "transactiontype": "type",
        "entrytype": "type",
        "kind": "type",
        "direction": "type",
        "收支类型": "type",
        "交易类型": "type",
        "类型": "type",
        "收入支出": "type",

        "amount": "amount",
        "value": "amount",
        "money": "amount",
        "transactionamount": "amount",
        "金额": "amount",
        "数额": "amount",
        "发生金额": "amount",

        "category": "category",
        "categories": "category",
        "classification": "category",
        "tag": "category",
        "类别": "category",
        "分类": "category",
        "交易分类": "category",
        "收支分类": "category",

        "note": "note",
        "notes": "note",
        "memo": "note",
        "description": "note",
        "comment": "note",
        "备注": "note",
        "说明": "note",
        "描述": "note",

        "currency": "currency",
        "currencycode": "currency",
        "ccy": "currency",
        "币种": "currency",
        "货币": "currency",
        "货币代码": "currency",

        "account": "account",
        "accountname": "account",
        "wallet": "account",
        "账户": "account",
        "账户名称": "account",
        "账号": "account",
        "钱包": "account",

        "exchangerate": "exchange_rate",
        "rate": "exchange_rate",
        "fxrate": "exchange_rate",
        "conversionrate": "exchange_rate",
        "汇率": "exchange_rate",
        "兑换汇率": "exchange_rate"
    ]

    private static let keywordHeaderAliases: [(key: String, value: String)] = [
        ("transactiondate", "date"),
        ("postingdate", "date"),
        ("occurreddate", "date"),
        ("日期", "date"),
        ("时间", "date"),

        ("transactiontype", "type"),
        ("entrytype", "type"),
        ("收支", "type"),
        ("类型", "type"),

        ("amount", "amount"),
        ("money", "amount"),
        ("金额", "amount"),
        ("数额", "amount"),

        ("category", "category"),
        ("classification", "category"),
        ("tag", "category"),
        ("分类", "category"),
        ("类别", "category"),

        ("note", "note"),
        ("memo", "note"),
        ("description", "note"),
        ("comment", "note"),
        ("备注", "note"),
        ("说明", "note"),

        ("currency", "currency"),
        ("ccy", "currency"),
        ("币种", "currency"),
        ("货币", "currency"),

        ("account", "account"),
        ("wallet", "account"),
        ("账户", "account"),
        ("账号", "account"),
        ("钱包", "account"),

        ("exchangerate", "exchange_rate"),
        ("fxrate", "exchange_rate"),
        ("汇率", "exchange_rate"),
        ("rate", "exchange_rate")
    ]
}
private extension String {
    nonisolated func removingUTF8BOM() -> String {
        hasPrefix("\u{FEFF}") ? String(dropFirst()) : self
    }

    nonisolated func normalizingCSVLineEndings() -> String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
            .replacingOccurrences(of: "\u{0085}", with: "\n")
            .replacingOccurrences(of: "\0", with: "")
    }

    nonisolated func headerAliasKey() -> String {
        unicodeScalars.reduce(into: "") { result, scalar in
            if CharacterSet.alphanumerics.contains(scalar) || scalar.value >= 0x4E00 && scalar.value <= 0x9FFF {
                result.unicodeScalars.append(scalar)
            }
        }
    }
}
