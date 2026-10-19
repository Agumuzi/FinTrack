import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct MacDepositsView: View {
    let bookCurrency: String?
    @Environment(\.modelContext) private var context
    @Query private var deposits: [DepositRecord]
    @Query private var transactions: [Transaction]
    @State private var search = ""
    @State private var status: MacDepositsData.Status?
    @State private var bank: String?
    @State private var currency: String?
    @State private var sort = MacDepositsData.Sort.maturity
    @State private var selectedID: UUID?
    @State private var showsDetails = false
    @State private var showsNew = false
    @State private var editing: MacFinanceRecord?
    @State private var schedule: DepositRecord?
    @State private var reviewing: MacFinanceRecord?
    @State private var removing: DepositRecord?
    @State private var confirming: DepositRecord?
    @State private var posting = false
    @State private var error: String?
    @State private var message: String?
    @State private var logoRevision = 0
    @State private var cropInput: MacBankLogos.CropInput?
    @State private var now = Date()
    private var active: [DepositRecord] { deposits.filter { $0.deletedAt == nil } }
    private var visible: [DepositRecord] {
        MacDepositsData.filtered(active, search: search, status: status, bank: bank, currency: currency, sort: sort, now: now)
    }
    private var selected: DepositRecord? { visible.first { $0.id == selectedID } }
    private var banks: [String] { Array(Set(active.map(\.bankName))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    private var currencies: [String] { Array(Set(active.map(\.originalCurrency))).sorted() }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= MacUI.space(950)
            let filterWidth = MacUI.filterColumnWidth(available: geometry.size.width, wide: wide)
            HStack(spacing: MacUI.space(0)) {
                filters.frame(width: filterWidth)
                Divider()
                list(wide: wide).frame(width: wide ? MacUI.space(310) : nil).frame(maxWidth: wide ? nil : .infinity, maxHeight: .infinity)
                if wide {
                    Divider()
                    if let selected { presentedDetail(selected, compact: false).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else { ContentUnavailableView("选择一笔存款", systemImage: "building.columns", description: Text("在列表中查看本金、期限与结息记录。")).frame(maxWidth: .infinity) }
                }
            }
            .sheet(isPresented: $showsDetails) {
                if !wide, let selected {
                    VStack(spacing: MacUI.space(0)) {
                        HStack { Text("存款详情").appFont(.section, weight: .semibold); Spacer(); Button("关闭") { showsDetails = false }.accessibilityIdentifier("depositCloseDetails") }.appPadding(18)
                        Divider(); presentedDetail(selected, compact: true)
                    }.appPanel(width: 560, height: 670)
                }
            }
        }
        .onAppear { selectedID = visible.first?.id }
        .onChange(of: visible.map(\.id)) { _, ids in
            if !ids.contains(selectedID ?? UUID()) { selectedID = ids.first; showsDetails = false }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
        .sheet(isPresented: $showsNew) {
            if let bookCurrency { MacFinanceEditor(panel: .deposits, currency: bookCurrency) { saved() } }
        }
    }

    private func presentedDetail(_ deposit: DepositRecord, compact: Bool) -> some View {
        detail(deposit, compact: compact)
        .sheet(item: $cropInput) { input in
            MacBankLogoCropView(input: input) { logoRevision += 1; cropInput = nil }
        }
        .sheet(item: $schedule) { MacDepositScheduleView(deposit: $0) }
        .sheet(item: $editing) { record in
            if let bookCurrency { MacFinanceEditor(panel: .deposits, currency: bookCurrency, existing: record) { saved() } }
        }
        .sheet(item: $reviewing) { MacFinanceReviewView(record: $0) }
        .sheet(item: $removing) { deposit in
            VStack(alignment: .leading, spacing: MacUI.space(18)) {
                Text("移除这笔存款？").appFont(.dialogTitle, weight: .semibold)
                Text(deposit.bankName)
                Text("已有结息账目会保留。这笔存款将不再出现在列表中，也不再执行计划。")
                HStack { Spacer(); Button("取消") { removing = nil }.accessibilityIdentifier("depositCancelRemove")
                    Button("确认移除", role: .destructive) {
                        do { try MacFinanceEditing.retire(.deposit(deposit), in: context); removing = nil; saved() }
                        catch { self.error = MacLocalization.error(error) }
                    }.accessibilityIdentifier("confirmRemoveFinance")
                }
            }.appPadding(24).appDialog(width: 500)
        }
        .sheet(item: $confirming) { deposit in
            VStack(alignment: .leading, spacing: MacUI.space(18)) {
                Text("确认已收到银行利息？").appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("confirmDepositInterestTitle")
                Text(deposit.bankName).appFont(.section, weight: .semibold)
                Text("确认后，将到期未入账的利息记为收入。本金保留在存款记录中；请以银行实际到账为准。")
                if deposit.originalCurrency != bookCurrency { Text("外币利息按每次结息日期获取汇率，保留独立的记账快照。").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                HStack { Spacer(); Button("取消") { confirming = nil }.accessibilityIdentifier("cancelDepositInterest")
                    Button("确认收到利息") { confirming = nil; post(deposit) }.accessibilityIdentifier("confirmDepositInterest")
                }
            }.appPadding(24).appDialog(width: 500)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: MacUI.space(15)) {
            HStack {
                Text("筛选").appFont(.section, weight: .semibold); Spacer()
                Button { showsNew = true } label: { Image(systemName: "plus").frame(width: MacUI.space(24), height: MacUI.space(24)) }
                    .buttonStyle(.plain).help("新增存款").accessibilityLabel("新增存款").accessibilityIdentifier("financeAdd").disabled(bookCurrency == nil || posting)
            }
            TextField("搜索银行或备注", text: $search).textFieldStyle(.roundedBorder).accessibilityIdentifier("depositSearch")
            ScrollView {
                VStack(alignment: .leading, spacing: MacUI.space(7)) {
                    filterButton("全部存款", count: active.count, selected: status == nil, icon: "tray", id: "depositAll") { status = nil }
                    ForEach(MacDepositsData.Status.allCases) { item in
                        filterButton(item == .soon ? "即将到期（30天内）" : item.rawValue,
                            count: active.filter { MacDepositsData.status($0, now: now) == item }.count,
                            selected: status == item, icon: item == .matured ? "calendar.badge.exclamationmark" : "clock", id: "depositStatus-\(item.rawValue)") { status = item }
                    }
                    Divider().appPadding(.vertical, 8)
                    Text("按银行").appFont(.caption, weight: .semibold).foregroundStyle(.secondary).appPadding(.leading, 8)
                    filterButton("全部银行", selected: bank == nil, id: "depositBankAll") { bank = nil }
                    ForEach(banks, id: \.self) { name in
                        filterButton(name, count: active.filter { $0.bankName == name }.count, selected: bank == name, id: "depositBank-\(name)") { bank = name }
                    }
                    Divider().appPadding(.vertical, 8)
                    Text("按币种").appFont(.caption, weight: .semibold).foregroundStyle(.secondary).appPadding(.leading, 8)
                    filterButton("全部币种", selected: currency == nil, id: "depositCurrencyAll") { currency = nil }
                    ForEach(currencies, id: \.self) { code in
                        filterButton(code, count: active.filter { $0.originalCurrency == code }.count, selected: currency == code, id: "depositCurrency-\(code)") { currency = code }
                    }
                }
            }
            Button("重置筛选") { search = ""; status = nil; bank = nil; currency = nil }.buttonStyle(.plain)
                .foregroundStyle(.secondary).accessibilityIdentifier("depositReset")
        }.appPadding(18).background(MacOverviewStyle.filters)
    }
    private func filterButton(_ title: String, count: Int? = nil, selected: Bool, icon: String? = nil, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: MacUI.space(7)) {
                if let icon { Image(systemName: icon).frame(width: MacUI.space(16)) }
                Text(title).lineLimit(2); Spacer(minLength: 2)
                if let count { Text("\(count)").monospacedDigit().foregroundStyle(.secondary) }
            }.appFont(.caption, weight: .regular, design: .default).appPadding(.horizontal, 9).appPadding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .macFinanceFilterRow(selected: selected)
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
    private func list(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(14)) {
            HStack { Text("\(visible.count) 笔存款").appFont(.section, weight: .semibold).accessibilityIdentifier("depositCount"); Spacer()
                if !wide, selected != nil { Button { showsDetails = true } label: { Image(systemName: "sidebar.right") }.help("查看详情").accessibilityLabel("查看详情").accessibilityIdentifier("depositOpenDetails") }
            }
            Picker("排序", selection: $sort) { ForEach(MacDepositsData.Sort.allCases) { Text($0.rawValue).tag($0) } }
                .labelsHidden().accessibilityIdentifier("depositSort")
            if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red).accessibilityIdentifier("financeActionError") }
            if let message { Text(message).appFont(.caption, weight: .regular).foregroundStyle(MacOverviewStyle.income).accessibilityIdentifier("financeActionMessage") }
            if bookCurrency == nil { Text("账本包含不同本位币，请在设置中核对后再新增或编辑。").appFont(.caption, weight: .regular).foregroundStyle(.orange) }
            if visible.isEmpty {
                ContentUnavailableView(active.isEmpty ? "还没有存款" : "没有匹配的存款", systemImage: "building.columns", description: Text(active.isEmpty ? "点击左上方 + 新增一笔存款。" : "试试其他筛选条件。"))
                    .accessibilityIdentifier("depositsEmptyState").frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: MacUI.space(10)) {
                        ForEach(visible, id: \.id) { deposit in
                            Button { selectedID = deposit.id; if !wide { showsDetails = true } } label: { row(deposit) }
                                .buttonStyle(.plain).accessibilityIdentifier("depositRow-\(deposit.bankName)")
                        }
                    }.appPadding(1)
                }
            }
        }.appPadding(18).background(MacOverviewStyle.canvas)
    }
    private func row(_ deposit: DepositRecord) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(12)) {
            HStack(alignment: .top, spacing: MacUI.space(10)) {
                MacBankIcon(bank: deposit.bankName, revision: logoRevision)
                VStack(alignment: .leading, spacing: MacUI.space(4)) { Text(deposit.bankName).appFont(.section, weight: .semibold).lineLimit(2); Text(MacDepositsData.mode(deposit)).appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            Text("\(MacOverviewStyle.money(deposit.originalPrincipal)) \(deposit.originalCurrency)").appFont(.section, weight: .semibold, design: .default).monospacedDigit()
            HStack { Text("年利率 \(deposit.annualInterestRate.formatted(.number.precision(.fractionLength(0...4))))%").appFont(.caption, weight: .regular); Spacer(); badge(deposit) }
            Text("到期 \(MacDateDisplay.string(deposit.maturityDate))").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
        }.appPadding(14).frame(maxWidth: .infinity, alignment: .leading)
            .macFinanceSelectableRow(selected: selectedID == deposit.id)
    }
    private func badge(_ deposit: DepositRecord) -> some View {
        let status = MacDepositsData.status(deposit, now: now)
        let color: Color = status == .soon ? .orange : (status == .active ? MacOverviewStyle.income : .secondary)
        return Text(status.rawValue).appFont(.caption, weight: .regular).foregroundStyle(color).appPadding(.horizontal, 8).appPadding(.vertical, 4)
            .background(color.opacity(0.1), in: Capsule())
    }
    private func detail(_ deposit: DepositRecord, compact: Bool) -> some View {
        let timing = MacDepositsData.timing(deposit, now: now)
        let audit = MacDepositsData.audit(deposit, transactions: transactions)
        return ScrollView {
            VStack(alignment: .leading, spacing: MacUI.space(16)) {
                HStack(alignment: .top, spacing: MacUI.space(12)) {
                    MacBankIcon(bank: deposit.bankName, size: 46, revision: logoRevision)
                    VStack(alignment: .leading, spacing: MacUI.space(4)) { Text(deposit.bankName).appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("depositDetailTitle"); Text(MacDepositsData.mode(deposit)).foregroundStyle(.secondary).appFont(.caption, weight: .regular) }
                    Spacer(); badge(deposit)
                }
                HStack {
                    Button("编辑", systemImage: "pencil") { editing = .deposit(deposit) }.accessibilityIdentifier("editFinance-\(deposit.id.uuidString)").disabled(bookCurrency == nil || posting)
                    Menu {
                        Button("选择银行图标…") { chooseLogo(deposit.bankName) }.accessibilityIdentifier("depositChooseLogo")
                        Button("恢复默认图标") { do { try MacBankLogos.reset(deposit.bankName); logoRevision += 1 } catch { self.error = error.localizedDescription } }.accessibilityIdentifier("depositResetLogo")
                        Divider()
                        Button("移除存款…", role: .destructive) { removing = deposit }.accessibilityIdentifier("depositRemove")
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: MacUI.space(35)).accessibilityIdentifier("depositMore").disabled(posting)
                    Spacer()
                }
                card {
                    Text("\(MacOverviewStyle.money(deposit.originalPrincipal)) \(deposit.originalCurrency)").appFont(.amount, weight: .semibold, design: .default).monospacedDigit().textSelection(.enabled).accessibilityIdentifier("depositPrincipal").id("principal-\(deposit.id)-\(deposit.originalPrincipal)")
                    Text("本金 · 原币").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    Divider().appPadding(.vertical, 6)
                    HStack(alignment: .top) {
                        metric("年利率", "\(deposit.annualInterestRate.formatted(.number.precision(.fractionLength(0...4))))%")
                        Spacer(); metric("存期", "\(timing.total) 天")
                        Spacer(); metric("预计总利息", "\(MacOverviewStyle.money(deposit.expectedInterest)) \(deposit.originalCurrency)", id: "depositExpectedInterest")
                    }
                    if deposit.isInterestManuallyEdited { Text("预计利息按手动输入金额保存。").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                }
                card {
                    HStack { metric("开始日期", MacDateDisplay.string(deposit.startDate)); Spacer(); metric("到期日期", MacDateDisplay.string(deposit.maturityDate)) }
                    ProgressView(value: timing.progress).tint(MacOverviewStyle.accent).appPadding(.vertical, 5)
                    HStack { Text(now < deposit.startDate ? "尚未起息" : "已存 \(timing.elapsed) 天"); Spacer(); Text(timing.remaining > 0 ? "距离到期 \(timing.remaining) 天" : "已到期") }.appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                }
                card {
                    Text("结息与入账").appFont(.section, weight: .semibold)
                    HStack(alignment: .top) {
                        metric("已核验入账利息", "\(MacOverviewStyle.money(audit.total)) \(deposit.originalCurrency)", id: "depositPostedInterest")
                        Spacer(); metric("结息状态", deposit.hasCreditedInterest ? "已完成结息" : (deposit.isActive ? "尚未完成" : "已结束"), id: "depositSettlementStatus")
                    }
                    if let next = deposit.nextInterestPayoutDate, deposit.isActive { Text("下一计划结息：\(MacDateDisplay.string(next))").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                    if audit.unverifiedCount > 0 { Label("\(audit.unverifiedCount) 条结息记录待核对，未计入合计。", systemImage: "exclamationmark.triangle").appFont(.caption, weight: .regular).foregroundStyle(.orange).accessibilityIdentifier("depositReceiptWarning") }
                    if !MacDepositSettlement.isManaged(deposit) {
                        Text("旧记录的历史到账需人工核对，不能仅凭到期状态推断利息已收到。").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                        Button("核对历史结息") { reviewing = .deposit(deposit) }.accessibilityIdentifier("reviewFinance-\(deposit.id.uuidString)").disabled(bookCurrency == nil || posting)
                    } else if !deposit.hasCreditedInterest {
                        Button(posting ? "正在记账…" : "确认收到到期利息", systemImage: "checkmark.circle") { confirming = deposit }
                            .accessibilityIdentifier("postDepositInterest-\(deposit.id.uuidString)")
                            .disabled(posting || bookCurrency == nil || !MacDepositSettlement.isEligible(deposit, now: now))
                    }
                    if deposit.hasCreditedInterest || deposit.lastInterestPayoutDate != nil {
                        Text("已有结息后，本金、利率和日期等关键参数受保护；仍可修改银行名称和备注。").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    }
                }
                card {
                    Text("结息记录").appFont(.section, weight: .semibold)
                    if audit.receipts.isEmpty { Text("暂无可核验的利息入账记录").appFont(.body, weight: .regular).foregroundStyle(.secondary) }
                    else {
                        HStack { Text("日期"); Spacer(); Text("已到账 · 原币") }.appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                        ForEach(audit.receipts, id: \.id) { receipt in
                            Divider()
                            HStack { Text(MacDateDisplay.string(receipt.date)); Spacer(); Text("+\(MacOverviewStyle.money(receipt.originalAmount)) \(receipt.originalCurrency)").monospacedDigit().foregroundStyle(MacOverviewStyle.income) }.appFont(.body, weight: .regular)
                            if receipt.originalCurrency != receipt.baseCurrencyCode {
                                Text("记账 \(MacOverviewStyle.money(receipt.baseAmount)) \(receipt.baseCurrencyCode) · 汇率 \(receipt.exchangeRateToBase.formatted(.number.precision(.fractionLength(0...8))))").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                card {
                    Text("结息计划").appFont(.section, weight: .semibold)
                    Text("预计金额尚未代表实际到账。").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    let rows = MacDepositScheduleView.rows(for: deposit)
                    ForEach(Array(rows.prefix(12))) { row in
                        HStack { Text(MacDateDisplay.string(row.date)); Spacer(); Text("\(MacOverviewStyle.money(row.interest)) \(deposit.originalCurrency)").monospacedDigit() }.appFont(.body, weight: .regular)
                        if row.id != rows.prefix(12).last?.id { Divider() }
                    }
                }
                Button("查看完整结息计划") { schedule = deposit }.accessibilityIdentifier("depositFullSchedule")
                if deposit.originalCurrency != deposit.baseCurrencyCode {
                    card {
                        Text("本金记账快照").appFont(.section, weight: .semibold)
                        Text("\(MacOverviewStyle.money(deposit.basePrincipal)) \(deposit.baseCurrencyCode)").monospacedDigit().accessibilityIdentifier("depositBookPrincipal")
                        Text("保存汇率：\(deposit.principalExchangeRateToBase.formatted(.number.precision(.fractionLength(0...8))))").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    }
                }
                card { Text("备注").appFont(.section, weight: .semibold); Text(MacFinanceNotes.visible(deposit.note).isEmpty ? "暂无备注" : MacFinanceNotes.visible(deposit.note)).foregroundStyle(.secondary).textSelection(.enabled) }
            }.appPadding(compact ? 18 : 24)
        }.background(MacOverviewStyle.canvas).accessibilityIdentifier("depositDetailScroll").id(deposit.id)
    }
    private func metric(_ title: String, _ value: String, id: String = "") -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(7)) {
            Text(value).appFont(.body, weight: .semibold, design: .default).monospacedDigit().textSelection(.enabled).accessibilityIdentifier(id).id(value)
            Text(title).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
        }
    }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(12), content: content).appPadding(18).frame(maxWidth: .infinity, alignment: .leading)
            .macFinanceDetailCard()
    }
    private func saved() {
        error = nil; message = "已保存"; now = Date()
        Task { try? await MacNotifications.schedule(in: context) }
    }
    private func post(_ deposit: DepositRecord) {
        guard let bookCurrency, !posting else { return }
        posting = true; error = nil; message = nil
        Task { @MainActor in
            defer { posting = false }
            do {
                let result = try await MacAutomaticPosting.post(deposit, now: Date(), book: bookCurrency, in: context)
                message = "已记录 \(result.receipts) 笔利息，共 \(MacOverviewStyle.money(result.totalInterest)) \(deposit.originalCurrency)"
                now = Date(); try? await MacNotifications.schedule(in: context)
            } catch { self.error = MacLocalization.error(error) }
        }
    }
    private func chooseLogo(_ bank: String) {
        do { cropInput = try MacBankLogos.select(for: bank); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
