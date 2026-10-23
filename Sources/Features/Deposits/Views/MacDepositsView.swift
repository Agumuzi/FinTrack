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
    @State private var copying: DepositRecord?
    @State private var reconciling: Transaction?
    @AppStorage("v13_deposit_single_list_width", store: MacPreferences.defaults) private var singleListWidth = 340.0
    @AppStorage("v13_deposit_columns", store: MacPreferences.defaults) private var listColumns = 1

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
    @AppStorage("v13_deposit_double_list_width", store: MacPreferences.defaults) private var doubleListWidth = 580.0
    private var listWidth: Double { listColumns == 2 ? doubleListWidth : singleListWidth }
    private var widthBinding: Binding<Double> { Binding(get: { listWidth }, set: { if listColumns == 2 { doubleListWidth = $0 } else { singleListWidth = $0 } }) }
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
                let maximum = max(300, Double(geometry.size.width - filterWidth - 340))
                list(wide: wide).frame(width: wide ? min(max(300, listWidth), maximum) : nil).frame(maxWidth: wide ? nil : .infinity, maxHeight: .infinity)
                if wide {
                    MacFinanceListDivider(width: widthBinding, maximum: maximum)
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
        .overlay(alignment: .bottomTrailing) {
            Button { showsNew = true } label: { Image(systemName: "plus").appIconFont(22, weight: .semibold).foregroundStyle(.white).frame(width: 46, height: 46).background(MacUI.accent, in: Circle()).contentShape(Circle()) }
                .buttonStyle(.plain).help("新建存款").accessibilityLabel("新建存款").accessibilityIdentifier("depositQuickAdd").disabled(bookCurrency == nil || posting).padding(22)
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
        .sheet(item: $copying) { source in if let bookCurrency { MacFinanceEditor(panel: .deposits, currency: bookCurrency, copyFrom: source) { saved() } } }
        .sheet(item: $reconciling) { receipt in MacDepositReceiptReviewView(deposit: deposit, receipt: receipt) }
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
            MacFinanceListToolbar(columns: $listColumns, sort: $sort, options: MacDepositsData.Sort.allCases.map { ($0.rawValue, $0) }, prefix: "deposit")
            if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red).accessibilityIdentifier("financeActionError") }
            if let message { Text(message).appFont(.caption, weight: .regular).foregroundStyle(MacOverviewStyle.income).accessibilityIdentifier("financeActionMessage") }
            if bookCurrency == nil { Text("账本包含不同本位币，请在设置中核对后再新增或编辑。").appFont(.caption, weight: .regular).foregroundStyle(.orange) }
            if visible.isEmpty {
                ContentUnavailableView(active.isEmpty ? "还没有存款" : "没有匹配的存款", systemImage: "building.columns", description: Text(active.isEmpty ? "点击左上方 + 新增一笔存款。" : "试试其他筛选条件。"))
                    .accessibilityIdentifier("depositsEmptyState").frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: listColumns == 2 ? 2 : 1), spacing: 10) {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                MacBankIcon(bank: deposit.bankName, size: 32, revision: logoRevision)
                VStack(alignment: .leading, spacing: 3) { Text(deposit.bankName).appFont(.body, weight: .semibold).lineLimit(1); Text(MacDepositsData.mode(deposit)).appFont(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 0); badge(deposit)
            }
            Text("\(MacOverviewStyle.money(deposit.originalPrincipal)) \(deposit.originalCurrency)").appFont(.section, weight: .semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            ViewThatFits(in: .horizontal) {
                HStack { Text(String(format: "%.2f%%", deposit.annualInterestRate)); Spacer(minLength: 4); Text(MacDateDisplay.string(deposit.maturityDate)) }
                VStack(alignment: .leading, spacing: 3) { Text(String(format: "%.2f%%", deposit.annualInterestRate)); Text(MacDateDisplay.string(deposit.maturityDate)) }
            }.appFont(.caption).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth: .infinity, minHeight: 104, alignment: .leading).contentShape(Rectangle()).macFinanceSelectableRow(selected: selectedID == deposit.id)
    }
    private func badge(_ deposit: DepositRecord) -> some View {
        let status = MacDepositsData.status(deposit, now: now)
        let color: Color = status == .soon ? .orange : (status == .active ? MacOverviewStyle.income : .secondary)
        return Text(status.rawValue).appFont(.caption, weight: .regular).foregroundStyle(color).appPadding(.horizontal, 8).appPadding(.vertical, 4)
            .background(color.opacity(0.1), in: Capsule())
    }
    private func detail(_ deposit: DepositRecord, compact: Bool) -> some View {
        GeometryReader { geometry in
            let audit = MacDepositsData.audit(deposit, transactions: transactions)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    detailHeader(deposit)
                    if geometry.size.width >= 650 {
                        HStack(alignment: .top, spacing: 14) { summaryCard(deposit).frame(maxWidth: .infinity); notesCard(deposit).frame(width: max(160, geometry.size.width * 0.29)) }
                    } else { summaryCard(deposit); if !MacFinanceNotes.visible(deposit.note).isEmpty { notesCard(deposit) } }
                    timingCard(deposit)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: geometry.size.width >= 1000 ? 3 : geometry.size.width >= 700 ? 2 : 1), alignment: .leading, spacing: 12) {
                        settlementCard(deposit, audit: audit)
                        receiptsCard(deposit, audit: audit)
                        scheduleCard(deposit)
                    }
                    if deposit.originalCurrency != deposit.baseCurrencyCode {
                        card { Text("本金记账快照").appFont(.section, weight: .semibold); Text("\(MacOverviewStyle.money(deposit.basePrincipal)) \(deposit.baseCurrencyCode)").accessibilityIdentifier("depositBookPrincipal"); Text("保存汇率：" + String(deposit.principalExchangeRateToBase)).appFont(.caption).foregroundStyle(.secondary) }
                    }
                }.padding(compact ? 18 : 22).padding(.bottom, 52)
            }.background(MacOverviewStyle.canvas).accessibilityIdentifier("depositDetailScroll").id(deposit.id)
        }
    }
    private func detailHeader(_ deposit: DepositRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            MacBankIcon(bank: deposit.bankName, size: 46, revision: logoRevision)
            VStack(alignment: .leading, spacing: 5) { Text(deposit.bankName).appFont(.dialogTitle, weight: .semibold).lineLimit(2).accessibilityIdentifier("depositDetailTitle"); Text(MacDepositsData.mode(deposit)).appFont(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                badge(deposit)
                HStack(spacing: 8) {
                    Button("编辑", systemImage: "pencil") { editing = .deposit(deposit) }.accessibilityIdentifier("editFinance-" + deposit.id.uuidString).disabled(bookCurrency == nil || posting)
                    Menu {
                        Button("复制存款", systemImage: "doc.on.doc") { copying = deposit }.accessibilityIdentifier("depositCopy").disabled(bookCurrency == nil)
                        Button("选择银行图标…") { chooseLogo(deposit.bankName) }.accessibilityIdentifier("depositChooseLogo")
                        Button("恢复默认图标") { do { try MacBankLogos.reset(deposit.bankName); logoRevision += 1 } catch { self.error = MacLocalization.error(error) } }
                        Divider(); Button("移除存款…", role: .destructive) { removing = deposit }.accessibilityIdentifier("depositRemove")
                    } label: { Image(systemName: "ellipsis").frame(width: 28, height: 30).contentShape(Rectangle()) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityIdentifier("depositMore").disabled(posting)
                }
            }
        }
    }
    private func summaryCard(_ deposit: DepositRecord) -> some View {
        card {
            Text("\(MacOverviewStyle.money(deposit.originalPrincipal)) \(deposit.originalCurrency)").appFont(.amount, weight: .semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65).accessibilityIdentifier("depositPrincipal")
            Text("本金 · 原币").appFont(.caption).foregroundStyle(.secondary); Divider()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top) { metric("年利率", String(format: "%.2f%%", deposit.annualInterestRate)); Spacer(); metric("存期", "\(MacDepositsData.timing(deposit, now: now).total) 天"); Spacer(); metric("预计总利息", "\(MacOverviewStyle.money(deposit.expectedInterest)) \(deposit.originalCurrency)", id: "depositExpectedInterest") }
                VStack(alignment: .leading, spacing: 10) { metric("年利率", String(format: "%.2f%%", deposit.annualInterestRate)); metric("存期", "\(MacDepositsData.timing(deposit, now: now).total) 天"); metric("预计总利息", "\(MacOverviewStyle.money(deposit.expectedInterest)) \(deposit.originalCurrency)", id: "depositExpectedInterest") }
            }
            if deposit.isInterestManuallyEdited { Text("预计利息按手动输入金额保存。").appFont(.caption).foregroundStyle(.secondary) }
        }
    }
    private func notesCard(_ deposit: DepositRecord) -> some View {
        card { Text("备注").appFont(.section, weight: .semibold); Text(MacFinanceNotes.visible(deposit.note).isEmpty ? "暂无备注" : MacFinanceNotes.visible(deposit.note)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
    }
    private func timingCard(_ deposit: DepositRecord) -> some View {
        let timing = MacDepositsData.timing(deposit, now: now)
        return card {
            HStack { metric("开始日期", MacDateDisplay.string(deposit.startDate)); Spacer(); metric("到期日期", MacDateDisplay.string(deposit.maturityDate)) }
            ProgressView(value: timing.progress).tint(MacUI.accent)
            HStack { Text(now < deposit.startDate ? "尚未起息" : "已存 \(timing.elapsed) 天"); Spacer(); Text(timing.remaining > 0 ? "距离到期 \(timing.remaining) 天" : "已到期") }.appFont(.caption).foregroundStyle(.secondary)
        }
    }
    private func settlementCard(_ deposit: DepositRecord, audit: MacDepositsData.ReceiptAudit) -> some View {
        card {
            Text("结息与入账").appFont(.section, weight: .semibold)
            metric("已核对到账利息", "\(MacOverviewStyle.money(audit.total)) \(deposit.originalCurrency)", id: "depositPostedInterest")
            Text(audit.pendingCount > 0 ? "\(audit.pendingCount) 笔计划收入待核对" : deposit.hasCreditedInterest ? "已完成结息" : "尚未完成").appFont(.caption).foregroundStyle(audit.pendingCount > 0 ? .orange : .secondary).accessibilityIdentifier("depositSettlementStatus")
            if audit.unverifiedCount > 0 { Label("\(audit.unverifiedCount) 条记录关联或金额异常，需核对历史。", systemImage: "exclamationmark.triangle").appFont(.caption).foregroundStyle(.orange).accessibilityIdentifier("depositReceiptWarning") }
            if !MacDepositSettlement.isManaged(deposit) {
                Text("旧记录需先核对历史到账。").appFont(.caption).foregroundStyle(.secondary)
                Button("核对历史结息") { reviewing = .deposit(deposit) }.accessibilityIdentifier("reviewFinance-" + deposit.id.uuidString).disabled(bookCurrency == nil || posting)
            } else if !deposit.hasCreditedInterest {
                Text("到期后自动生成待核对收入，也可在下方手动确认实际到账。").appFont(.caption).foregroundStyle(.secondary)
                Button(posting ? "正在记账…" : "确认收到到期利息", systemImage: "checkmark.circle") { confirming = deposit }.accessibilityIdentifier("postDepositInterest-" + deposit.id.uuidString).disabled(posting || bookCurrency == nil || !MacDepositSettlement.isEligible(deposit, now: now))
            }
        }
    }
    private func receiptsCard(_ deposit: DepositRecord, audit: MacDepositsData.ReceiptAudit) -> some View {
        card {
            Text("结息记录").appFont(.section, weight: .semibold)
            if audit.receipts.isEmpty { Text("暂无利息入账记录").foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(audit.receipts, id: \.id) { receipt in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(MacDateDisplay.string(receipt.date)).appFont(.caption).foregroundStyle(.secondary)
                            Text("+\(MacOverviewStyle.money(receipt.originalAmount)) \(receipt.originalCurrency)").appFont(.body, weight: .semibold).foregroundStyle(MacOverviewStyle.income)
                            Button((receipt.note ?? "").contains("[FTEstimated]") ? "核对实际到账" : "调整到账金额") { reconciling = receipt }.appFont(.caption).disabled(bookCurrency == nil || posting)
                        }
                        Divider()
                    }
                }
            }.frame(minHeight: audit.receipts.isEmpty ? 1 : 80, maxHeight: 210)
        }
    }
    private func scheduleCard(_ deposit: DepositRecord) -> some View {
        card {
            Text("结息计划").appFont(.section, weight: .semibold)
            Text("计划金额在核对前不代表实际到账。").appFont(.caption).foregroundStyle(.secondary)
            ForEach(Array(MacDepositScheduleView.rows(for: deposit).prefix(3))) { row in
                VStack(alignment: .leading, spacing: 4) { Text(MacDateDisplay.string(row.date)).appFont(.caption).foregroundStyle(.secondary); Text("\(MacOverviewStyle.money(row.interest)) \(deposit.originalCurrency)").appFont(.body, weight: .medium).monospacedDigit() }
            }
            Button("查看完整结息计划") { schedule = deposit }.appFont(.caption).accessibilityIdentifier("depositFullSchedule")
        }
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
