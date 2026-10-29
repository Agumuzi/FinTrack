import Foundation
import SwiftData

@MainActor
enum MacCSV {
    enum Failure: LocalizedError {
        case invalid(String), duplicateID(String), empty
        var errorDescription: String? {
            switch self {
            case .invalid(let detail): "CSV 导入已停止：\(detail)。本批未保存任何记录。"
            case .duplicateID(let detail): "CSV 中的 ID 重复：\(detail)。本批未保存任何记录。"
            case .empty: "CSV 中没有可导入的记录；请填写模板后再导入。"
            }
        }
    }

    struct Preview {
        let sections: [String: CSVImportSectionTable]
        let count: Int
        let currencies: [String]
        var standardBookCurrency: String? = nil
        var kind: MacCSVKind? = nil
        var hasStableIDs = true
    }

    static func export(in context: ModelContext) throws -> URL {
        guard let url = CSVExporter.exportAllDataCSV(
            transactions: try context.fetch(FetchDescriptor<Transaction>()),
            recurringRules: try context.fetch(FetchDescriptor<RecurringTransaction>()),
            deposits: try context.fetch(FetchDescriptor<DepositRecord>()),
            loans: try context.fetch(FetchDescriptor<LoanRule>()),
            goals: try context.fetch(FetchDescriptor<Goal>()),
            profiles: try context.fetch(FetchDescriptor<FinancialProfile>()),
            categories: try context.fetch(FetchDescriptor<Category>()),
            accounts: try context.fetch(FetchDescriptor<Account>()))
        else { throw Failure.invalid("Export could not be written") }
        return url
    }

    static func export(in context: ModelContext, kind: MacCSVKind, transactionRange: DateInterval? = nil) throws -> String {
        guard let url = CSVExporter.exportAllDataCSV(
            transactions: kind == .transactions ? try context.fetch(FetchDescriptor<Transaction>()).filter { $0.deletedAt == nil && (transactionRange == nil || ($0.date >= transactionRange!.start && $0.date < transactionRange!.end)) } : [],
            recurringRules: kind == .recurring ? try context.fetch(FetchDescriptor<RecurringTransaction>()).filter { $0.deletedAt == nil } : [],
            deposits: kind == .deposits ? try context.fetch(FetchDescriptor<DepositRecord>()).filter { $0.deletedAt == nil } : [],
            loans: kind == .loans ? try context.fetch(FetchDescriptor<LoanRule>()).filter { $0.deletedAt == nil } : [],
            goals: [], profiles: [], categories: [], accounts: []) else { throw Failure.invalid("导出失败") }
        defer { try? FileManager.default.removeItem(at: url) }
        let tables = try CSVImportReader().readSections(contents: String(contentsOf: url, encoding: .utf8))
        guard let table = tables[kind.sectionTitle.lowercased()] else { throw Failure.invalid("导出类型缺失") }
        return MacCSVFormat.csv(headers: table.headers, rows: table.rows.map { row in table.headers.map { row.values[$0] ?? "" } })
    }

    static func exportAsync(in context: ModelContext, kind: MacCSVKind? = nil, transactionRange: DateInterval? = nil) async throws -> String {
        var snapshot=try MacNativeBackup.capture(in:context,csvKind:kind)
        let section=kind?.sectionTitle
        if let kind {
            snapshot.transaction = kind == .transactions ? snapshot.transaction.filter{$0.deletedAt == nil && (transactionRange == nil || ($0.date >= transactionRange!.start && $0.date < transactionRange!.end))} : []
            snapshot.recurringTransaction = kind == .recurring ? snapshot.recurringTransaction.filter{$0.deletedAt == nil} : []
            snapshot.depositRecord = kind == .deposits ? snapshot.depositRecord.filter{$0.deletedAt == nil} : []
            snapshot.loanRule = kind == .loans ? snapshot.loanRule.filter{$0.deletedAt == nil} : []
        }
        let value=snapshot
        return try await Task.detached(priority:.userInitiated){try MacCSVSnapshotEncoder.encode(value,section:section)}.value
    }
    nonisolated private struct Parsed: Sendable {
        let document: MacCSVDocument
        let sections: [String: CSVImportSectionTable]
        let raw: [String: CSVImportSectionTable]
        let flat: CSVImportTable?
    }
    static func previewAsync(_ content: String, bookCurrency: String, kind: MacCSVKind? = nil) async throws -> Preview {
        let parsed=try await Task.detached(priority:.userInitiated) {
            guard content.utf8.count <= 50_000_000 else {throw Failure.invalid("文件不能超过50,000,000字节")}
            let document=try MacCSVDocument(content),headers=document.records[0].cells
            let standard = !document.isSectioned && headers.contains("ExchangeRate") && headers.contains("BaseCurrency")
            let native = !document.isSectioned && (headers.contains("OriginalAmount") || headers.contains("OriginalPrincipal") || headers.contains("BasePrincipal"))
            let name = headers.contains("BankName") ? "Deposits" : headers.contains("TermMonths") ? "Loans" : headers.contains("IntervalValue") ? "Recurring Transactions" : "Transactions"
            let text=content.hasPrefix("\u{FEFF}") ? String(content.dropFirst()):content
            let reader=CSVImportReader()
            let sections=standard ? [:]:try reader.readSections(contents:native ? "\"Section\",\""+name+"\"\n"+text:content)
            let raw = !standard && sections.isEmpty ? try reader.readSections(contents:"\"Section\",\"Transactions\"\n"+content):[:]
            let flat = !standard && sections.isEmpty && raw["transactions"]?.headers.contains(where:{$0.lowercased()=="originalamount"}) != true ? try reader.read(contents:content):nil
            return Parsed(document:document,sections:sections,raw:raw,flat:flat)
        }.value
        return try preview(content,bookCurrency:bookCurrency,kind:kind,parsed:parsed)
    }
    static func preview(_ content: String, bookCurrency: String, kind expectedKind: MacCSVKind? = nil) throws -> Preview {
        try preview(content,bookCurrency:bookCurrency,kind:expectedKind,parsed:nil)
    }
    private static func preview(_ content: String, bookCurrency: String, kind expectedKind: MacCSVKind?, parsed: Parsed?) throws -> Preview {
        guard content.utf8.count <= 50_000_000 else { throw Failure.invalid("文件不能超过50,000,000字节") }
        let document = try parsed?.document ?? MacCSVDocument(content)
        if let templateKind = document.templateKind {
            guard expectedKind == nil || expectedKind == templateKind else { throw Failure.invalid("所选类型为\(expectedKind!.title)，文件属于\(templateKind.title)") }
            guard document.templateBaseCurrency == (try MacCurrency.code(bookCurrency)) else { throw Failure.invalid("模板本位币为\(document.templateBaseCurrency ?? "")，与当前账本不符；请重新导出模板") }
        }
        let headers = document.records[0].cells
        let standard = !document.isSectioned && headers.contains("ExchangeRate") && headers.contains("BaseCurrency")
        if standard {
            let kind = MacCSVStandard.kind(headers: headers)
            guard expectedKind == nil || expectedKind == kind else { throw Failure.invalid("所选类型为\(expectedKind!.title)，文件属于\(kind.title)") }
            let table = try MacCSVStandard.section(document, kind: kind, bookCurrency: bookCurrency)
            let sections = [kind.sectionKey: table]
            try validate(sections)
            guard !table.rows.isEmpty else { throw Failure.empty }
            return Preview(sections: sections, count: table.rows.count, currencies: [try MacCurrency.code(bookCurrency)], standardBookCurrency: bookCurrency, kind: kind)
        }
        let reader = CSVImportReader()
        let nativeFlat = !document.isSectioned && (headers.contains("OriginalAmount") || headers.contains("OriginalPrincipal") || headers.contains("BasePrincipal"))
        let nativeKind = MacCSVStandard.kind(headers: headers)
        let flatContent = content.hasPrefix("\u{FEFF}") ? String(content.dropFirst()) : content
        let source = nativeFlat ? "\"Section\",\"\(nativeKind.sectionTitle)\"\n" + flatContent : content
        var sections = try parsed?.sections ?? reader.readSections(contents: source)
        var generatedIDs = false
        if sections.isEmpty {
            let raw = try parsed?.raw ?? reader.readSections(contents: "\"Section\",\"Transactions\"\n" + content)
            if raw["transactions"]?.headers.contains(where: { $0.lowercased() == "originalamount" }) == true {
                sections = raw
            } else {
                let table = try parsed?.flat ?? reader.read(contents: content)
                guard table.headers.allSatisfy({ !$0.isEmpty && $0 != "account" }), Set(table.headers).count == table.headers.count else {
                    throw Failure.invalid("普通收支CSV列名无法识别、重复映射或包含不支持的账户列；请使用记账模板，账户信息可放在Note")
                }
                let required = Set(["date", "type", "category", "currency", "amount"])
                guard required.isSubset(of: Set(table.headers)) else { throw Failure.invalid("缺少Date、Type、Category、Currency或Amount列") }
                let book = try MacCurrency.code(bookCurrency)
                generatedIDs = true
                var rows: [CSVImportSectionTable.RawRow] = []
                for row in table.rows {
                    guard let currency = row.values["currency"], !currency.isEmpty else { throw Failure.invalid("row \(row.rowIndex): Currency") }
                    let source = try MacCurrency.code(currency)
                    let amount = try MacTransactionCRUD.amount(row.values["amount"] ?? "")
                    try MacTransactionCRUD.validateManualNote(row.values["note"] ?? "")
                    let typeText = (row.values["type"] ?? "").lowercased()
                    guard let type = ["income": TransactionType.income, "expense": .expense,
                        "收入": .income, "支出": .expense, "доход": .income, "расход": .expense][typeText]
                    else { throw Failure.invalid("row \(row.rowIndex): Type") }
                    let category = try MacTransactionCRUD.validatedCategory(row.values["category"] ?? "")
                    let date = try parsedDate(row.values["date"] ?? "", field: "row \(row.rowIndex): Date")
                    let rawRate = row.values["exchange_rate"] ?? ""
                    let rate: Double? = source == book ? 1 : (rawRate.isEmpty ? nil : try MacCurrency.rate(rawRate))
                    let snapshot = try MacCurrency.snapshot(amount: amount, original: source, base: book, rate: rate)
                    let iso = ISO8601DateFormatter().string(from: date)
                    rows.append(.init(rowIndex: row.rowIndex, values: [
                        "ID": UUID().uuidString, "Date": iso, "Type": type.rawValue,
                        "Category": category, "Currency": book, "Amount": String(snapshot.baseAmount),
                        "OriginalAmount": String(amount), "OriginalCurrency": source,
                        "ExchangeRateToBase": String(snapshot.rate), "BaseAmount": String(snapshot.baseAmount),
                        "BaseCurrency": book, "Note": row.values["note"] ?? "",
                        "CreatedAt": iso, "UpdatedAt": iso, "SyncVersion": "1"
                    ]))
                }
                sections = ["transactions": .init(sectionTitle: "Transactions", headers: rows.first.map { Array($0.values.keys) } ?? [], rows: rows)]
            }
        }
        // Original exporter uses "Recurring Transactions" and "Financial Profile";
        // the original importer expects these keys without spaces.
        var normalized: [String: CSVImportSectionTable] = [:]
        for (key, table) in sections {
            let normalizedKey = key.filter { !$0.isWhitespace }
            guard normalized[normalizedKey] == nil else { throw Failure.invalid("Repeated section " + table.sectionTitle) }
            normalized[normalizedKey] = table
        }
        sections = normalized
        if let expectedKind, Set(sections.keys) != [expectedKind.sectionKey] {
            throw Failure.invalid("请选择\(expectedKind.title)的独立CSV；混合文件请使用旧版完整CSV兼容入口")
        }
        try validate(sections)
        let count = sections.values.reduce(0) { $0 + $1.rows.count }
        guard count > 0 else { throw Failure.empty }
        var currencies = Set<String>()
        for table in sections.values {
            for row in table.rows {
                if let code = row.values["BaseCurrency"], !code.isEmpty { currencies.insert(code) }
            }
        }
        if expectedKind != nil, currencies != [try MacCurrency.code(bookCurrency)] {
            throw Failure.invalid("独立数据文件的本位币必须与当前账本一致；原版历史文件请使用兼容入口并核对本位币")
        }
        return Preview(sections: sections, count: count, currencies: currencies.sorted(), standardBookCurrency: expectedKind == nil ? nil : bookCurrency, kind: expectedKind, hasStableIDs: !generatedIDs)
    }

    static func commit(_ preview: Preview, in context: ModelContext) throws -> FullDataImportCommitResult {
        try MacRecoveryJournal.assertWritable(in:context)
        guard !context.hasChanges else { throw Failure.invalid("Save or cancel pending edits first") }
        if let currency = preview.standardBookCurrency {
            _ = try MacCurrency.ledgerCurrency(in: context, preferred: currency)
        }
        try validate(preview.sections)
        var sections = preview.sections
        let accounts = try context.fetch(FetchDescriptor<Account>())
        if let table = sections["accounts"] {
            let rows = try table.rows.filter { row in
                let date = try parsedDate(row.values["CreatedAt"] ?? "", field: "Account.CreatedAt")
                return !accounts.contains {
                    $0.name == row.values["Name"] && $0.type == row.values["Type"] &&
                    $0.currency == row.values["Currency"] && $0.balance == Double(row.values["Balance"] ?? "") &&
                    Int64($0.createdAt.timeIntervalSince1970) == Int64(date.timeIntervalSince1970)
                }
            }
            sections["accounts"] = .init(sectionTitle: table.sectionTitle, headers: table.headers, rows: rows)
        }
        do {
            let result = try MacFullDataImportService().importBackup(sections: sections, into: context)
            // Reconstruct only deterministic original loan-generated links.
            // Unmatched rules remain visible for the legacy audit.
            let loans = try context.fetch(FetchDescriptor<LoanRule>())
            let rules = try context.fetch(FetchDescriptor<RecurringTransaction>())
            for loan in loans where loan.generatedRules.isEmpty {
                let prefix = "loan_generated:\(loan.id.uuidString):"
                let related = rules.filter { ($0.projectIdentifier ?? "").hasPrefix(prefix) }
                if !related.isEmpty { loan.generatedRules = related }
            }
            try MacDataManagement.registerReferencedCategories(in: context)
            try context.save()
            return result
        } catch {
            context.rollback()
            throw error
        }
    }

    // MacCSV is MainActor-isolated. These fixed POSIX/UTC parsers are never
    // reconfigured after construction or shared with background actors.
    private static let dayParser: DateFormatter = {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX"); day.timeZone = TimeZone(secondsFromGMT: 0)
        day.dateFormat = "yyyy-MM-dd"; day.isLenient = false
        return day
    }()
    private static let isoParser = ISO8601DateFormatter()
    private static let fractionalISOParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func parsedDate(_ value: String, field: String) throws -> Date {
        let day = dayParser
        let datePart = String(value.prefix(10))
        guard datePart.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil,
              let date = day.date(from: datePart), day.string(from: date) == datePart else { throw Failure.invalid(field + " 日期无效") }
        if value == datePart { return date }
        guard value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](?:\\.[0-9]+)?(?:Z|[+-][0-9]{2}:[0-9]{2})$", options: .regularExpression) != nil else { throw Failure.invalid(field + " 需要YYYY-MM-DD或带时区ISO 8601时间") }
        if let date = isoParser.date(from: value) { return date }
        if let date = fractionalISOParser.date(from: value) { return date }
        throw Failure.invalid(field)
    }

    private static func validate(_ sections: [String: CSVImportSectionTable]) throws {
        let numbers: [String: [String]] = [
            "transactions": ["Amount", "OriginalAmount", "BaseAmount", "ExchangeRateToBase"],
            "recurringtransactions": ["Amount", "OriginalAmount", "BaseAmount", "ExchangeRateToBase"],
            "deposits": ["Principal", "OriginalPrincipal", "BasePrincipal", "AnnualInterestRate", "ExpectedInterest", "BaseExpectedInterest", "PrincipalExchangeRateToBase", "InterestExchangeRateToBase"],
            "loans": ["Principal", "BasePrincipal", "AnnualRate", "ExchangeRateToBase", "TotalAmount", "DownPaymentAmount", "DownPaymentPercent"],
            "goals": ["TargetAmount", "CreationNetWorth"],
            "financialprofile": ["InitialAssets", "InitialDebt"], "accounts": ["Balance"], "categories": []]
        let dates: [String: [String]] = ["transactions": ["Date", "CreatedAt", "UpdatedAt"],
            "recurringtransactions": ["NextExecutionDate", "CreatedAt", "UpdatedAt"],
            "deposits": ["StartDate", "MaturityDate", "CreatedAt", "UpdatedAt"],
            "loans": ["StartDate", "CreatedAt", "UpdatedAt"], "goals": ["StartDate", "CreatedAt", "UpdatedAt"],
            "financialprofile": ["CreatedAt", "UpdatedAt"], "categories": ["CreatedAt", "UpdatedAt"], "accounts": ["CreatedAt"]]
        for (key, table) in sections {
            guard let required = numbers[key] else { throw Failure.invalid("Unknown section \(table.sectionTitle)") }
            var seen = Set<UUID>()
            for row in table.rows {
                let v = row.values
                let detail = "\(table.sectionTitle), row \(row.rowIndex)"
                if key == "goals", let precision = v["TargetDatePrecision"], !precision.isEmpty,
                   TargetDatePrecision(rawValue: precision) == nil { throw Failure.invalid(detail + ": target date precision") }
                if key == "goals", let raw = v["TargetDateValue"], !raw.isEmpty {
                    guard let precision = v["TargetDatePrecision"].flatMap(TargetDatePrecision.init(rawValue:)),
                          !(v["Deadline"] ?? "").isEmpty, GoalTargetTime.components(raw, precision: precision) != nil
                    else { throw Failure.invalid(detail + ": target date calendar value") }
                }
                for field in ["IsActive", "NotificationsEnabled", "HasCreditedInterest", "IsInterestManuallyEdited", "IncludesCurrentAssets", "IsAccomplished", "IsPaused"] {
                    if let raw = v[field], !["true", "false", "1", "0", "yes", "no"].contains(raw.lowercased()) {
                        throw Failure.invalid(detail + ": " + field + " 状态无效")
                    }
                }
                for (field, range) in [("ReminderDaysBefore", 0...365), ("ReminderHour", 0...23), ("ReminderMinute", 0...59)] {
                    if let raw = v[field], !raw.isEmpty { guard let value = Int(raw), range.contains(value) else { throw Failure.invalid(detail + ": " + field) } }
                }
                if key != "accounts" {
                    guard let id = UUID(uuidString: v["ID"] ?? "") else { throw Failure.invalid(detail + ": ID") }
                    guard seen.insert(id).inserted else { throw Failure.duplicateID(detail) }
                }
                for field in required {
                    guard let number = Double(v[field] ?? ""), number.isFinite, abs(number) <= (key == "transactions" && field == "ExchangeRateToBase" ? 1e14 : 1e12)
                    else { throw Failure.invalid(detail + ": " + field) }
                }
                for field in dates[key] ?? [] { _ = try parsedDate(v[field] ?? "", field: detail + ": " + field) }
                for field in ["DeletedAt", "Deadline", "LastExecutionDate", "EndDate", "LastInterestPayoutDate", "NextInterestPayoutDate"] {
                    if let value = v[field], !value.isEmpty { _ = try parsedDate(value, field: detail + ": " + field) }
                }
                for field in ["Currency", "OriginalCurrency", "BaseCurrency"] {
                    if let value = v[field] { _ = try MacCurrency.code(value) }
                }
                if ["transactions", "recurringtransactions"].contains(key) {
                    let validType = key == "recurringtransactions"
                        ? ["income", "expense"].contains((v["Type"] ?? "").lowercased())
                        : ["Income", "Expense"].contains(v["Type"] ?? "")
                    guard validType,
                          let original = Double(v["OriginalAmount"] ?? ""), original >= 0,
                          let base = Double(v["BaseAmount"] ?? ""), base >= 0,
                          let rate = Double(v["ExchangeRateToBase"] ?? ""), rate > 0,
                          let source = v["OriginalCurrency"], let book = v["BaseCurrency"]
                    else { throw Failure.invalid(detail + ": transaction snapshot") }
                    if key == "transactions" {
                        do { try MacBankSettlement.validateSavedSnapshot(amount:original,actual:base,source:source,base:book,rate:rate,allowLegacyPrecision:true) }
                        catch { throw Failure.invalid(detail + ": inconsistent exchange snapshot") }
                    } else {
                        let expected = try MacCurrency.snapshot(amount:original,original:source,base:book,rate:rate)
                        guard abs(expected.baseAmount - base) < 0.005 else { throw Failure.invalid(detail + ": inconsistent exchange snapshot") }
                    }
                }
                if key == "recurringtransactions" {
                    guard let interval = Int(v["IntervalValue"] ?? ""), (1...365).contains(interval),
                          RecurringIntervalUnit(rawValue: v["IntervalUnit"] ?? "") != nil
                    else { throw Failure.invalid(detail + ": recurring interval") }
                }
                if key == "loans" {
                    guard let term = Int(v["TermMonths"] ?? ""), (1...600).contains(term),
                          RepaymentMethod(rawValue: v["Method"] ?? "") != nil,
                          let principal = Double(v["Principal"] ?? ""), principal > 0,
                          let annual = Double(v["AnnualRate"] ?? ""), (0...100).contains(annual),
                          let total = Double(v["TotalAmount"] ?? ""), total > 0,
                          let down = Double(v["DownPaymentAmount"] ?? ""), down >= 0,
                          let percent = Double(v["DownPaymentPercent"] ?? ""), (0...100).contains(percent),
                          abs(total - down - principal) < 0.005,
                          let base = Double(v["BasePrincipal"] ?? ""), base > 0,
                          let rate = Double(v["ExchangeRateToBase"] ?? ""), rate > 0, rate <= 1e9,
                          let source = v["Currency"], let book = v["BaseCurrency"]
                    else { throw Failure.invalid(detail + ": loan schedule") }
                    do { try MacBankSettlement.validateSavedSnapshot(amount:principal,actual:base,source:source,base:book,rate:rate,allowLegacyPrecision:true) }
                    catch { throw Failure.invalid(detail + ": inconsistent loan snapshot") }
                }
                if key == "deposits" {
                    guard let principal = Double(v["Principal"] ?? ""), principal > 0,
                          let original = Double(v["OriginalPrincipal"] ?? ""), original == principal,
                          let base = Double(v["BasePrincipal"] ?? ""), base > 0,
                          let annual = Double(v["AnnualInterestRate"] ?? ""), (0...100).contains(annual),
                          let interest = Double(v["ExpectedInterest"] ?? ""), interest >= 0,
                          let baseInterest = Double(v["BaseExpectedInterest"] ?? ""), baseInterest >= 0,
                          let principalRate = Double(v["PrincipalExchangeRateToBase"] ?? ""), principalRate > 0, principalRate <= 1e9,
                          let interestRate = Double(v["InterestExchangeRateToBase"] ?? ""), interestRate > 0, interestRate <= 1e9,
                          let source = v["OriginalCurrency"], source == v["Currency"], let book = v["BaseCurrency"],
                          DepositInterestSettlementMode(rawValue: v["InterestSettlementMode"] ?? "") != nil,
                          try parsedDate(v["StartDate"] ?? "", field: detail) < parsedDate(v["MaturityDate"] ?? "", field: detail)
                    else { throw Failure.invalid(detail + ": deposit terms") }
                    do {
                        try MacBankSettlement.validateSavedSnapshot(amount:principal,actual:base,source:source,base:book,rate:principalRate,allowLegacyPrecision:true)
                        try MacBankSettlement.validateSavedSnapshot(amount:interest,actual:baseInterest,source:source,base:book,rate:interestRate,allowLegacyPrecision:true)
                    } catch { throw Failure.invalid(detail + ": inconsistent deposit snapshot") }
                }
                if key == "goals", (Double(v["TargetAmount"] ?? "") ?? 0) <= 0 {
                    throw Failure.invalid(detail + ": target amount must be positive")
                }
                if key == "financialprofile", (Double(v["InitialAssets"] ?? "") ?? -1) < 0 {
                    throw Failure.invalid(detail + ": initial assets must be nonnegative")
                }
            }
        }
    }
}
