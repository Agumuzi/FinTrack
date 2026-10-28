import Foundation

nonisolated enum MacCSVKind: String, CaseIterable, Identifiable {
    case transactions, deposits, loans, recurring
    nonisolated var id: String { rawValue }
    var title: String {
        switch self { case .transactions: "记账"; case .deposits: "存款"; case .loans: "贷款"; case .recurring: "周期记账" }
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
        let full = guide(bookCurrency: bookCurrency)
        func between(_ start: String, _ end: String) -> String {
            String(full.components(separatedBy: start)[1].components(separatedBy: end)[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let headings = ["记账表专有规则", "存款表专有规则", "贷款表专有规则", "周期记账表专有规则", "四类示例"]
        let index = MacCSVKind.allCases.firstIndex(of: kind)!
        let specific = between(headings[index], headings[index + 1])
        let labels = ["记账：", "存款：", "贷款：", "周期记账：", "导入与导出"]
        let examples = full.components(separatedBy: "四类示例（仅说明，不放入空白模板；均为虚构数据）")[1]
        let example = examples.components(separatedBy: labels[index])[1].components(separatedBy: labels[index + 1])[0].trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        给 AI：这是 FinTrack「\(kind.title)」专用空白 CSV 模板（v1）。
        用户只需提供原始账本和本文件，无需另附格式说明或指令。原始账本可以是 Excel、CSV、PDF、照片、扫描件、文本或其他可读取资料；先识别明细，无法读取或有歧义时请向用户确认。
        只整理「\(kind.title)」，不能混入其他三类数据。原表中的其他类型和无法确认的数据单独列为待处理清单，不能擅自改作本类型。
        当前账本本位币：\(bookCurrency)。不得自行更换本位币、猜测币种或历史汇率。

        本文件结构
        第一条 CSV 记录以 #FinTrackTemplate 开头，依次保存版本、数据类型和本位币；第二条记录以 #AIInstructions 开头，其第二格就是本段说明。两条说明记录均不是财务数据，不能作为表头、交易或规则导入。第三条记录才是以下正式表头：
        \(kind.headers.joined(separator: ","))
        正式表头的全部列必须保留，大小写一致，顺序可调，不得新增、遗漏或重复。请将确认的数据填写在正式表头之后。可原样保留这两条说明记录，也可输出只有正式表头和明细的干净 CSV，软件均支持；不得修改版本、类型、本位币标记，不要把原始账本嵌入说明区。说明中的示例也不是用户数据。

        通用规则与共用字段
        \(between("通用文件规则", "记账表专有规则"))

        \(kind.title)专有规则
        \(specific)

        本类型示例（虚构，仅理解格式，不要导入）
        \(example)

        输出要求
        请按以上全部规则生成一个可下载的「\(kind.title)」CSV文件；保留全部英文列名。一行一条确认的本类型记录，不加入标题、合计、小计、余额、重复展示或Markdown围栏。不要把规则再变成已发生收支，不擅自合并两条真实相同金额的记录。
        必填值缺失、原始资料无法读取、OCR文字或日期有歧义、币种/汇率/收支方向/计息或还款方式无法确认时，先问用户；不得猜测、编造、补0或静默丢行。待确认项单独列清单，不混入CSV。
        每条新记录生成有效UUID，重新转换时复用已有ID；外部流水号需保留稳定映射。按币种核对金额或本金合计，另行报告原始明细数、输出数、排除项及待确认项，报告不能混进CSV。
        软件先校验整文件再预览，确认后合并；相同ID跳过且不覆盖，新ID视为新记录。导入动作不会生成历史收据；新周期规则默认暂停。不要改动软件原格式数据导出的系统字段或把它套进简化模板，完整历史恢复使用原生备份。
        """
    }
    static func guide(bookCurrency: String) -> String {
        let tables = MacCSVKind.allCases.map { "\($0.title) · \($0.templateName)\n\($0.headers.joined(separator: ","))" }.joined(separator: "\n\n")
        return """
        FinTrack 独立 CSV 格式 v1 / 账本整理指令

        当前账本本位币：\(bookCurrency)
        每个空白 CSV 内已包含对应类型的 AI 指令、字段规则和本位币；只需将原始账本与该模板交给 AI，无需单独说明文件。CSV 没有工作表；记账、存款、贷款、周期记账分别保存为四个文件。在软件中先选择数据类型，再导入对应文件，不得混用。

        四类表头（全部列须保留，大小写一致，顺序可调整）
        \(tables)

        通用文件规则
        UTF-8，可带 BOM；英文逗号分隔；LF/CRLF 换行；模板前两条CSV记录为带标记的说明区，正式表头为第三条；AI输出也可省去说明区、直接以列名开头。明细一行一条对应类型的数据。禁止重复、增加、遗漏列；不得加入标题、合计、示例、公式或 Markdown 围栏。只有表头的模板不导入任何记录。
        单元格含逗号、双引号或换行时，整格用双引号包围，内部双引号写成两个双引号。空值仍保留分隔符。文件上限 50,000,000 字节。

        所有表共用字段
        ID：必填，有效 UUID；例如 11111111-1111-4111-8111-111111111111。每条新记录生成一个，同一记录重导时保持原 ID。同文件重复 ID 阻止整批导入，账本中已有 ID 跳过且不覆盖。重新生成 ID 会产生新记录。
        Currency：必填，原始货币的三位大写字母代码，例如 USD、CNY、RUB、EUR。不能填货币符号或中文名。
        BaseCurrency：必填，每行填写 \(bookCurrency)，须与导入时账本本位币一致。改变本位币后须重新核实所有换算值。
        ExchangeRate：原币到本位币的正数汇率，1 Currency = ExchangeRate BaseCurrency；不是每100单位报价。同币可空或填1，异币必填；最多六位小数，最大1000000000。不得猜测或用今日汇率代替历史汇率；软件不会联网补全。
        Amount / Principal：原币金额 / 原币本金，必填正数，最多两位小数且不超过1000000000000。英文小数点，不带千位分隔符、正负号、货币符号或科学计数法。换算为本币时四舍五入到两位，不得溢出上限或舍入为0。
        Note：选填，自由备注；账户信息可明确附于此。不允许填写软件内部的 [FT 开头标记。
        Date / StartDate / MaturityDate / NextExecutionDate / EndDate：YYYY-MM-DD 或带明确时区的ISO 8601时间，例如2026-10-01T12:30:00+03:00；不接受Excel日期序号、斜线日期和无时区时间。纯日期按UTC零点保存，带时区时间按其实际时间点保存。
        Title / BankName / Category：必填非空名称，最多100字符，分类只写名称不加图标；导入提交时会登记所引用的分类，收入与支出同名分类分别管理。

        记账表专有规则
        Date：交易发生日期，必填。
        Type：仅 Income（收入）或 Expense（支出），大小写一致。Amount为原币金额。仅导入已经发生的收入或支出；转账、余额、期初资产、存贷款本金和规则定义不能猜作收支。
        负数、退款必须根据原始证据明确收支方向，再填写正数；不能直接取绝对值。

        存款表专有规则
        BankName：银行名称。Principal：原币本金。AnnualInterestRate：必填，0到100的年化百分数，最多四位小数，3.5表示3.5%，不能写0.035来表示3.5%。
        StartDate：起存日；MaturityDate：到期日，必须晚于起存日。
        InterestSettlementMode：仅 At Maturity（到期付息）、Monthly（按月付息）、Monthly Compound（按月复利），须与原表合同一致。
        ExpectedInterest：选填，原币预计总利息，非负且最多两位小数；空白时软件按本身的存期/计息规则计算，明确填写时按手工预计利息保留，并沿用软件规则反推匹配的年化利率。
        InterestExchangeRate：预计利息到本位币的汇率，格式同ExchangeRate；异币必填，同币可空或1。与本金汇率独立，禁止猜测。
        导入为新的受管理存款，保留本金和预计利息；不凭表格伪造已付利息或续存历史，导入动作不生成收支。

        贷款表专有规则
        Title：贷款名称。Principal：实际贷款原币本金，不是含首付总价。AnnualRate：必填，0到100的年化百分数，最多四位小数。
        TermMonths：必填，1到600的整数，总期数/月数。
        Method：仅 Equal Payment（等额本息）、Equal Principal（等额本金）、Interest Only（先息后本）。
        StartDate：第一期还款日期，不是合同签订日。Category：还款分类。
        此模板定义新的完整还款计划，不表示已有任何一期已还款；不猜测历史还款、余额或首付。若原表只有剩余余额或不完整的已还历史，请先向用户确认，不直接据此生成新完整计划。完整历史恢复使用原生备份或原格式数据文件。

        周期记账表专有规则
        Title：规则名称。Type：Income或Expense。Amount：每期原币金额，不能填写多期合计。
        IntervalValue：1到365的整数。IntervalUnit：仅 day、week、month、year（小写）。例如每2个月为2,month。
        NextExecutionDate：下一次待执行的日期，必填。EndDate：选填，若填写不能早于下一次日期。
        导入为新的受管理规则，默认暂停，核对下一次日期后在周期页面启用；不自动制造过去的执行记录，也不直接生成交易。

        四类示例（仅说明，不放入空白模板；均为虚构数据）
        记账：
        ID,Date,Type,Category,Currency,Amount,BaseCurrency,ExchangeRate,Note
        11111111-1111-4111-8111-111111111111,2026-10-01,Expense,餐饮,\(bookCurrency),35.50,\(bookCurrency),1,"午餐,咖啡"
        存款：
        ID,BankName,Principal,Currency,BaseCurrency,ExchangeRate,AnnualInterestRate,ExpectedInterest,InterestExchangeRate,StartDate,MaturityDate,InterestSettlementMode,Note
        22222222-2222-4222-8222-222222222222,示例银行,1000,\(bookCurrency),\(bookCurrency),1,3.5,,1,2026-10-01,2027-10-01,At Maturity,虚构新存款
        贷款：
        ID,Title,Principal,Currency,BaseCurrency,ExchangeRate,AnnualRate,TermMonths,Method,StartDate,Category,Note
        33333333-3333-4333-8333-333333333333,示例贷款,12000,\(bookCurrency),\(bookCurrency),1,3.5,12,Equal Payment,2027-01-01,还款,虚构新计划
        周期记账：
        ID,Title,Type,Category,Currency,Amount,BaseCurrency,ExchangeRate,IntervalValue,IntervalUnit,NextExecutionDate,EndDate,Note
        44444444-4444-4444-8444-444444444444,示例月租,Expense,房租,\(bookCurrency),1000,\(bookCurrency),1,1,month,2027-01-01,,虚构新规则

        导入与导出
        选择类型后，空白模板和数据导出都只包含该类型的未删除数据。数据导出为软件原格式的单表CSV，额外保留原币/本币快照、状态、时间戳与系统关联字段，可原样重导；它与供AI建立新记录的简化v1模板用途不同。不要删改这些系统字段或把原格式数据套入简化模板，以免丢失历史状态。
        旧版多分区完整CSV可通过单独的兼容入口导入；选定类型的入口拒绝混合文件。完整恢复仍使用.fintrack备份。
        导入先校验整文件，再预览，确认后合并；错误会阻止本批保存。预览显示类型和前五条记录，确认前核对金额、币种和汇率。已有ID跳过，不更新旧记录。旧普通收支CSV仍兼容，但无稳定ID时重复导入可能重复入账。

        可直接交给AI的转换指令
        请分析附带的原始账本（Excel、PDF、图片、文本等），根据以上FinTrack v1规则分别生成记账、存款、贷款、周期记账CSV；只生成原表确有数据的文件，每类一个可下载.csv，严禁混表。保留相应全部英文表头。
        先区分已发生交易与规则定义，排除合计、小计、余额、重复展示，不能把存款或贷款再算作收入/支出，也不要擅自合并两笔真实相同金额的记录。账户、预算、目标和未知类型单独列为不支持项。
        缺失必填值、历史汇率、计息方式、还款方式、收支方向或日期有歧义时，先向我确认；不得猜测、编造、补0或静默丢行。待确认项单独列清单，不能混入CSV。
        每条新记录生成有效UUID；已有外部流水号需保留稳定映射，重新转换复用ID。按类型报告原始明细数、输出数、排除及待确认数，按币种核对金额/本金合计。输出文件中不要附解释和Markdown围栏。
        """
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
        guard !input.contains("\0") else { throw MacCSV.Failure.invalid("文件含有空字符") }
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
                guard !closed && c != "\"" else { throw MacCSV.Failure.invalid("第 \(line) 行：双引号位置不正确") }
                field.append(c)
            }
            index += 1
        }
        guard !quoted else { throw MacCSV.Failure.invalid("第 \(startLine) 行：双引号未闭合") }
        if !field.isEmpty || !cells.isEmpty || closed { appendRecord() }
        guard !result.isEmpty else { throw MacCSV.Failure.empty }
        if result[0].cells.first == "#FinTrackTemplate" {
            let marker = result[0].cells
            guard marker.count >= 4, marker[1] == "1", let kind = MacCSVKind(rawValue: marker[2]),
                  marker.count == kind.headers.count, marker.dropFirst(4).allSatisfy({ $0.isEmpty }),
                  marker[3] == marker[3].uppercased(), (try? MacFXPair(base: marker[3], quote: marker[3]).base) == marker[3],
                  result.count >= 3 else { throw MacCSV.Failure.invalid("模板版本、类型、本位币或说明区结构无效") }
            let instructions = result[1].cells
            guard instructions.count == kind.headers.count, instructions[0] == "#AIInstructions",
                  !instructions[1].isEmpty, instructions.dropFirst(2).allSatisfy({ $0.isEmpty }) else {
                throw MacCSV.Failure.invalid("模板AI说明区不完整；请重新导出模板")
            }
            templateKind = kind; templateBaseCurrency = marker[3]
            result.removeFirst(2)
            guard Set(result[0].cells) == Set(kind.headers), result[0].cells.count == kind.headers.count else {
                throw MacCSV.Failure.invalid("模板正式表头与\(kind.title)类型不一致")
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
                    throw MacCSV.Failure.invalid("第 \(row.line) 行：分区标记或上一分区表头不完整")
                }
                let key = row.cells[1].lowercased().filter { !$0.isWhitespace }
                guard sections.insert(key).inserted else { throw MacCSV.Failure.invalid("第 \(row.line) 行：重复分区 \(row.cells[1])") }
                needsHeader = true
            } else if needsHeader || (!isSectioned && index == 0) {
                headers = row.cells
                guard headers.allSatisfy({ !$0.isEmpty }), Set(headers.map { $0.lowercased() }).count == headers.count else {
                    throw MacCSV.Failure.invalid("第 \(row.line) 行：列名为空或重复")
                }
                needsHeader = false
            } else {
                guard row.cells.count == headers.count else {
                    throw MacCSV.Failure.invalid("第 \(row.line) 行：应有 \(headers.count) 列，实际 \(row.cells.count) 列；请检查逗号和引号")
                }
            }
        }
        guard !needsHeader else { throw MacCSV.Failure.invalid("最后一个分区缺少表头") }
    }
}
