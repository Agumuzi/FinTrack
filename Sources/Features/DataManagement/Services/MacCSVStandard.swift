import Foundation

@MainActor
enum MacCSVStandard {
    static func kind(headers: [String]) -> MacCSVKind {
        if headers.contains("BankName") { return .deposits }
        if headers.contains("TermMonths") { return .loans }
        if headers.contains("IntervalValue") { return .recurring }
        return .transactions
    }

    static func section(_ document: MacCSVDocument, kind: MacCSVKind, bookCurrency: String) throws -> CSVImportSectionTable {
        let headers = document.records[0].cells
        guard Set(headers) == Set(kind.headers), headers.count == kind.headers.count else {
            throw MacCSV.Failure.invalid("请选择\(kind.title)模板，并保留全部列：\(kind.headers.joined(separator: ","))")
        }
        let book = try MacCurrency.code(bookCurrency)
        let now = ISO8601DateFormatter().string(from: Date())
        let rows = try document.records.dropFirst().map { record -> CSVImportSectionTable.RawRow in
            let values = Dictionary(uniqueKeysWithValues: zip(headers, record.cells))
            func fail(_ field: String) -> MacCSV.Failure { .invalid("第 \(record.line) 行：\(field)") }
            func name(_ field: String) throws -> String {
                guard let value = values[field], !value.isEmpty, value.count <= 100 else { throw fail(field + " 必须为1到100字符") }
                return value
            }
            func number(_ field: String, scale: Int, positive: Bool = false, maximum: Double = 1e12) throws -> Double {
                let text = values[field] ?? ""
                guard text.range(of: "^[0-9]+(?:\\.[0-9]{1,\(scale)})?$", options: .regularExpression) != nil,
                      let value = Double(text), value.isFinite, value <= maximum,
                      positive ? value > 0 : value >= 0 else { throw fail(field + " 数值或小数位数不正确") }
                return value
            }
            @MainActor func date(_ field: String) throws -> Date { try MacCSV.parsedDate(values[field] ?? "", field: "第 \(record.line) 行：" + field) }
            func rate(_ field: String) throws -> Double {
                if values[field, default: ""].isEmpty && values["Currency"] == book { return 1 }
                return try number(field, scale: 6, positive: true, maximum: 1e9)
            }
            guard let id = UUID(uuidString: values["ID"] ?? "") else { throw fail("ID 必须为有效UUID") }
            guard let source = values["Currency"], source == source.uppercased(), (try? MacCurrency.code(source)) == source else { throw fail("Currency 必须为三位大写代码") }
            guard values["BaseCurrency"] == book else { throw fail("BaseCurrency 必须为当前账本本位币 " + book) }
            let note = values["Note"] ?? ""
            guard !note.contains("[FT") else { throw fail("Note 不允许包含软件内部的 [FT 标记") }
            let principalField = kind == .deposits || kind == .loans ? "Principal" : "Amount"
            let amount = try number(principalField, scale: 2, positive: true)
            let snapshot: MacCurrencySnapshot
            do { snapshot = try MacCurrency.snapshot(amount: amount, original: source, base: book, rate: rate("ExchangeRate")) }
            catch { throw fail("ExchangeRate 或换算后金额无效；同币必须为1，异币必须提供历史汇率") }
            var row = values
            row["ID"] = id.uuidString
            row["CreatedAt"] = now; row["UpdatedAt"] = now; row["SyncVersion"] = "1"
            row["ExchangeRateToBase"] = String(snapshot.rate)
            row["OriginalCurrency"] = source
            row["OriginalAmount"] = String(amount); row["BaseAmount"] = String(snapshot.baseAmount)
            switch kind {
            case .transactions, .recurring:
                guard ["Income", "Expense"].contains(values["Type"] ?? "") else { throw fail("Type 只能为 Income 或 Expense") }
                row["Category"] = try name("Category")
                if kind == .transactions {
                    _ = try date("Date")
                    row["Currency"] = book; row["Amount"] = String(snapshot.baseAmount)
                } else {
                    row["Title"] = try name("Title")
                    guard let interval = Int(values["IntervalValue"] ?? ""), (1...365).contains(interval),
                          String(interval) == values["IntervalValue"], RecurringIntervalUnit(rawValue: values["IntervalUnit"] ?? "") != nil else { throw fail("IntervalValue / IntervalUnit 无效") }
                    let next = try date("NextExecutionDate")
                    if !values["EndDate", default: ""].isEmpty, try date("EndDate") < next { throw fail("EndDate 早于 NextExecutionDate") }
                    row["ProjectIdentifier"] = MacFinanceRecords.managedRecurringTag
                    row["IsActive"] = "false"; row["NotificationsEnabled"] = "false"
                }
            case .deposits:
                row["BankName"] = try name("BankName")
                let annual = try number("AnnualInterestRate", scale: 4, maximum: 100)
                let start = try date("StartDate"), end = try date("MaturityDate")
                guard end > start else { throw fail("MaturityDate 必须晚于 StartDate") }
                guard let mode = DepositInterestSettlementMode(rawValue: values["InterestSettlementMode"] ?? "") else { throw fail("InterestSettlementMode 无效") }
                let override = values["ExpectedInterest", default: ""].isEmpty ? nil : try number("ExpectedInterest", scale: 2)
                let terms = try MacDepositTerms.calculate(principal: amount, annualRate: annual, start: start, maturity: end, mode: mode, expectedOverride: override)
                let interest: MacCurrencySnapshot
                do { interest = try MacCurrency.snapshot(amount: terms.expectedInterest, original: source, base: book, rate: rate("InterestExchangeRate")) }
                catch { throw fail("InterestExchangeRate 或预计利息换算无效") }
                row["OriginalPrincipal"] = String(amount); row["BasePrincipal"] = String(snapshot.baseAmount)
                row["PrincipalExchangeRateToBase"] = String(snapshot.rate)
                row["ExpectedInterest"] = String(terms.expectedInterest); row["BaseExpectedInterest"] = String(interest.baseAmount)
                row["AnnualInterestRate"] = String(terms.annualRate)
                row["InterestExchangeRateToBase"] = String(interest.rate)
                row["IsInterestManuallyEdited"] = String(terms.manuallyEdited)
                row["IsActive"] = "true"; row["HasCreditedInterest"] = "false"
                row["NotificationsEnabled"] = "false"; row["MaturityInterestHandling"] = "Payout"
                if mode == .monthly {
                    row["NextInterestPayoutDate"] = ISO8601DateFormatter().string(from: min(Calendar.current.date(byAdding: .month, value: 1, to: start) ?? end, end))
                }
                row["Note"] = MacFinanceNotes.replacing(MacFinanceRecords.managedDepositTag, with: note)
            case .loans:
                row["Title"] = try name("Title"); row["Category"] = try name("Category")
                _ = try number("AnnualRate", scale: 4, maximum: 100)
                guard let term = Int(values["TermMonths"] ?? ""), (1...600).contains(term), String(term) == values["TermMonths"],
                      RepaymentMethod(rawValue: values["Method"] ?? "") != nil else { throw fail("TermMonths / Method 无效") }
                _ = try date("StartDate")
                row["BasePrincipal"] = String(snapshot.baseAmount); row["TotalAmount"] = String(amount)
                row["DownPaymentAmount"] = "0"; row["DownPaymentPercent"] = "0"
                row["Note"] = MacFinanceNotes.replacing(MacFinanceRecords.managedLoanTag, with: note)
            }
            // The legacy persistence adapter reads ISO timestamps only. Normalize
            // accepted calendar dates here so it can never replace them with now.
            for field in ["Date", "StartDate", "MaturityDate", "NextExecutionDate", "EndDate"] where row[field, default: ""].count == 10 {
                row[field] = ISO8601DateFormatter().string(from: try MacCSV.parsedDate(row[field]!, field: "第 \(record.line) 行：" + field))
            }
            return .init(rowIndex: record.line, values: row)
        }
        return .init(sectionTitle: kind.sectionTitle, headers: rows.first.map { Array($0.values.keys) } ?? [], rows: rows)
    }
}
