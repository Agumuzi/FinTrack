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
            throw MacCSV.Failure.invalid(L10n.format("mac.cSVStandard.section.ebf888f4eb", "\(kind.title)", "\(kind.headers.joined(separator: ","))"))
        }
        let book = try MacCurrency.code(bookCurrency)
        let now = ISO8601DateFormatter().string(from: Date())
        let rows = try document.records.dropFirst().map { record -> CSVImportSectionTable.RawRow in
            let values = Dictionary(uniqueKeysWithValues: zip(headers, record.cells))
            func fail(_ field: String) -> MacCSV.Failure { .invalid(L10n.format("mac.cSVStandard.fail.acaad330e0", "\(record.line)", "\(field)")) }
            func name(_ field: String) throws -> String {
                guard let value = values[field], !value.isEmpty, value.count <= 100 else { throw fail(field + L10n.text("mac.cSVStandard.fail.b30c93afe3")) }
                return value
            }
            func number(_ field: String, scale: Int, positive: Bool = false, maximum: Double = 1e12) throws -> Double {
                let text = values[field] ?? ""
                guard text.range(of: "^[0-9]+(?:\\.[0-9]{1,\(scale)})?$", options: .regularExpression) != nil,
                      let value = Double(text), value.isFinite, value <= maximum,
                      positive ? value > 0 : value >= 0 else { throw fail(field + L10n.text("mac.cSVStandard.fail.4909079d22")) }
                return value
            }
            @MainActor func date(_ field: String) throws -> Date { try MacCSV.parsedDate(values[field] ?? "", field: L10n.format("mac.cSVStandard.date.547eea2d9a", "\(record.line)") + field) }
            func rate(_ field: String) throws -> Double {
                if values[field, default: ""].isEmpty && values["Currency"] == book { return 1 }
                return try number(field, scale: 6, positive: true, maximum: 1e9)
            }
            guard let id = UUID(uuidString: values["ID"] ?? "") else { throw fail(L10n.text("mac.cSVStandard.fail.7d094c7059")) }
            guard let source = values["Currency"], source == source.uppercased(), (try? MacCurrency.code(source)) == source else { throw fail(L10n.text("mac.cSVStandard.fail.390bf6bfd7")) }
            guard values["BaseCurrency"] == book else { throw fail(L10n.text("mac.cSVStandard.fail.dfea5b594a") + book) }
            let note = values["Note"] ?? ""
            guard !note.contains("[FT") else { throw fail(L10n.text("mac.cSVStandard.fail.f62baae042")) }
            let principalField = kind == .deposits || kind == .loans ? "Principal" : "Amount"
            let amount = try number(principalField, scale: 2, positive: true)
            let snapshot: MacCurrencySnapshot
            do { snapshot = try MacCurrency.snapshot(amount: amount, original: source, base: book, rate: rate("ExchangeRate")) }
            catch { throw fail(L10n.text("mac.cSVStandard.fail.7a881e1936")) }
            var row = values
            row["ID"] = id.uuidString
            row["CreatedAt"] = now; row["UpdatedAt"] = now; row["SyncVersion"] = "1"
            row["ExchangeRateToBase"] = String(snapshot.rate)
            row["OriginalCurrency"] = source
            row["OriginalAmount"] = String(amount); row["BaseAmount"] = String(snapshot.baseAmount)
            switch kind {
            case .transactions, .recurring:
                guard ["Income", "Expense"].contains(values["Type"] ?? "") else { throw fail(L10n.text("mac.cSVStandard.fail.2f9adc429e")) }
                row["Category"] = try name("Category")
                if kind == .transactions {
                    _ = try date("Date")
                    row["Currency"] = book; row["Amount"] = String(snapshot.baseAmount)
                } else {
                    row["Title"] = try name("Title")
                    guard let interval = Int(values["IntervalValue"] ?? ""), (1...365).contains(interval),
                          String(interval) == values["IntervalValue"], RecurringIntervalUnit(rawValue: values["IntervalUnit"] ?? "") != nil else { throw fail(L10n.text("mac.cSVStandard.fail.728b7f1b72")) }
                    let next = try date("NextExecutionDate")
                    if !values["EndDate", default: ""].isEmpty, try date("EndDate") < next { throw fail(L10n.text("mac.cSVStandard.fail.c21c43f4db")) }
                    row["ProjectIdentifier"] = MacFinanceRecords.managedRecurringTag
                    row["IsActive"] = "false"; row["NotificationsEnabled"] = "false"
                }
            case .deposits:
                row["BankName"] = try name("BankName")
                let annual = try number("AnnualInterestRate", scale: 4, maximum: 100)
                let start = try date("StartDate"), end = try date("MaturityDate")
                guard end > start else { throw fail(L10n.text("mac.cSVStandard.fail.9876b17f8b")) }
                guard let mode = DepositInterestSettlementMode(rawValue: values["InterestSettlementMode"] ?? "") else { throw fail(L10n.text("mac.cSVStandard.fail.b757df3433")) }
                let override = values["ExpectedInterest", default: ""].isEmpty ? nil : try number("ExpectedInterest", scale: 2)
                let terms = try MacDepositTerms.calculate(principal: amount, annualRate: annual, start: start, maturity: end, mode: mode, expectedOverride: override)
                let interest: MacCurrencySnapshot
                do { interest = try MacCurrency.snapshot(amount: terms.expectedInterest, original: source, base: book, rate: rate("InterestExchangeRate")) }
                catch { throw fail(L10n.text("mac.cSVStandard.fail.cd0c945faf")) }
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
                      RepaymentMethod(rawValue: values["Method"] ?? "") != nil else { throw fail(L10n.text("mac.cSVStandard.fail.4bc5204cca")) }
                _ = try date("StartDate")
                row["BasePrincipal"] = String(snapshot.baseAmount); row["TotalAmount"] = String(amount)
                row["DownPaymentAmount"] = "0"; row["DownPaymentPercent"] = "0"
                row["Note"] = MacFinanceNotes.replacing(MacFinanceRecords.managedLoanTag, with: note)
            }
            // The legacy persistence adapter reads ISO timestamps only. Normalize
            // accepted calendar dates here so it can never replace them with now.
            for field in ["Date", "StartDate", "MaturityDate", "NextExecutionDate", "EndDate"] where row[field, default: ""].count == 10 {
                row[field] = ISO8601DateFormatter().string(from: try MacCSV.parsedDate(row[field]!, field: L10n.format("mac.cSVStandard.rows.547eea2d9a", "\(record.line)") + field))
            }
            return .init(rowIndex: record.line, values: row)
        }
        return .init(sectionTitle: kind.sectionTitle, headers: rows.first.map { Array($0.values.keys) } ?? [], rows: rows)
    }
}
