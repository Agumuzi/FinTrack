import SwiftUI
import SwiftData
import Charts

struct MacLoansView: View {
    let bookCurrency: String?
    @Environment(\.modelContext) private var context
    @Query private var loans: [LoanRule]
    @Query private var transactions: [Transaction]
    @Query private var rules: [RecurringTransaction]
    @AppStorage("v13_loans_single_list_width", store: MacPreferences.defaults) private var singleListWidth = 340.0
    @AppStorage("v13_loans_columns", store: MacPreferences.defaults) private var listColumns = 1
    @State private var search = ""
    @State private var status: MacLoansData.Status?
    @State private var category: String?
    @State private var currency: String?
    @State private var sort = MacLoansData.Sort.next
    @State private var selectedID: UUID?
    @State private var showsDetails = false
    @State private var showsNew = false
    @State private var editing: MacFinanceRecord?
    @State private var reviewing: MacFinanceRecord?
    @State private var schedule: LoanRule?
    @State private var legacy: MacLegacyLoanAudit.Report?
    @State private var receipt: Transaction?
    @State private var removal: LoanRule?
    private struct Confirmation: Identifiable {
        let loan: LoanRule
        let preview: MacLoanRepayment.Preview
        let book: String
        let source: String
        var id: UUID { loan.id }
    }
    @State private var confirmation: Confirmation?
    @State private var paymentRate = ""
    @State private var loadingRate = false
    @State private var error: String?
    @State private var message: String?
    @State private var now = Date()
    @AppStorage("v13_loans_double_list_width", store: MacPreferences.defaults) private var doubleListWidth = 580.0
    @State private var transientWidth: Double?
    private var listWidth: Double { transientWidth ?? (listColumns == 2 ? doubleListWidth : singleListWidth) }
    private var widthBinding: Binding<Double> { Binding(get: { listWidth }, set: { transientWidth = $0 }) }
    private var active: [LoanRule] { loans.filter { $0.deletedAt == nil } }
    private var audits: [UUID: MacLoansData.Audit] {
        Dictionary(uniqueKeysWithValues: active.map { ($0.id, MacLoansData.audit($0, transactions: transactions, rules: rules)) })
    }
    private var visible: [LoanRule] {
        MacLoansData.filtered(active, audits: audits, search: search, status: status, category: category, currency: currency, sort: sort, now: now)
    }
    private var selected: LoanRule? { visible.first { $0.id == selectedID } }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= MacUI.space(1000)
            let filterWidth = MacUI.filterColumnWidth(available: geometry.size.width, wide: wide)
            let maximum = max(300, Double(geometry.size.width - filterWidth - 340))
            HStack(spacing: MacUI.space(0)) {
                filters.frame(width: filterWidth)
                Divider()
                list(wide: wide).frame(width: wide ? min(max(300, listWidth), maximum) : nil).frame(maxWidth: wide ? nil : .infinity, maxHeight: .infinity)
                if wide {
                    MacFinanceListDivider(width: widthBinding, maximum: maximum) { value in
                        if listColumns == 2 { doubleListWidth = value } else { singleListWidth = value }; transientWidth = nil
                    }
                    if let selected { presentedDetail(selected).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else { ContentUnavailableView("选择一笔贷款", systemImage: "banknote", description: Text("查看还款计划和实际记录。")).frame(maxWidth: .infinity) }
                }
            }
            .sheet(isPresented: $showsDetails) {
                if !wide, let selected {
                    VStack(spacing: MacUI.space(0)) {
                        HStack { Text("贷款详情").appFont(.section, weight: .semibold); Spacer(); Button("关闭") { showsDetails = false }.accessibilityIdentifier("loansCloseDetails") }.appPadding(18)
                        Divider(); presentedDetail(selected)
                    }.appPanel(width: 600, height: 700)
                }
            }
        }
        .onAppear { selectedID = visible.first?.id }
        .onChange(of: listColumns) { _, _ in transientWidth = nil }
        .onChange(of: visible.map(\.id)) { _, ids in
            if !ids.contains(selectedID ?? UUID()) { selectedID = ids.first; showsDetails = false }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
        .sheet(isPresented: $showsNew) { if let bookCurrency { MacFinanceEditor(panel: .loans, currency: bookCurrency) { saved() } } }
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: MacUI.space(15)) {
            HStack {
                Text("筛选").appFont(.section, weight: .semibold); Spacer()
                Button { showsNew = true } label: { Image(systemName: "plus").frame(width: MacUI.space(24), height: MacUI.space(24)) }
                    .buttonStyle(MacInteractiveButtonStyle()).appHelp("新增贷款").accessibilityLabel("新增贷款").accessibilityIdentifier("financeAdd").disabled(bookCurrency == nil)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: MacUI.space(7)) {
                    filter("全部贷款", count: active.count, selected: status == nil, id: "loansAll") { status = nil }
                    ForEach(MacLoansData.Status.allCases) { item in
                        filter(item.rawValue, count: active.filter { MacLoansData.matches(audits[$0.id].map { MacLoansData.status($0, now: now) } ?? .review, filter: item) }.count,
                               selected: status == item, id: "loansStatus-\(item.rawValue)") { status = item }
                    }
                    Divider().appPadding(.vertical, 8)
                    Text("贷款类别").appFont(.caption, weight: .semibold).foregroundStyle(.secondary).appPadding(.leading, 8)
                    filter("全部类别", selected: category == nil, id: "loansCategoryAll") { category = nil }
                    ForEach(Array(Set(active.map(\.category))).sorted(), id: \.self) { item in
                        filter(MacOverviewStyle.category(item), selected: category == item, id: "loansCategory-\(item)") { category = item }
                    }
                    Divider().appPadding(.vertical, 8)
                    Text("原币").appFont(.caption, weight: .semibold).foregroundStyle(.secondary).appPadding(.leading, 8)
                    filter("全部币种", selected: currency == nil, id: "loansCurrencyAll") { currency = nil }
                    ForEach(Array(Set(active.map(\.currency))).sorted(), id: \.self) { item in
                        filter(item, selected: currency == item, id: "loansCurrency-\(item)") { currency = item }
                    }
                }
            }
            Button("重置筛选") { search = ""; status = nil; category = nil; currency = nil }.buttonStyle(MacInteractiveButtonStyle()).foregroundStyle(.secondary).accessibilityIdentifier("loansReset")
        }.appPadding(18).background(MacOverviewStyle.filters)
    }
    private func filter(_ title: String, count: Int? = nil, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title).lineLimit(2); Spacer(minLength: 2); if let count { Text("\(count)").monospacedDigit().foregroundStyle(.secondary) } }
                .appFont(.caption, weight: .regular, design: .default).appPadding(9).frame(maxWidth: .infinity, alignment: .leading)
                .macFinanceFilterRow(selected: selected)
        }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier(id)
    }
    private func list(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(14)) {
            HStack {
                Text("\(visible.count) 笔贷款").appFont(.section, weight: .semibold).accessibilityIdentifier("loansCount"); Spacer()
                if !wide, selected != nil { Button { showsDetails = true } label: { Image(systemName: "sidebar.right") }.appHelp("查看详情").accessibilityLabel("查看详情").accessibilityIdentifier("loansOpenDetails") }
            }
            TextField("搜索贷款、类别或备注", text: $search).textFieldStyle(.roundedBorder).accessibilityIdentifier("loansSearch")
            MacFinanceListToolbar(columns: $listColumns, sort: $sort, options: MacLoansData.Sort.allCases.map { ($0.rawValue, $0) }, prefix: "loans")
            if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red).accessibilityIdentifier("financeActionError") }
            if let message { Text(message).appFont(.caption, weight: .regular).foregroundStyle(MacOverviewStyle.income).accessibilityIdentifier("financeActionMessage") }
            if bookCurrency == nil { Text("账本包含不同本位币，请先在设置中核对。").appFont(.caption, weight: .regular).foregroundStyle(.orange) }
            if visible.isEmpty {
                ContentUnavailableView(active.isEmpty ? "还没有贷款" : "没有匹配的贷款", systemImage: "banknote", description: Text(active.isEmpty ? "点击左上方 + 新增贷款。" : "试试其他筛选条件。"))
                    .accessibilityIdentifier("loansEmptyState").frame(maxHeight: .infinity)
            } else {
                ScrollView { LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: listColumns == 2 ? 2 : 1), spacing: 10) {
                    ForEach(visible, id: \.id) { loan in
                        Button { selectedID = loan.id; if !wide { showsDetails = true } } label: { row(loan) }
                            .buttonStyle(MacInteractiveButtonStyle())
                            .accessibilityRepresentation {
                                Button(loan.title) { selectedID = loan.id; if !wide { showsDetails = true } }
                                    .accessibilityIdentifier("loansRow-\(loan.title)")
                            }
                    }
                }.appPadding(1) }
            }
        }.appPadding(18)
    }
    private func row(_ loan: LoanRule) -> some View {
        let audit = audits[loan.id] ?? MacLoansData.audit(loan, transactions: transactions, rules: rules)
        let payments = audit.schedule.isEmpty ? loan.amortizationSchedule : audit.schedule
        return VStack(alignment: .leading, spacing: MacUI.space(10)) {
            HStack(alignment: .top, spacing: MacUI.space(10)) {
                Image(systemName: "banknote").appFont(.section, weight: .semibold).foregroundStyle(MacOverviewStyle.accent)
                    .frame(width: MacUI.space(36), height: MacUI.space(36)).background(MacOverviewStyle.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: MacUI.space(4)) { Text(loan.title).appFont(.section, weight: .semibold).lineLimit(2); Text("\(MacOverviewStyle.category(loan.category)) · \(MacLoansData.method(loan.method))").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            HStack { Text(money(loan.principal, loan)).appFont(.section, weight: .semibold, design: .default).monospacedDigit(); Spacer(minLength: 0) }
            HStack { Text("贷款本金").appFont(.caption, weight: .regular).foregroundStyle(.secondary); Spacer(); badge(audit) }
            if let outstanding = audit.outstanding {
                Text("剩余本金 \(money(outstanding, loan))").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                ProgressView(value: Double(audit.paid.count), total: Double(max(1, payments.filter { $0.total > 0 }.count))).appHelp("按已核验收据计算的期数进度")
                Text("已还 \(audit.paid.count)/\(payments.filter { $0.total > 0 }.count) 期" + (payments.contains { $0.total == 0 } ? " · 零金额期次无需付款" : " · 剩余 \(loan.termMonths - audit.paid.count) 期")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            } else { Text("实际已还与剩余本金待核对").appFont(.caption, weight: .regular).foregroundStyle(.orange) }
            if let end = loan.amortizationSchedule.last?.date { Text("计划到期 \(MacDateDisplay.string(end))").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
        }.appPadding(14).frame(maxWidth: .infinity, alignment: .leading)
            .macFinanceSelectableRow(selected: selectedID == loan.id)
    }
    private func badge(_ audit: MacLoansData.Audit) -> some View {
        let state = MacLoansData.status(audit, now: now)
        let color: Color = state == .settled ? MacOverviewStyle.income : (state == .review || state == .overdue ? .orange : MacOverviewStyle.accent)
        return Text(state.rawValue).appFont(.caption, weight: .regular).foregroundStyle(color).appPadding(.horizontal, 7).appPadding(.vertical, 4).background(color.opacity(0.1), in: Capsule())
    }
    private func presentedDetail(_ loan: LoanRule) -> some View {
        detail(loan)
            .sheet(item: $editing) { item in if let bookCurrency { MacFinanceEditor(panel: .loans, currency: bookCurrency, existing: item) { saved() } } }
            .sheet(item: $reviewing) { MacFinanceReviewView(record: $0) }
            .sheet(item: $schedule) { item in MacLoansScheduleView(loan: item, audit: MacLoansData.audit(item, transactions: transactions, rules: rules)) }
            .sheet(item: $legacy) { legacyReport($0) }
            .sheet(item: $receipt) { receiptDetail($0) }
            .sheet(item: $confirmation) { paymentConfirmation($0) }
            .sheet(item: $removal) { removalConfirmation($0) }
    }
    private func detail(_ loan: LoanRule) -> some View {
        let audit = audits[loan.id] ?? MacLoansData.audit(loan, transactions: transactions, rules: rules)
        let payments = audit.schedule.isEmpty ? loan.amortizationSchedule : audit.schedule
        return ScrollView {
            VStack(alignment: .leading, spacing: MacUI.space(16)) {
                HStack { Text(loan.title).appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("loansDetailTitle"); Spacer(); badge(audit) }
                HStack {
                    Button("编辑", systemImage: "pencil") { editing = .loan(loan) }.accessibilityIdentifier("loansEdit").disabled(bookCurrency == nil)
                    Button("还款计划", systemImage: "calendar") { schedule = loan }.accessibilityIdentifier("loansSchedule")
                    Menu { Button("移除贷款…", role: .destructive) { removal = loan }.accessibilityIdentifier("loansRemove") }
                        label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: MacUI.space(30)).accessibilityIdentifier("loansMore")
                    Spacer()
                }
                card {
                    Text(money(loan.principal, loan)).appFont(.amount, weight: .semibold, design: .default).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).accessibilityIdentifier("loansPrincipal").id("principal-\(loan.id)-\(loan.principal)")
                    Text("贷款本金 · \(MacOverviewStyle.category(loan.category))").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    Divider()
                    HStack(alignment: .top) {
                        metric("年利率", "\(loan.annualRate.formatted())%"); Spacer()
                        metric("还款方式", MacLoansData.method(loan.method)); Spacer()
                        metric("总期限", "\(loan.termMonths) 期")
                    }
                    Text("首期 \(MacDateDisplay.string(loan.startDate)) · 计划到期 \(payments.last.map { MacDateDisplay.string($0.date) } ?? "待核对")").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    if loan.downPaymentAmount > 0 { Text("总额 \(money(loan.totalAmount, loan)) · 首付 \(money(loan.downPaymentAmount, loan))").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                }
                card {
                    Text("实际还款进度").appFont(.section, weight: .semibold)
                    if let outstanding = audit.outstanding {
                        Text("剩余本金 \(money(outstanding, loan))").appFont(.section, weight: .semibold).monospacedDigit().accessibilityIdentifier("loansOutstanding").id("remaining-\(loan.id)-\(outstanding)")
                        ProgressView(value: Double(audit.paid.count), total: Double(max(1, payments.filter { $0.total > 0 }.count)))
                        Text("已还 \(audit.paid.count)/\(payments.filter { $0.total > 0 }.count) 期" + (payments.contains { $0.total == 0 } ? " · 零金额期次无需付款" : " · 剩余 \(loan.termMonths - audit.paid.count) 期")).appFont(.caption, weight: .regular).accessibilityIdentifier("loansProgress").id("progress-\(loan.id)-\(audit.paid.count)")
                        HStack { metric("已还本金", money(audit.principalPaid ?? 0, loan)); Spacer(); metric("已付利息", money(audit.interestPaid ?? 0, loan)) }
                        if let warning = audit.warning { Text(warning).appFont(.caption).foregroundStyle(.orange) }
                        else { Text("依据已核验的账本记录。").appFont(.caption).foregroundStyle(.secondary) }
                    } else {
                        Text("实际进度待核对").appFont(.section, weight: .semibold).accessibilityIdentifier("loansUnverified")
                        Text(audit.warning ?? "请核对历史还款。").appFont(.caption, weight: .regular).foregroundStyle(.orange)
                    }
                }
                nextCard(loan, audit: audit)
                card {
                    HStack { Text("计划本息构成").appFont(.section, weight: .semibold); Spacer(); Text(loan.currency).appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                    Text(audit.reliable ? "展示接下来最多 12 期计划；计划不代表实际付款。" : "展示前 12 期计划；实际已还未知。").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    composition(loan, audit: audit)
                    HStack { metric("计划总利息", money(LoanAmortizationEngine.totalInterest(schedule: payments), loan)); Spacer(); metric("计划本息合计", money(LoanAmortizationEngine.totalRepayment(schedule: payments), loan)) }
                }
                card {
                    HStack { Text("实际还款记录").appFont(.section, weight: .semibold); Spacer(); Text(audit.reliable ? "\(audit.receipts.count) 笔已核验" : "待核对").appFont(.caption, weight: .regular).foregroundStyle(.secondary).accessibilityIdentifier("loansReceiptCount").id("receipts-\(loan.id)-\(audit.receipts.count)-\(audit.reliable)") }
                    if audit.receipts.isEmpty { Text(audit.reliable ? "暂无已核验的还款记录" : "核对完成前不展示实际付款汇总。").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                    ForEach(audit.receipts, id: \.id) { entry in
                        Button { receipt = entry } label: {
                            HStack { Text(MacDateDisplay.string(entry.date)); Spacer(); Text("−\(MacOverviewStyle.money(entry.originalAmount)) \(entry.originalCurrency)").monospacedDigit(); Image(systemName: "chevron.right").appFont(.caption, weight: .regular) }.appFont(.caption, weight: .regular).appPadding(.vertical, 7).contentShape(Rectangle())
                        }.buttonStyle(MacInteractiveButtonStyle()).appHelp("查看实际账目和保存的汇率快照").accessibilityIdentifier("loansReceipt-\(entry.id)")
                    }
                }
                if loan.currency != loan.baseCurrencyCode {
                    card {
                        HStack { Text("初始本金 \(MacOverviewStyle.money(loan.basePrincipal)) \(loan.baseCurrencyCode)").monospacedDigit(); Spacer(); Text("汇率 \(loan.exchangeRateToBase.formatted())").foregroundStyle(.secondary) }.appFont(.caption)
                        Text("实际还款使用每笔收据保存的汇率。").appFont(.caption).foregroundStyle(.secondary)
                    }
                }
                if !MacFinanceNotes.visible(loan.note).isEmpty { card { Text("备注").appFont(.section, weight: .semibold); Text(MacFinanceNotes.visible(loan.note)).textSelection(.enabled) } }
            }.appPadding(20)
        }.accessibilityIdentifier("loansDetailScroll").id(loan.id)
    }
    private func nextCard(_ loan: LoanRule, audit: MacLoansData.Audit) -> some View {
        card {
            Text("下一期计划").appFont(.section, weight: .semibold)
            if let next = audit.next {
                Text("第 \(next.index)/\(loan.termMonths) 期 · \(MacDateDisplay.string(next.date))").appFont(.body, weight: .medium).accessibilityIdentifier("loansNext")
                Text(money(next.total, loan)).appFont(.dialogTitle, weight: .semibold).monospacedDigit()
                Text("本金 \(money(next.principal, loan)) + 利息 \(money(next.interest, loan))").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                if Calendar.current.startOfDay(for: next.date) <= Calendar.current.startOfDay(for: now) {
                    Button("记录本期已付款…") { prepare(loan) }.accessibilityIdentifier("loansRecordPayment").disabled(bookCurrency == nil)
                    Text("请核对真实付款；此操作只记账，不发起银行扣款。").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                } else { Text("尚未到计划日期 · 未入账").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
            } else if audit.reliable { Text(audit.warning == nil ? "全部应付期次已核验" : "历史差额待核对").appFont(.body, weight: .regular).foregroundStyle(MacOverviewStyle.income) }
            else {
                Text(audit.warning ?? "请核对已有账目。").appFont(.caption, weight: .regular).foregroundStyle(.orange)
                if !MacLoanRepayment.isManaged(loan) || rules.contains(where: { ($0.projectIdentifier ?? "").hasPrefix("loan_generated:\(loan.id.uuidString):") }) {
                    Button("检查旧贷款关联") { do { legacy = try MacLegacyLoanAudit.inspect(loan, in: context) } catch { self.error = MacLocalization.error(error) } }.accessibilityIdentifier("loansLegacyAudit")
                    Button("核对首个未入账期次…") { reviewing = .loan(loan) }.accessibilityIdentifier("loansReview").disabled(bookCurrency == nil)
                    Text("核对会沿用原有周期还款流程；若已启用自动入账，到期计划可能自动记入账本。").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func composition(_ loan: LoanRule, audit: MacLoansData.Audit) -> some View {
        let payments = Array((audit.schedule.isEmpty ? loan.amortizationSchedule : audit.schedule).filter { !audit.reliable || !audit.paid.contains($0.index) }.prefix(12))
        return Group {
            if payments.isEmpty { Text("没有剩余还款计划").appFont(.caption, weight: .regular).foregroundStyle(.secondary).appMinHeight(100) }
            else {
                Chart(payments, id: \.index) { item in
                    BarMark(x: .value("期次", String(item.index)), y: .value("金额", item.principal)).foregroundStyle(by: .value("构成", "本金"))
                        .accessibilityLabel("第\(item.index)期计划本金").accessibilityValue("\(MacOverviewStyle.money(item.principal)) \(loan.currency)")
                    BarMark(x: .value("期次", String(item.index)), y: .value("金额", item.interest)).foregroundStyle(by: .value("构成", "利息"))
                        .accessibilityLabel("第\(item.index)期计划利息").accessibilityValue("\(MacOverviewStyle.money(item.interest)) \(loan.currency)")
                }.chartForegroundStyleScale(["本金": MacOverviewStyle.accent, "利息": MacOverviewStyle.accent.opacity(0.32)])
                    .chartXAxisLabel("期次").frame(height: MacUI.space(160)).accessibilityIdentifier("loansCompositionChart")
                    .appHelp("本金与利息均来自原有摊还计划；点击还款计划查看每期金额。")
            }
        }
    }
    private func money(_ value: Double, _ loan: LoanRule) -> String { "\(MacOverviewStyle.money(value)) \(loan.currency)" }
    private func metric(_ label: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: MacUI.space(5)) { Text(value).appFont(.body, weight: .medium).monospacedDigit(); Text(label).appFont(.caption, weight: .regular).foregroundStyle(.secondary) } }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(12), content: content).appPadding(18).frame(maxWidth: .infinity, alignment: .leading)
            .macFinanceDetailCard()
    }
    private func prepare(_ loan: LoanRule) {
        guard let bookCurrency else { return }
        do {
            let preview = try MacLoanRepayment.nextPayment(loan, now: Date(), bookCurrency: bookCurrency, in: context)
            paymentRate = loan.currency == bookCurrency ? "1" : ""; error = nil
            confirmation = Confirmation(loan: loan, preview: preview, book: bookCurrency, source: loan.currency)
        } catch { self.error = MacLocalization.error(error) }
    }
    private func paymentConfirmation(_ item: Confirmation) -> some View {
        let p = item.preview.payment
        return VStack(alignment: .leading, spacing: MacUI.space(16)) {
            Text("确认本期已实际付款？").appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("confirmLoanPaymentTitle")
            Text(item.loan.title).appFont(.section, weight: .semibold)
            Text("第 \(p.index)/\(item.preview.totalCount) 期 · \(MacDateDisplay.string(p.date))")
            Text("本金 \(MacOverviewStyle.money(p.principal)) + 利息 \(MacOverviewStyle.money(p.interest)) = \(MacOverviewStyle.money(p.total)) \(item.source)").accessibilityIdentifier("loanExpectedPayment")
            if item.source != item.book {
                TextField("本期还款汇率（\(item.source) → \(item.book)）", text: $paymentRate).accessibilityIdentifier("loanPaymentExchangeRate")
                Button("获取计划日汇率") {
                    loadingRate = true
                    Task { @MainActor in
                        defer { loadingRate = false }
                        do {
                            let rate = try await MacExchangeRates.shared.quote(from: item.source, to: item.book, on: p.date)
                            if confirmation?.id == item.id { paymentRate = String(rate) }
                        } catch { self.error = MacLocalization.error(error) }
                    }
                }.disabled(loadingRate)
                Text("本位币 \(item.book)；请核对真实付款使用的汇率。").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            }
            if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red) }
            Text("确认后新增一笔本金与利息合计的账本支出。此操作不转账，也不把其他期次标记为已付。")
            HStack { Spacer(); Button("取消") { confirmation = nil }.accessibilityIdentifier("loansCancelPayment").disabled(loadingRate)
                Button("确认记录已付款") {
                    do {
                        try MacLoanRepayment.recordPaid(item.loan, now: Date(), bookCurrency: item.book, expectedIndex: p.index,
                            exchangeRate: item.source == item.book ? 1 : try MacCurrency.rate(paymentRate), expectedPayment: p,
                            expectedScheduleCount: item.preview.totalCount, expectedOriginalCurrency: item.source, in: context)
                        saved(); confirmation = nil
                    } catch { self.error = MacLocalization.error(error); confirmation = nil }
                }.accessibilityIdentifier("confirmLoanPayment").disabled(loadingRate || (item.source != item.book && paymentRate.isEmpty))
            }
        }.appPadding(24).appDialog(width: 540)
    }
    private func removalConfirmation(_ loan: LoanRule) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(18)) {
            Text("移除这笔贷款？").appFont(.dialogTitle, weight: .semibold); Text(loan.title).appFont(.section, weight: .semibold)
            Text("贷款将从列表移除，关联还款规则停止执行。已有实际账目保留；移除不代表已经结清。")
            HStack { Spacer(); Button("取消") { removal = nil }.accessibilityIdentifier("loansCancelRemoval")
                Button("确认移除", role: .destructive) { do { try MacFinanceEditing.retire(.loan(loan), in: context); saved(); removal = nil } catch { self.error = MacLocalization.error(error) } }.accessibilityIdentifier("loansConfirmRemoval")
            }
        }.appPadding(24).appDialog(width: 500)
    }
    private func legacyReport(_ report: MacLegacyLoanAudit.Report) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(16)) {
            Text("旧贷款关联核对 · 只读").appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("legacyLoanAuditTitle")
            Text(report.loanTitle).appFont(.section, weight: .semibold)
            Text("关联规则 \(report.linkedRuleCount) · 孤立规则 \(report.orphanRuleCount) · 缺失期次 \(report.missingPeriodCount) · 重复期次 \(report.duplicatePeriodCount) · 无法识别 \(report.malformedRuleCount)").accessibilityIdentifier("legacyLoanAuditSummary")
            Text("可证明已付款：0 期。相似日期、金额与备注只作为核对线索；此报告不新增或更改账目。").appFont(.body, weight: .regular).foregroundStyle(.orange).accessibilityIdentifier("legacyLoanAuditUnverified")
            ScrollView { VStack(alignment: .leading, spacing: MacUI.space(10)) { ForEach(report.installments) { row in
                Text("第 \(row.index) 期 · \(MacDateDisplay.string(row.dueDate)) · 计划 \(MacOverviewStyle.money(row.scheduledAmount)) \(report.currency) · 关联 \(row.linkedRuleCount) · 候选现金记录 \(row.possibleCashExpenseCount)").appFont(.caption, weight: .regular)
            } } }.frame(maxHeight: MacUI.space(280))
            HStack { Spacer(); Button("关闭") { legacy = nil }.accessibilityIdentifier("closeLegacyLoanAudit") }
        }.appPadding(24).appDialog(width: 650)
    }
    private func receiptDetail(_ entry: Transaction) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(16)) {
            Text("实际还款账目").appFont(.dialogTitle, weight: .semibold)
            Text(MacDateDisplay.string(entry.date))
            Text("支出 \(MacOverviewStyle.money(entry.originalAmount)) \(entry.originalCurrency)").appFont(.section, weight: .semibold)
            Text("本位币 \(MacOverviewStyle.money(entry.baseAmount)) \(entry.baseCurrencyCode)").accessibilityIdentifier("loansReceiptBookAmount")
            Text("保存汇率 \(entry.exchangeRateToBase.formatted()) · \(MacOverviewStyle.category(entry.category))")
            Text("此账目由贷款还款生成；调整还款计划前需要核对已有记录。").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            Text((entry.note ?? "").components(separatedBy: " [FTLoan:").first!.replacingOccurrences(of: "Loan installment ", with: "还款期次 ").replacingOccurrences(of: "Principal:", with: "本金：").replacingOccurrences(of: "Interest:", with: "利息：")).appFont(.caption, weight: .regular).textSelection(.enabled)
            HStack { Spacer(); Button("关闭") { receipt = nil }.accessibilityIdentifier("loansCloseReceipt") }
        }.appPadding(24).appDialog(width: 560)
    }
    private func saved() { error = nil; message = "已保存"; now = Date(); Task { try? await MacNotifications.schedule(in: context) } }
}

struct MacLoansScheduleView: View {
    let loan: LoanRule
    let audit: MacLoansData.Audit
    @Environment(\.dismiss) private var dismiss
    private struct Row: Identifiable {
        let payment: LoanAmortizationEngine.Payment
        var id: Int { payment.index }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(14)) {
            Text(loan.title).appFont(.dialogTitle, weight: .semibold)
            Text("还款计划 · \(loan.currency) · \(MacLoansData.method(loan.method))").appFont(.section, weight: .semibold)
            Text("计划不代表实际已付。只有核验收据完整时才展示已入账标记。").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            Table((audit.schedule.isEmpty ? loan.amortizationSchedule : audit.schedule).map { Row(payment: $0) }) {
                TableColumn("期次") { Text(String($0.payment.index)) }.width(MacUI.space(40))
                TableColumn("日期") { Text(MacDateDisplay.string($0.payment.date)) }.width(MacUI.space(100))
                TableColumn("本金") { Text(MacOverviewStyle.money($0.payment.principal)) }
                TableColumn("利息") { Text(MacOverviewStyle.money($0.payment.interest)) }
                TableColumn("合计") { Text(MacOverviewStyle.money($0.payment.total)) }
                TableColumn("计划剩余本金") { Text(MacOverviewStyle.money($0.payment.remainingBalance)) }
                TableColumn("记录状态") { row in Text(!audit.reliable ? "待核对" : (audit.paid.contains(row.id) ? "已核验入账" : row.payment.total == 0 ? "无需付款" : "未入账")) }
            }.frame(height: MacUI.space(380)).accessibilityIdentifier("loanScheduleTable")
            HStack { Spacer(); Button("关闭") { dismiss() }.accessibilityIdentifier("loansCloseSchedule") }
        }.appPadding(24).appDialog(width: 850)
    }
}
