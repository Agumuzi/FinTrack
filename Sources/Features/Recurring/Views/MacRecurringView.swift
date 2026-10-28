import SwiftUI
import SwiftData

struct MacRecurringView: View {
    @AppStorage(MacCustomTypography.bodyKey, store: MacPreferences.defaults) private var layoutBodyPoints = 16
    @AppStorage(MacCustomTypography.captionKey, store: MacPreferences.defaults) private var layoutCaptionPoints = 12
    @AppStorage("v2_font_tier", store: MacPreferences.defaults) private var layoutTier = "standard"
    let bookCurrency: String?
    @Environment(\.modelContext) private var context
    @Query private var rules: [RecurringTransaction]
    @Query private var transactions: [Transaction]
    @AppStorage("v13_recurring_single_list_width", store: MacPreferences.defaults) private var singleListWidth = 340.0
    @AppStorage("v13_recurring_columns", store: MacPreferences.defaults) private var listColumns = 1
    @State private var search = ""
    @State private var type: RecurringTransactionType?
    @State private var status: MacRecurringData.Status?
    @State private var category: String?
    @State private var currency: String?
    @State private var sort = MacRecurringData.Sort.next
    @State private var selectedID: UUID?
    @State private var showsDetails = false
    @State private var showsNew = false
    @State private var editing: MacFinanceRecord?
    @State private var reviewing: MacFinanceRecord?
    @State private var schedule: RecurringTransaction?
    private enum Action { case pause, resume, remove, post }
    private struct Confirmation: Identifiable {
        let rule: RecurringTransaction
        let action: Action
        let dates: [Date]
        var id: UUID { rule.id }
    }
    @State private var confirmation: Confirmation?
    @State private var posting = false
    @State private var error: String?
    @State private var message: String?
    @State private var now = Date()
    @AppStorage("v13_recurring_double_list_width", store: MacPreferences.defaults) private var doubleListWidth = 580.0
    @State private var transientWidth: Double?
    private var automaticListWidth: Double { MacFinanceSplitSizing.minimumListWidth(columns: listColumns, bodySize: MacUI.fontTier.bodySize, titles: active.map(\.title)) }
    private var listWidth: Double {
        if let transientWidth { return transientWidth }
        let key = listColumns == 2 ? "v13_recurring_double_list_width" : "v13_recurring_single_list_width"
        let deltaKey = "v144_recurring_list_delta_" + String(listColumns)
        if let delta = MacPreferences.defaults.object(forKey: deltaKey) as? NSNumber { return max(300, automaticListWidth + delta.doubleValue) }
        guard MacPreferences.defaults.object(forKey: key) != nil else { return automaticListWidth }
        let originalAutomatic = MacFinanceSplitSizing.minimumListWidth(columns: listColumns, bodySize: 16, titles: active.map(\.title))
        return max(300, (listColumns == 2 ? doubleListWidth : singleListWidth) + automaticListWidth - originalAutomatic)
    }
    private var widthBinding: Binding<Double> { Binding(get: { listWidth }, set: { transientWidth = $0 }) }
    private var active: [RecurringTransaction] { rules.filter { $0.deletedAt == nil } }
    private var visible: [RecurringTransaction] {
        MacRecurringData.filtered(active, search: search, type: type, status: status, category: category, currency: currency, sort: sort)
    }
    private var selected: RecurringTransaction? { visible.first { $0.id == selectedID } }

    var body: some View {
        let _ = layoutBodyPoints; let _ = layoutCaptionPoints
        GeometryReader { geometry in
            let filterWidth = MacUI.filterColumnWidth(available: geometry.size.width, wide: geometry.size.width >= MacUI.space(950))
            let detailMinimum = MacFinanceSplitSizing.detailMinimum(bodySize: MacUI.fontTier.bodySize)
            let wide = geometry.size.width - filterWidth >= 300 + detailMinimum + 10
            let maximum = max(300, Double(geometry.size.width - filterWidth - detailMinimum - 10))
            HStack(spacing: MacUI.space(0)) {
                filters.frame(width: filterWidth)
                Divider()
                list(wide: wide).accessibilityElement(children:.contain).accessibilityIdentifier("recurringListPane").frame(width: wide ? min(max(300, listWidth), maximum) : nil).frame(maxWidth: wide ? nil : .infinity, maxHeight: .infinity)
                if wide {
                    MacFinanceListDivider(width: widthBinding, maximum: maximum) { value in
                        if listColumns == 2 { doubleListWidth = value } else { singleListWidth = value }
                        MacPreferences.defaults.set(value - automaticListWidth, forKey: "v144_recurring_list_delta_" + String(listColumns)); transientWidth = nil
                    }.accessibilityIdentifier("recurringListDivider")
                    if let selected { presentedDetail(selected).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else { ContentUnavailableView("选择一个周期项目", systemImage: "clock.arrow.circlepath", description: Text("查看规则、计划和实际入账记录。")).frame(maxWidth: .infinity) }
                }
            }
            .sheet(isPresented: $showsDetails) {
                if !wide, let selected {
                    VStack(spacing: MacUI.space(0)) {
                        HStack { Text("周期详情").appFont(.section, weight: .semibold); Spacer(); Button("关闭") { showsDetails = false }.accessibilityIdentifier("recurringCloseDetails") }.appPadding(18)
                        Divider(); presentedDetail(selected)
                    }.appPanel(width: 560, height: 670)
                }
            }
        }
        .onAppear { selectedID = visible.first?.id }
        .onChange(of: listColumns) { _, _ in transientWidth = nil }
        .onChange(of: visible.map(\.id)) { _, ids in
            if !ids.contains(selectedID ?? UUID()) { selectedID = ids.first; showsDetails = false }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
        .sheet(isPresented: $showsNew) {
            if let bookCurrency { MacFinanceEditor(panel: .recurring, currency: bookCurrency) { saved() } }
        }
        .task(id: active.map { "\($0.id):\($0.updatedAt):\($0.isActive)" }.joined()) { try? await MacNotifications.schedule(in: context) }
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: MacUI.space(15)) {
            HStack {
                Text("筛选").appFont(.section, weight: .semibold); Spacer()
                Button { showsNew = true } label: { Image(systemName: "plus").frame(width: MacUI.space(24), height: MacUI.space(24)) }
                    .buttonStyle(MacInteractiveButtonStyle()).appHelp("新增周期").accessibilityLabel("新增周期").accessibilityIdentifier("financeAdd").disabled(bookCurrency == nil || posting)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: MacUI.space(7)) {
                    filter("全部周期", count: active.count, selected: type == nil, id: "recurringAll") { type = nil }
                    filter("收入", count: active.filter { $0.typedType == .income }.count, selected: type == .income, id: "recurringIncome") { type = .income }
                    filter("支出", count: active.filter { $0.typedType == .expense }.count, selected: type == .expense, id: "recurringExpense") { type = .expense }
                    Divider().appPadding(.vertical, 8)
                    Text("状态").appFont(.caption, weight: .semibold).foregroundStyle(.secondary).appPadding(.leading, 8)
                    filter("全部状态", selected: status == nil, id: "recurringStatusAll") { status = nil }
                    ForEach(MacRecurringData.Status.allCases) { item in
                        filter(item.rawValue, count: active.filter { MacRecurringData.status($0) == item }.count, selected: status == item, id: "recurringStatus-\(item.rawValue)") { status = item }
                    }
                    Divider().appPadding(.vertical, 8)
                    Text("类别").appFont(.caption, weight: .semibold).foregroundStyle(.secondary).appPadding(.leading, 8)
                    filter("全部类别", selected: category == nil, id: "recurringCategoryAll") { category = nil }
                    ForEach(Array(Set(active.map(\.category))).sorted(), id: \.self) { item in
                        filter(MacOverviewStyle.category(item), selected: category == item, id: "recurringCategory-\(item)") { category = item }
                    }
                    Divider().appPadding(.vertical, 8)
                    Text("原币").appFont(.caption, weight: .semibold).foregroundStyle(.secondary).appPadding(.leading, 8)
                    filter("全部币种", selected: currency == nil, id: "recurringCurrencyAll") { currency = nil }
                    ForEach(Array(Set(active.map(\.originalCurrency))).sorted(), id: \.self) { item in
                        filter(item, selected: currency == item, id: "recurringCurrency-\(item)") { currency = item }
                    }
                }
            }
            Button("重置筛选") { search = ""; type = nil; status = nil; category = nil; currency = nil }.buttonStyle(MacInteractiveButtonStyle()).foregroundStyle(.secondary).accessibilityIdentifier("recurringReset")
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
                Text("\(visible.count) 个周期项目").appFont(.section, weight: .semibold).accessibilityIdentifier("recurringCount"); Spacer()
                if !wide, selected != nil { Button { showsDetails = true } label: { Image(systemName: "sidebar.right") }.appHelp("查看详情").accessibilityLabel("查看详情").accessibilityIdentifier("recurringOpenDetails") }
            }
            TextField("搜索项目、类别或备注", text: $search).textFieldStyle(.roundedBorder).accessibilityIdentifier("recurringSearch")
            MacFinanceListToolbar(columns: $listColumns, sort: $sort, options: MacRecurringData.Sort.allCases.map { ($0.rawValue, $0) }, prefix: "recurring")
            if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red).accessibilityIdentifier("financeActionError") }
            if let message { Text(message).appFont(.caption, weight: .regular).foregroundStyle(MacOverviewStyle.income).accessibilityIdentifier("financeActionMessage") }
            if bookCurrency == nil { Text("账本包含不同本位币，请在设置中核对后再新增或编辑。").appFont(.caption, weight: .regular).foregroundStyle(.orange) }
            if visible.isEmpty {
                ContentUnavailableView(active.isEmpty ? "还没有周期项目" : "没有匹配的周期", systemImage: "repeat", description: Text(active.isEmpty ? "点击左上方 + 新增周期收支。" : "试试其他筛选条件。"))
                    .accessibilityIdentifier("recurringEmptyState").frame(maxHeight: .infinity)
            } else {
                ScrollView { LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: listColumns == 2 ? 2 : 1), spacing: 10) {
                    ForEach(visible, id: \.id) { rule in
                        Button { selectedID = rule.id; if !wide { showsDetails = true } } label: { row(rule) }
                            .buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("recurringRow-\(rule.title)")
                    }
                }.appPadding(1) }
            }
        }.appPadding(18)
    }
    private func amount(_ rule: RecurringTransaction) -> String { "\(rule.typedType == .income ? "+" : "−")\(MacOverviewStyle.money(rule.originalAmount)) \(rule.originalCurrency)" }
    private func row(_ rule: RecurringTransaction) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(11)) {
            HStack(alignment: .top, spacing: MacUI.space(10)) {
                Image(systemName: rule.typedType == .income ? "arrow.down.left" : "arrow.up.right").appFont(.section, weight: .semibold).foregroundStyle(color(rule))
                    .frame(width: MacUI.space(36), height: MacUI.space(36)).background(color(rule).opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: MacUI.space(4)) { Text(rule.title).appFont(.section, weight: .semibold).fixedSize(horizontal: false, vertical: true); Text("\(MacRecurringData.frequency(rule)) · \(MacOverviewStyle.category(rule.category))").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            HStack { Text(amount(rule)).appFont(.section, weight: .semibold, design: .default).monospacedDigit().foregroundStyle(color(rule)); Spacer(minLength: 0); badge(rule) }
            Text("计划 \(MacDateDisplay.string(rule.nextExecutionDate))").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
        }.appPadding(14).frame(maxWidth: .infinity, alignment: .leading)
            .macFinanceSelectableRow(selected: selectedID == rule.id)
    }
    private func color(_ rule: RecurringTransaction) -> Color { rule.typedType == .income ? MacOverviewStyle.income : MacOverviewStyle.expense }
    private func badge(_ rule: RecurringTransaction) -> some View {
        let state = MacRecurringData.status(rule), color: Color = state == .active ? MacOverviewStyle.income : .secondary
        return Text(state.rawValue).appFont(.caption, weight: .regular).foregroundStyle(color).appPadding(.horizontal, 7).appPadding(.vertical, 4).background(color.opacity(0.1), in: Capsule())
    }
    private func presentedDetail(_ rule: RecurringTransaction) -> some View {
        detail(rule)
            .sheet(item: $editing) { item in if let bookCurrency { MacFinanceEditor(panel: .recurring, currency: bookCurrency, existing: item) { saved() } } }
            .sheet(item: $reviewing) { MacFinanceReviewView(record: $0) }
            .sheet(item: $schedule) { MacRecurringScheduleView(rule: $0) }
            .sheet(item: $confirmation) { confirmationView($0) }
    }
    private func detail(_ rule: RecurringTransaction) -> some View {
        let audit = MacRecurringData.audit(rule, transactions: transactions)
        let state = MacRecurringData.status(rule)
        let linkedLoan = MacRecurringData.isLoan(rule)
        let managed = MacFinanceRecords.isManagedRecurring(rule)
        let dates = try? MacAutomaticPosting.recurringDates(rule, now: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: MacUI.space(16)) {
                HStack { Text(rule.title).appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("recurringDetailTitle"); Spacer(); badge(rule) }
                HStack {
                    Button("编辑", systemImage: "pencil") { editing = .recurring(rule) }.accessibilityIdentifier("recurringEdit").disabled(bookCurrency == nil || posting || linkedLoan)
                    if state != .ended {
                        Button(rule.isActive ? "暂停…" : "恢复…") { request(rule, action: rule.isActive ? .pause : .resume) }
                            .accessibilityIdentifier("recurringToggle").disabled(posting || linkedLoan || (!rule.isActive && !managed))
                    }
                    Menu { Button("移除周期…", role: .destructive) { request(rule, action: .remove) }.accessibilityIdentifier("recurringRemove") }
                        label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: MacUI.space(30)).accessibilityIdentifier("recurringMore").disabled(posting || linkedLoan)
                    Spacer()
                }
                card {
                    Text(amount(rule)).appFont(.amount, weight: .semibold, design: .default).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).foregroundStyle(color(rule)).accessibilityIdentifier("recurringAmount").id("amount-\(rule.id)-\(rule.originalAmount)")
                    Text("\(rule.typedType == .income ? "收入" : "支出") · 每次原币金额").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    Divider()
                    HStack(alignment: .top) {
                        metric("循环频率", MacRecurringData.frequency(rule)); Spacer()
                        metric("结束日期", rule.endDate.map(MacDateDisplay.string) ?? "无结束日期"); Spacer()
                        metric("类别", MacOverviewStyle.category(rule.category))
                    }
                }
                card {
                    Text("下一次计划").appFont(.section, weight: .semibold)
                    Text(MacDateDisplay.string(rule.nextExecutionDate)).appFont(.section, weight: .semibold).accessibilityIdentifier("recurringNextDate").id("next-\(rule.id)-\(rule.nextExecutionDate)")
                    if linkedLoan {
                        Text("贷款关联规则 · 请在贷款页核对实际还款。这些计划不作为周期独立入账。").appFont(.caption, weight: .regular).foregroundStyle(.orange)
                    } else if !managed {
                        Text("旧规则待核对 · 最近执行日期不能证明实际到账，不推测历史账目。").appFont(.caption, weight: .regular).foregroundStyle(.orange)
                        Button("核对首个未入账日期…") { reviewing = .recurring(rule) }.accessibilityIdentifier("recurringReview").disabled(posting)
                    } else if state == .ended {
                        Text("计划已结束；已有账目继续保留。").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    } else if !rule.isActive {
                        Text("规则已暂停，不会执行入账。恢复后请核对待处理日期。").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    } else if let dates, !dates.isEmpty {
                        Text("\(dates.count) 次计划待确认 · 请核对实际收支").appFont(.caption, weight: .regular).foregroundStyle(.orange).accessibilityIdentifier("recurringDueCount")
                        Button("确认实际收支并入账…") { request(rule, action: .post) }.accessibilityIdentifier("postRecurring").disabled(bookCurrency == nil || posting)
                    } else if dates == nil {
                        Text("计划需要核对，可能包含超过 24 次待处理或无效频率。请编辑或核对首个未入账日期。").appFont(.caption, weight: .regular).foregroundStyle(.orange)
                        Button("核对未入账日期…") { reviewing = .recurring(rule) }.accessibilityIdentifier("recurringReview").disabled(posting)
                    } else {
                        Text("尚未到计划日期 · 未入账").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    }
                    Button("查看计划") { schedule = rule }.accessibilityIdentifier("recurringSchedule")
                }
                card {
                    HStack { Text("实际入账记录").appFont(.section, weight: .semibold); Spacer(); Text("\(audit.receipts.count) 笔已核验").appFont(.caption, weight: .regular).foregroundStyle(.secondary).accessibilityIdentifier("recurringReceiptCount").id("receipts-\(rule.id)-\(audit.receipts.count)") }
                    if audit.unverifiedCount > 0 { Text("\(audit.unverifiedCount) 笔关联账目未通过核验，请到账目页检查；未计入本列表。").appFont(.caption, weight: .regular).foregroundStyle(.orange) }
                    if audit.receipts.isEmpty { Text("暂无可核验的入账记录").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                    ForEach(audit.receipts, id: \.id) { entry in
                        VStack(alignment: .leading, spacing: MacUI.space(5)) {
                            HStack { Text(MacDateDisplay.string(entry.date)); Spacer(); Text("\(entry.typedType == .income ? "+" : "−")\(MacOverviewStyle.money(entry.originalAmount)) \(entry.originalCurrency)").monospacedDigit() }.appFont(.caption, weight: .regular)
                            if entry.originalCurrency != entry.baseCurrencyCode { Text("本位币 \(MacOverviewStyle.money(entry.baseAmount)) \(entry.baseCurrencyCode) · 汇率 \(entry.exchangeRateToBase.formatted())").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                        }.appPadding(.vertical, 5)
                    }
                    if let last = rule.lastExecutionDate { Text("规则最近执行：\(MacDateDisplay.string(last))；实际入账以可核验账目为准。").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                }
                if rule.originalCurrency != rule.baseCurrencyCode || !MacFinanceNotes.visible(rule.note).isEmpty {
                    card {
                        if rule.originalCurrency != rule.baseCurrencyCode {
                            HStack { Text("本位币 \(MacOverviewStyle.money(rule.baseAmount)) \(rule.baseCurrencyCode)").monospacedDigit().accessibilityIdentifier("recurringBookAmount"); Spacer(); Text("汇率 \(rule.exchangeRateToBase.formatted())").foregroundStyle(.secondary) }.appFont(.caption)
                        }
                        if !MacFinanceNotes.visible(rule.note).isEmpty { Text(MacFinanceNotes.visible(rule.note)).textSelection(.enabled) }
                    }
                }
            }.appPadding(20)
        }.accessibilityIdentifier("recurringDetailScroll")
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(5)) { Text(value).appFont(.body, weight: .medium); Text(label).appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
    }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(12), content: content).appPadding(18).frame(maxWidth: .infinity, alignment: .leading)
            .macFinanceDetailCard()
    }
    private func request(_ rule: RecurringTransaction, action: Action) {
        do {
            let dates = action == .post ? try MacAutomaticPosting.recurringDates(rule, now: Date()) : []
            confirmation = Confirmation(rule: rule, action: action, dates: dates); error = nil
        } catch { self.error = MacLocalization.error(error) }
    }
    private func confirmationView(_ item: Confirmation) -> some View {
        let title: String
        let explanation: String
        switch item.action {
        case .pause: title = "暂停这个周期？"; explanation = "暂停后不再入账，已有账目保留。恢复时不会跳过积累的待处理日期。"
        case .resume: title = "恢复这个周期？"; explanation = "保留原来的下一次计划日期。请核对暂停期间的实际收支；若启用了自动入账，恢复后到期计划可能自动记录。"
        case .remove: title = "移除这个周期？"; explanation = "规则将从列表移除并停止执行，已有账目保留。"
        case .post: title = "确认这些收支已实际发生？"; explanation = "将以下 \(item.dates.count) 次计划记入账本。请逐次核对实际金额，计划日期本身不代表已经到账。外币按发生日期获取汇率。"
        }
        return VStack(alignment: .leading, spacing: MacUI.space(18)) {
            Text(title).appFont(.dialogTitle, weight: .semibold); Text(item.rule.title).appFont(.section, weight: .semibold); Text(explanation)
            if item.action == .post {
                ScrollView { VStack(alignment: .leading, spacing: MacUI.space(6)) {
                    ForEach(item.dates, id: \.self) { date in Text("\(MacDateDisplay.string(date)) · \(amount(item.rule))").appFont(.caption, weight: .regular).monospacedDigit() }
                } }.frame(maxHeight: MacUI.space(200))
            }
            HStack { Spacer(); Button("取消") { confirmation = nil }.accessibilityIdentifier("recurringCancelConfirmation")
                Button(item.action == .remove ? "确认移除" : "确认") { apply(item); confirmation = nil }.accessibilityIdentifier("recurringConfirm")
            }
        }.appPadding(24).appDialog(width: 500)
    }
    private func apply(_ item: Confirmation) {
        if item.action == .post {
            guard let bookCurrency, !posting else { return }
            posting = true; error = nil; message = nil
            Task { @MainActor in
                defer { posting = false }
                do {
                    guard item.dates == (try MacAutomaticPosting.recurringDates(item.rule, now: Date())) else { throw MacFinanceReview.Failure.schedule }
                    let count = try await MacAutomaticPosting.post(item.rule, now: Date(), book: bookCurrency, in: context)
                    saved(); message = "已记录 \(count) 次实际收支"
                } catch { self.error = MacLocalization.error(error) }
            }
        } else {
            do {
                if item.action == .remove { try MacFinanceEditing.retire(.recurring(item.rule), in: context) }
                else { try MacRecurringData.setActive(item.rule, active: item.action == .resume, in: context) }
                saved()
            } catch { self.error = MacLocalization.error(error) }
        }
    }
    private func saved() { error = nil; message = "已保存"; now = Date(); Task { try? await MacNotifications.schedule(in: context) } }
}
