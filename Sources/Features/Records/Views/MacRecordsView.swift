import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// Native record editing, search, filtering, export and batch actions.
struct MacRecordSection: View {
    private let scope: MacOverviewScope?

    init(scope: MacOverviewScope? = nil, navigationState: MacRecordsNavigationState = MacRecordsNavigationState()) {
        self.scope = scope
        _searchText = State(initialValue: scope == nil ? navigationState.searchText : "")
        _currencyFilter = State(initialValue: scope == nil ? navigationState.currencyFilter : "All")
        _recordSort = State(initialValue: navigationState.recordSort)
        _displayLimit = State(initialValue: navigationState.displayLimit)
        _expandedYears = State(initialValue: scope == nil ? navigationState.expandedYears : [Calendar.current.component(.year, from: Date())])
        _expandedMonths = State(initialValue: scope == nil ? navigationState.expandedMonths : [Self.monthKey(Date())])
        if let scope {
            _rangeTitle = State(initialValue: scope.title)
            _dateFilterEnabled = State(initialValue: scope.interval() != nil)
            _dateFrom = State(initialValue: scope.interval()?.start ?? scope.from)
            _dateThrough = State(initialValue: scope.interval().map { $0.end.addingTimeInterval(-1) } ?? scope.through)
            _categoryFilter = State(initialValue: scope.category ?? "All")
            _typeFilter = State(initialValue: scope.type?.rawValue ?? "All")
        } else {
            _rangeTitle = State(initialValue: navigationState.rangeTitle)
            _dateFilterEnabled = State(initialValue: navigationState.dateFilterEnabled)
            _dateFrom = State(initialValue: navigationState.dateFrom)
            _dateThrough = State(initialValue: navigationState.dateThrough)
            _categoryFilter = State(initialValue: navigationState.categoryFilter)
            _typeFilter = State(initialValue: navigationState.typeFilter)
        }
    }
    @EnvironmentObject private var feedback: MacOperationFeedbackCenter
    @EnvironmentObject private var workspace: MacWorkspaceSession
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var financeDeposits: [DepositRecord]
    @Query private var financeLoans: [LoanRule]
    @Query private var financeRules: [RecurringTransaction]
    @Query private var financialProfiles: [FinancialProfile]
    @Query private var goals: [Goal]
    @State private var activeRowsCache: [Transaction] = []
    @State private var visibleRowsCache: [Transaction] = []
    @State private var maximumVisibleAmount = 0.0
    @AppStorage(MacCustomTypography.bodyKey, store: MacPreferences.defaults) private var measuredCustomBody = 16
    @AppStorage("v2_font_tier", store: MacPreferences.defaults) private var measuredFontTier = "standard"
    @AppStorage(MacInterfaceFonts.preferenceKey, store: MacPreferences.defaults) private var measuredFontName = ""
    @State private var activeBookCurrencyCache: String?
    @State private var filterCurrencyCodes: [String] = []
    @State private var filterCategoryNames: [String: [String]] = [:]
    @State private var timelineIndex = MacRecordsTimelineIndex(rows: [])
    @State private var searchText = ""
    @State private var selectedTransactionID: UUID?
    @State private var saveError: String?
    @State private var showsNewTransaction = false
    @State private var editingTransaction: Transaction?
    @AppStorage("v2_confirm_records") private var extraDeletionConfirmation = true
    @State private var deletionAcknowledged = false
    @State private var showsDeleteConfirmation = false
    @State private var typeFilter = "All"
    @State private var dateFilterEnabled = false
    @State private var dateFrom = DateFilterRangeState.currentMonth().startDate
    @State private var dateThrough = Date()
    @State private var currencyFilter = "All"
    @State private var categoryFilter = "All"
    @State private var batchSelection = Set<UUID>()
    @State private var selectionMode = false
    private var showsSelectionBoxes: Bool { selectionMode || batchSelection.count > 1 }
    @State private var confirmsBatchDelete = false
    @State private var showsDetails = false
    @State private var recordSort = MacPreferences.defaults.string(forKey: "v2_sort") ?? "最新优先"
    @State private var displayLimit = MacPreferences.defaults.object(forKey: "v2_page_size") as? Int ?? 50
    @AppStorage("v2_notes") private var showsNotesPreview = true
    @State private var rangeTitle = "全部记录"
    @State private var expandedYears: Set<Int> = [Calendar.current.component(.year, from: Date())]
    @State private var expandedMonths: Set<String> = [Self.monthKey(Date())]
    private static func monthKey(_ date: Date) -> String {
        "\(Calendar.current.component(.year, from: date))-\(Calendar.current.component(.month, from: date))"
    }
    @AppStorage("base_currency") private var preferredBookCurrency = "USD"

    private var activeTransactions: [Transaction] { activeRowsCache }
    private var isNewLedger: Bool {
        activeTransactions.isEmpty && !financeDeposits.contains { $0.deletedAt == nil }
        && !financeLoans.contains { $0.deletedAt == nil } && !financeRules.contains { $0.deletedAt == nil }
        && !financialProfiles.contains { $0.deletedAt == nil } && !goals.contains { $0.deletedAt == nil }
    }

    private var activeBookCurrency: String? { activeBookCurrencyCache }

    private var activeBookCurrencyFromLedger: String? {
        MacCurrency.resolveLedgerCurrency(transactions: activeTransactions, deposits: financeDeposits,
            loans: financeLoans, recurring: financeRules, preferred: preferredBookCurrency).displayCurrency
    }

    private var totals: (income: Double, expense: Double, net: Double) {
        MacTransactionCRUD.totals(
            transactions: visibleTransactions,
            currency: activeBookCurrency ?? preferredBookCurrency
        )
    }

    private var visibleTransactions: [Transaction] { visibleRowsCache }

    private func refreshVisibleRows() {
        let filter = MacRecordsFilter(search: searchText, type: typeFilter, currency: currencyFilter,
            category: categoryFilter, interval: dateFilterEnabled ? MacRecordsFilter.inclusiveDays(from: dateFrom, through: dateThrough) : nil)
        let filtered = activeTransactions.filter { filter.matches($0) }
        // The @Query already supplies newest-first rows. Re-sorting all SwiftData faults
        // during each body evaluation turns ordinary page navigation into repeated work.
        if recordSort == "最新优先" { visibleRowsCache = filtered }
        else {
            visibleRowsCache = filtered.sorted {
                switch recordSort {
                case "最早优先": return $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
                case "金额从高到低": return $0.baseAmount == $1.baseAmount ? $0.date > $1.date : $0.baseAmount > $1.baseAmount
                default: return $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
                }
            }
        }
        if !batchSelection.isEmpty { batchSelection.formIntersection(Set(visibleRowsCache.map(\.id))) }
        maximumVisibleAmount = visibleRowsCache.map(\.baseAmount).max() ?? 0
        if let selectedTransactionID, !visibleRowsCache.contains(where: { $0.id == selectedTransactionID }) {
            self.selectedTransactionID = nil; showsDetails = false
        }
    }

    private func refreshLedgerState() {
        activeRowsCache = transactions.filter { $0.deletedAt == nil }
        activeBookCurrencyCache = activeBookCurrencyFromLedger
        filterCurrencyCodes = Array(Set(activeRowsCache.map(\.originalCurrency))).sorted()
        filterCategoryNames = Dictionary(grouping: activeRowsCache, by: \.type).mapValues { Array(Set($0.map(\.category))).sorted() }
        timelineIndex = MacRecordsTimelineIndex(rows: activeRowsCache)
        refreshVisibleRows()
    }

    private var selectedTransaction: Transaction? {
        guard let selectedTransactionID else { return nil }
        return visibleTransactions.first { $0.id == selectedTransactionID }
    }
    private var dateColumnWidth: CGFloat {
        let _ = measuredFontTier; let _ = measuredFontName
        let sample = MacDateDisplay.string(Date()).replacingOccurrences(of: "[0-9]", with: "8", options: .regularExpression)
        return max(92, ceil((sample as NSString).size(withAttributes: [.font: MacInterfaceFonts.font(size: MacUI.fontTier.bodySize, monospacedDigits: true)]).width) + 24)
    }
    private var amountColumnWidth: CGFloat {
        let _ = measuredFontTier; let _ = measuredFontName
        let sample = "−" + MacOverviewStyle.money(maximumVisibleAmount) + (activeBookCurrency == nil ? " XXX" : "")
        return max(110, ceil((sample as NSString).size(withAttributes: [.font: MacInterfaceFonts.font(size: MacUI.fontTier.bodySize, weight: .medium, monospacedDigits: true)]).width) + 28)
    }

    private var categoryColumnWidth: CGFloat {
        let font = MacInterfaceFonts.font(size: MacUI.fontTier.bodySize)
        let names = Set(visibleTransactions.map(\.category))
        let measured = names.map { (MacOverviewStyle.category($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 80
        return max(50, measured + 34)
    }
    private var headerSelectionState: Int { batchSelection.isEmpty ? 0 : batchSelection.count == visibleTransactions.count ? 2 : 1 }
    private func toggleAllRecords() {
        if batchSelection.count == visibleTransactions.count { batchSelection.removeAll() }
        else { selectAllRecords() }
    }
    private func tableSizing(compact: Bool) -> some View {
        MacRecordsTableSizing(dateWidth: dateColumnWidth, amountWidth: amountColumnWidth, categoryWidth: categoryColumnWidth,
            compact: compact, selecting: showsSelectionBoxes, revision: "\(displayLimit)-\(visibleTransactions.count)-\(recordSort)-\(measuredFontName)-\(MacUI.fontTier.bodySize)-\(measuredCustomBody)",
            titles: (showsSelectionBoxes ? [""] : []) + (compact ? ["日期", "类别", "金额（\(activeBookCurrency ?? "本位币")）"] : ["日期", "类别", "备注", "原币", "金额（\(activeBookCurrency ?? "本位币")）"]),
            onRowClick: { index in
                let rows = Array(visibleTransactions.prefix(displayLimit))
                guard !showsSelectionBoxes, rows.indices.contains(index) else { return }
                selectedTransactionID = rows[index].id; showsDetails = true
            }).frame(width: 0, height: 0)
    }
    @ViewBuilder private var headerSelectionCheckbox: some View {
        if showsSelectionBoxes {
            MacRecordsSelectAllCheckbox(state: headerSelectionState, action: toggleAllRecords)
                .frame(width: 18, height: 18).padding(.leading, 16).padding(.top, 5)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let filterWidth = MacUI.filterColumnWidth(available: geometry.size.width, wide: geometry.size.width >= MacUI.space(950))
            let wide = geometry.size.width - filterWidth >= MacUI.space(860)
            HStack(spacing: MacUI.space(0)) {
                timelinePanel.frame(width: filterWidth)
                Divider()
                VStack(alignment: .leading, spacing: MacUI.space(12)) {
                    header
                    if activeBookCurrency == nil {
                        Label("账本含不同本位币，请在设置中核对后再汇总。", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange).accessibilityIdentifier("mixedCurrencyBlocked")
                    }
                    summaryCards(compact: geometry.size.width - filterWidth < MacUI.space(760))
                    filterBar
                    if let saveError {
                        Text("保存失败：\(saveError)").foregroundStyle(.red).accessibilityIdentifier("saveError")
                    }
                    HStack(alignment: .top, spacing: MacUI.space(14)) {
                        VStack(alignment: .leading, spacing: MacUI.space(0)) {
                            tableToolbar
                            Divider()
                            if visibleTransactions.isEmpty {
                                ContentUnavailableView("暂无符合条件的账目", systemImage: "doc.text.magnifyingglass",
                                    description: Text("调整筛选条件，或新增一笔收入与支出。"))
                                    .accessibilityIdentifier("recordsEmptyState")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                GeometryReader { tableGeometry in
                                    let columns = showsSelectionBoxes ? 6 : 5
                                    let checkbox = showsSelectionBoxes ? MacUI.space(26) : 0
                                    let required = dateColumnWidth + amountColumnWidth + MacUI.space(250) + checkbox + CGFloat(columns) * 24 + 20
                                    if tableGeometry.size.width < required { compactTransactionTable(availableWidth: tableGeometry.size.width) }
                                    else { transactionTable(availableWidth: tableGeometry.size.width) }
                                }
                            }
                            if !visibleTransactions.isEmpty { tablePagination }
                        }
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 13))
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.045)))
                        if wide, showsDetails, let row = selectedTransaction {
                            detailPanel(row).frame(width: MacUI.space(260))
                        }
                    }.frame(maxHeight: .infinity)
                    Text("收支汇总使用已保存的本位币金额；明细保留原币与历史汇率。")
                        .appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                }.appPadding(20).frame(width: max(1, geometry.size.width - filterWidth - 1))
            }
            .sheet(isPresented: Binding(get: { !wide && showsDetails && selectedTransaction != nil }, set: { showsDetails = $0 })) {
                if let row = selectedTransaction { detailPanel(row).appPanel(width: 360, height: 560).appPadding(20) }
            }
        }
        .onAppear { refreshLedgerState() }
        .onDisappear {
            guard scope == nil else { return }
            workspace.recordsNavigationState = MacRecordsNavigationState(
                searchText: searchText, typeFilter: typeFilter, dateFilterEnabled: dateFilterEnabled,
                dateFrom: dateFrom, dateThrough: dateThrough, currencyFilter: currencyFilter,
                categoryFilter: categoryFilter, recordSort: recordSort, displayLimit: displayLimit,
                rangeTitle: rangeTitle, expandedYears: expandedYears, expandedMonths: expandedMonths
            )
        }
        .onChange(of: transactions.count) { _, _ in refreshLedgerState() }
        .onChange(of: financeDeposits.count) { _, _ in refreshLedgerState() }
        .onChange(of: financeLoans.count) { _, _ in refreshLedgerState() }
        .onChange(of: financeRules.count) { _, _ in refreshLedgerState() }
        .onChange(of: preferredBookCurrency) { _, _ in refreshLedgerState() }
        .onChange(of: searchText) { _, _ in refreshVisibleRows() }
        .onChange(of: typeFilter) { _, type in
            if type != "All", categoryFilter != "All", !(filterCategoryNames[type] ?? []).contains(categoryFilter) { categoryFilter = "All" }
            refreshVisibleRows()
        }
        .onChange(of: dateFilterEnabled) { _, _ in refreshVisibleRows() }
        .onChange(of: dateFrom) { _, _ in refreshVisibleRows() }
        .onChange(of: dateThrough) { _, _ in refreshVisibleRows() }
        .onChange(of: currencyFilter) { _, _ in refreshVisibleRows() }
        .onChange(of: categoryFilter) { _, _ in refreshVisibleRows() }
        .onChange(of: recordSort) { _, _ in refreshVisibleRows() }
        .onChange(of: batchSelection) { old, value in
            if let id = value.subtracting(old).first ?? value.first {
                selectedTransactionID = id
            } else { selectedTransactionID = nil; showsDetails = false }
        }
        .sheet(item: $editingTransaction) { transaction in
            MacTransactionEditor(
                bookCurrency: activeBookCurrency ?? preferredBookCurrency,
                existing: transaction,
                onSaved: { id in
                    refreshLedgerState()
                    selectedTransactionID = id
                    batchSelection = [id]; showsDetails = true
                    saveError = nil
                }
            )
        }
        .sheet(isPresented: $showsNewTransaction) {
            MacTransactionEditor(
                bookCurrency: activeBookCurrency ?? preferredBookCurrency,
                existing: nil,
                onSaved: { id in
                    refreshLedgerState()
                    selectedTransactionID = id
                    batchSelection = [id]; showsDetails = true
                    saveError = nil
                }
            )
        }
        .sheet(isPresented: $confirmsBatchDelete) {
            VStack(alignment: .leading, spacing: MacUI.space(18)) {
                Text("删除选中的 \(deletableSelection.count) 笔账目？").appFont(.dialogTitle, weight: .semibold)
                Text("仅删除当前筛选结果中选中的普通账目，操作无法撤销。自动生成的入账记录受保护。").foregroundStyle(.secondary)
                if extraDeletionConfirmation { Toggle("我已核对所选账目", isOn: $deletionAcknowledged) }
                HStack {
                    Spacer()
                    Button("取消") { confirmsBatchDelete = false }.accessibilityIdentifier("cancelBatchDeletion")
                    Button("确认删除", role: .destructive) {
                        do {
                            try MacDataManagement.deleteTransactions(deletableSelection, in: modelContext)
                            refreshLedgerState()
                            batchSelection.removeAll(); selectedTransactionID = nil; saveError = nil
                            confirmsBatchDelete = false
                        } catch { saveError = MacLocalization.error(error) }
                    }.accessibilityIdentifier("confirmBatchDeletion").disabled(deletableSelection.isEmpty || (extraDeletionConfirmation && !deletionAcknowledged))
                }
            }.appPadding(24).appDialog(width: 460)
        }
    }

    private var deletableSelection: [Transaction] {
        visibleTransactions.filter { batchSelection.contains($0.id) && !MacTransactionCRUD.isProtectedGeneratedPosting($0) }
    }
    private var header: some View {
        HStack {
            Text(rangeTitle).appFont(.body, weight: .medium, design: .default).foregroundStyle(.secondary)
                .accessibilityIdentifier("recordsTitle")
            if MacPreferences.isTesting && ProcessInfo.processInfo.environment["FINTRACK_V2_DEMO"] == "1" {
                Text("演示账本（虚构）").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            }
            Spacer()
            if isNewLedger {
                MacCurrencyMenu(selection:$preferredBookCurrency,codes:["USD","RUB","EUR","CNY"],identifier:"bookCurrencyPicker")
            } else {
                Text("本位币  \(activeBookCurrency ?? "待核对")").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            }
            Button { showsNewTransaction = true } label: { Label("新增账目", systemImage: "plus") }
                .buttonStyle(.borderedProminent).tint(MacOverviewStyle.accent)
                .accessibilityIdentifier("addEntry").disabled(activeBookCurrency == nil)
        }
    }
    @ViewBuilder private func summaryCards(compact: Bool) -> some View {
        if compact {
            VStack(spacing: MacUI.space(8)) {
                compactMetric("支出", amount: totals.expense, color: MacOverviewStyle.expense, id: "bookExpense", filter: "Expense")
                compactMetric("收入", amount: totals.income, color: MacOverviewStyle.income, id: "bookIncome", filter: "Income")
                compactMetric("净额", amount: totals.net, color: .primary, id: "bookNet", filter: "All")
            }.appPadding(12).background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 13))
        } else {
        HStack(spacing: MacUI.space(12)) {
            metric("支出", amount: totals.expense, color: MacOverviewStyle.expense, id: "bookExpense", filter: "Expense")
            metric("收入", amount: totals.income, color: MacOverviewStyle.income, id: "bookIncome", filter: "Income")
            metric("净额", amount: totals.net, color: .primary, id: "bookNet", filter: "All")
        }
        }
    }
    private func compactMetric(_ title: String, amount: Double, color: Color, id: String, filter: String) -> some View {
        Button { typeFilter = filter } label: {
            HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(MacOverviewStyle.money(amount) + " " + (activeBookCurrency ?? "")).monospacedDigit().foregroundStyle(color) }
                .appFont(.body, weight: .medium).contentShape(Rectangle())
        }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier(id).accessibilityLabel(title + "：" + MacOverviewStyle.money(amount))
    }
    private func metric(_ title: String, amount: Double, color: Color, id: String, filter: String) -> some View {
        Button { typeFilter = filter } label: {
            VStack(alignment: .leading, spacing: MacUI.space(9)) {
                Text(title).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                Text(activeBookCurrency == nil ? "—" : MacOverviewStyle.money(amount))
                    .appFont(.amount, weight: .semibold, design: .default).monospacedDigit().foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.5).allowsTightening(true).accessibilityIdentifier(id)
                Text(activeBookCurrency ?? "本位币待核对").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
            }.appPadding(15).frame(maxWidth: .infinity, alignment: .leading).appMinHeight(108)
                .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.04)))
        }.buttonStyle(MacInteractiveButtonStyle()).appHelp("查看当前范围的\(title == "净额" ? "全部账目" : title + "账目")")
            .accessibilityLabel("\(title)：\(activeBookCurrency == nil ? "—" : MacOverviewStyle.money(amount)) \(activeBookCurrency ?? "")")
            .accessibilityIdentifier(id)
    }
    private var filterBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MacUI.space(10)) { typePicker; categoryPicker; currencyPicker; Spacer(minLength: 8); clearFilters }
            VStack(alignment: .leading, spacing: MacUI.space(8)) {
                HStack(spacing: MacUI.space(10)) { typePicker; currencyPicker; Spacer(minLength: 0) }
                HStack { categoryPicker; Spacer(); clearFilters }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("recordFilters")
    }
    private var typePicker: some View {
        MacIconMenu(selection:$typeFilter,options:[
            .init(title:"全部收支",value:"All",symbol:"arrow.up.arrow.down"),
            .init(title:"收入",value:"Income",symbol:"arrow.down.left"),
            .init(title:"支出",value:"Expense",symbol:"arrow.up.right")
        ],identifier:"recordTypeFilter",accessibilityTitle:"收支",width:148)
    }
    private var categoryPicker: some View {
        let separator = "\u{1f}"
        var options: [MacIconMenuOption] = [.init(title:"全部类别",value:"All",symbol:"square.grid.2x2")]
        // Scope drill-downs can intentionally select a name across both types.
        if categoryFilter != "All", typeFilter == "All" {
            options.append(.init(title:MacOverviewStyle.category(categoryFilter),value:"All" + separator + categoryFilter,symbol:"tag"))
        }
        let styles: [String:MacCategoryStyle] = MacSettingsStore.load("v2_category_styles",fallback:[:])
        let types = TransactionType(rawValue:typeFilter).map { [$0] } ?? [.income,.expense]
        for type in types {
            let names = filterCategoryNames[type.rawValue] ?? []
            if !names.isEmpty {
                options.append(.init(title:type == .income ? "收入分类" : "支出分类",value:nil))
                options += names.map { name in
                    .init(title:MacOverviewStyle.category(name),value:type.rawValue + separator + name,
                          image:MacCategoryCatalog.menuImage(style:MacCategoryCatalog.style(name:name,type:type.rawValue,in:styles),name:name))
                }
            }
        }
        return MacIconMenu(selection:Binding(get:{
            categoryFilter == "All" ? "All" : typeFilter + separator + categoryFilter
        },set:{ value in
            if value == "All" { categoryFilter = "All" }
            else if let boundary = value.firstIndex(of:"\u{1f}") {
                typeFilter = String(value[..<boundary]); categoryFilter = String(value[value.index(after:boundary)...])
            }
        }),options:options,identifier:"recordCategoryFilter",accessibilityTitle:"类别",width:164)
    }
    private var currencyPicker: some View {
        MacCurrencyMenu(selection:$currencyFilter,codes:filterCurrencyCodes,identifier:"recordCurrencyFilter",prefixOptions:[("全部币种","All")])
    }
    private var clearFilters: some View {
        Button("重置") {
            searchText = ""; typeFilter = "All"; categoryFilter = "All"; currencyFilter = "All"
            dateFilterEnabled = false; rangeTitle = "全部记录"
        }.buttonStyle(MacInteractiveButtonStyle()).foregroundStyle(MacOverviewStyle.accent).accessibilityIdentifier("recordReset")
    }
    private var tableToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MacUI.space(12)) { tableCount; sortPicker; detailsButton; Spacer(); selectionActions; exportButton }
            VStack(alignment: .leading, spacing: MacUI.space(9)) {
                HStack { tableCount; Spacer(); sortPicker }
                HStack { detailsButton; Spacer(); selectionActions; exportButton }
            }
        }.appPadding(.horizontal, 12).appPadding(.vertical, 8)
    }
    @ViewBuilder private var selectionActions: some View {
        if showsSelectionBoxes {
            Text("已选 \(batchSelection.count) 笔").appFont(.caption).foregroundStyle(.secondary)
            Button("取消") { selectionMode = false; batchSelection.removeAll() }.accessibilityIdentifier("recordCancelSelection")
            Button("删除", role: .destructive) { deletionAcknowledged = false; confirmsBatchDelete = true }
                .disabled(deletableSelection.isEmpty).accessibilityIdentifier("recordDeleteSelection")
        } else {
            Button("多选") { selectionMode = true; showsDetails = false }.disabled(visibleTransactions.isEmpty).accessibilityIdentifier("recordStartSelection")
        }
    }
    private var tablePagination: some View {
        VStack(spacing:0) {
            Divider()
            HStack {
                Text("已显示 \(min(displayLimit, visibleTransactions.count)) / \(visibleTransactions.count) 笔")
                    .appFont(.caption).foregroundStyle(.secondary).accessibilityIdentifier("recordDisplayedCount")
                Spacer()
                if displayLimit < visibleTransactions.count {
                    Button("显示更多") { displayLimit += MacPreferences.defaults.object(forKey: "v2_page_size") as? Int ?? 50 }
                        .accessibilityIdentifier("recordLoadMore")
                }
            }.appPadding(.horizontal, 12).appPadding(.vertical, 8)
        }
    }
    private var tableCount: some View {
        Text("\(visibleTransactions.count) 笔账目").appFont(.caption, weight: .medium, design: .default)
            .accessibilityIdentifier("transactionCount")
    }
    private var sortPicker: some View {
        MacSettingsMenu(selection: $recordSort, options: ["最新优先", "最早优先", "金额从高到低"].map { ($0, $0) }).frame(width: max(132, MacUI.fontTier.bodySize * 7 + 32)).accessibilityIdentifier("recordSort")
    }
    private var batchMenu: some View {
        Menu("批量操作\(batchSelection.isEmpty ? "" : "（\(batchSelection.count)）")") {
            Button("选择当前普通账目") { batchSelection = Set(visibleTransactions.filter { !MacTransactionCRUD.isProtectedGeneratedPosting($0) }.map(\.id)) }
                .accessibilityIdentifier("selectVisibleRecords")
            Button("清除选择") { batchSelection.removeAll() }.disabled(batchSelection.isEmpty)
            Divider()
            Button("删除选中账目", role: .destructive) { deletionAcknowledged = false; confirmsBatchDelete = true }
                .disabled(deletableSelection.isEmpty).accessibilityIdentifier("deleteSelectedRecords")
        }.menuStyle(.borderlessButton).fixedSize().accessibilityIdentifier("recordBatchMenu")
    }
    private var detailsButton: some View {
        Button { showsDetails = true } label: { Image(systemName: "sidebar.right") }
            .buttonStyle(MacInteractiveButtonStyle()).disabled(selectedTransaction == nil).appHelp("查看选中账目的详情")
            .accessibilityLabel("查看交易详情").accessibilityIdentifier("recordOpenDetails")
    }
    private var exportButton: some View {
        Button { exportVisibleTransactions() } label: { Label("导出", systemImage: "square.and.arrow.up") }
            .buttonStyle(MacInteractiveButtonStyle()).disabled(visibleTransactions.isEmpty).appHelp("将当前筛选结果导出为 CSV")
            .accessibilityIdentifier("recordExport")
    }
    private func selectAllRecords() {
        selectionMode = true; showsDetails = false
        displayLimit = max(displayLimit, visibleTransactions.count)
        batchSelection = Set(visibleTransactions.map(\.id))
    }
    private func selectionCheckbox(_ row: Transaction) -> some View {
        Toggle("选择账目", isOn: Binding(get: { batchSelection.contains(row.id) }, set: { value in
            selectionMode = true
            if value { batchSelection.insert(row.id) } else { batchSelection.remove(row.id) }
        })).toggleStyle(.checkbox).labelsHidden().accessibilityIdentifier("recordSelect-" + row.id.uuidString)
    }
    @ViewBuilder private func recordContextMenu(_ ids: Set<UUID>) -> some View {
        let rows = visibleTransactions.filter { ids.contains($0.id) }
        if rows.count == 1, let row = rows.first {
            Button("查看详情", systemImage: "sidebar.right") { selectedTransactionID = row.id; showsDetails = true }
            Button("编辑", systemImage: "pencil") { editingTransaction = row }.disabled(activeBookCurrency == nil || MacTransactionCRUD.isProtectedGeneratedPosting(row))
        }
        if !rows.isEmpty {
            Button(rows.count == 1 ? "删除账目" : "删除选中的 \(rows.count) 笔账目", systemImage: "trash", role: .destructive) {
                batchSelection = ids; deletionAcknowledged = false; confirmsBatchDelete = true
            }.disabled(rows.allSatisfy(MacTransactionCRUD.isProtectedGeneratedPosting))
            Divider()
        }
        Button(showsSelectionBoxes ? "结束多选" : "多选", systemImage: "checklist") {
            if showsSelectionBoxes { selectionMode = false; batchSelection.removeAll() }
            else { selectionMode = true; batchSelection.formUnion(ids); showsDetails = false }
        }.accessibilityIdentifier("recordContextMultiSelect")
        Button("全选", systemImage: "checkmark.circle") { selectAllRecords() }.keyboardShortcut("a", modifiers: .command).disabled(visibleTransactions.isEmpty).accessibilityIdentifier("recordContextSelectAll")
        Button("取消选择") { batchSelection.removeAll() }.disabled(batchSelection.isEmpty)
    }
    private func transactionTable(availableWidth: CGFloat) -> some View {
        let columns = showsSelectionBoxes ? 6 : 5
        let checkbox = showsSelectionBoxes ? MacUI.space(26) : 0
        let category = MacUI.space(150)
        let notes = max(60, availableWidth - dateColumnWidth - amountColumnWidth - category - MacUI.space(50) - checkbox - CGFloat(columns) * 24 - 20)
        return Table(Array(visibleTransactions.prefix(displayLimit)), selection: $batchSelection) {
            if showsSelectionBoxes {
                TableColumn("") { row in selectionCheckbox(row) }.width(MacUI.space(26))
            }
            TableColumn("日期") { row in
                Text(MacDateDisplay.string(row.date))
                    .appFont(.body, weight: .regular, design: .default)
                    .monospacedDigit()
            }.width(min: 60, ideal: dateColumnWidth, max: 600)
            TableColumn("类别") { row in categoryCell(row) }.width(min: 35, ideal: category, max: 2000)
            TableColumn("备注") { row in
                Text(showsNotesPreview ? (MacFinanceNotes.visible(row.note).isEmpty ? "—" : MacFinanceNotes.visible(row.note)) : "—").appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary).lineLimit(1)
            }.width(min: 35, ideal: notes, max: 10000)
            TableColumn("原币") { row in Text(row.originalCurrency).appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary) }
                .width(min: 42, ideal: 50, max: 200)
            TableColumn("金额（\(activeBookCurrency ?? "本位币")）") { row in signedTableAmount(row) }
                .width(min: 65, ideal: amountColumnWidth, max: 2000).alignment(.trailing)
        }.tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: UUID.self, menu: { ids in recordContextMenu(ids) }, primaryAction: { ids in
                if !showsSelectionBoxes, let id = ids.first { selectedTransactionID = id; showsDetails = true }
            })
            .background(MacRecordsKeyboardActions(selectAll: selectAllRecords).frame(width: 0, height: 0))
            .accessibilityIdentifier("recordsTable")
            .background(tableSizing(compact: false))
            .overlay(alignment: .topLeading) { headerSelectionCheckbox }
            .id("full-\(showsSelectionBoxes)")

    }
    private func compactTransactionTable(availableWidth: CGFloat) -> some View {
        let columns = showsSelectionBoxes ? 4 : 3
        let category = max(40, availableWidth - dateColumnWidth - amountColumnWidth - (showsSelectionBoxes ? MacUI.space(26) : 0) - CGFloat(columns) * 24 - 20)
        return Table(Array(visibleTransactions.prefix(displayLimit)), selection: $batchSelection) {
            if showsSelectionBoxes {
                TableColumn("") { row in selectionCheckbox(row) }.width(MacUI.space(26))
            }
            TableColumn("日期") { row in Text(MacDateDisplay.string(row.date)).appFont(.body, weight: .regular, design: .default).monospacedDigit() }.width(min: 60, ideal: dateColumnWidth, max: 600)
            TableColumn("类别") { row in categoryCell(row) }.width(min: 35, ideal: category, max: 2000)
            TableColumn("金额（\(activeBookCurrency ?? "本位币")）") { row in
                VStack(alignment:.trailing,spacing:1) {
                    signedTableAmount(row)
                    if row.originalCurrency != row.baseCurrencyCode {
                        Text("原币 " + row.originalCurrency).appFont(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth:.infinity,alignment:.trailing)
            }.width(min: 65, ideal: amountColumnWidth, max: 2000).alignment(.trailing)
        }.tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: UUID.self, menu: { ids in recordContextMenu(ids) }, primaryAction: { ids in
                if !showsSelectionBoxes, let id = ids.first { selectedTransactionID = id; showsDetails = true }
            })
            .background(MacRecordsKeyboardActions(selectAll: selectAllRecords).frame(width: 0, height: 0)).accessibilityIdentifier("recordsTable")
            .background(tableSizing(compact: true))
            .overlay(alignment: .topLeading) { headerSelectionCheckbox }
            .id("compact-\(showsSelectionBoxes)")

    }
    private func categoryCell(_ row: Transaction) -> some View {
        HStack(spacing: 6) {
            MacCategoryBadge(name: row.category, type: row.type, size: 22)
            Text(MacOverviewStyle.category(row.category)).lineLimit(1).truncationMode(.tail).frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
            if MacTransactionCRUD.isProtectedGeneratedPosting(row) { Image(systemName:"lock").appFont(.caption).fixedSize() }
        }.appFont(.body).frame(maxWidth:.infinity,alignment:.leading).appHelp(MacOverviewStyle.category(row.category))
            .accessibilityElement(children: .ignore).accessibilityLabel(MacOverviewStyle.category(row.category))
            .accessibilityIdentifier("recordRow-" + row.id.uuidString)
    }
    private func signedTableAmount(_ row: Transaction) -> some View {
        let income = row.typedType == .income
        return Text((income ? "+" : "−") + MacOverviewStyle.money(row.baseAmount)
                    + (activeBookCurrency == nil ? " " + row.baseCurrencyCode : ""))
            .appFont(.body, weight: .medium).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            .foregroundStyle(income ? MacOverviewStyle.income : MacOverviewStyle.expense)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("recordAmount-" + row.id.uuidString)
            .accessibilityLabel((income ? "收入 " : "支出 ") + MacOverviewStyle.money(row.baseAmount) + " " + row.baseCurrencyCode)
    }
    private func detailPanel(_ row: Transaction) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(18)) {
            HStack {
                Text("交易详情").appFont(.section, weight: .semibold); Spacer()
                Button { showsDetails = false } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }
                    .buttonStyle(MacInteractiveButtonStyle()).accessibilityLabel("关闭详情").accessibilityIdentifier("recordCloseDetails")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: MacUI.space(18)) {
                    Label(row.typedType == .income ? "收入" : "支出", systemImage: row.typedType == .income ? "arrow.down.left" : "arrow.up.right")
                        .appFont(.caption, weight: .regular).foregroundStyle(row.typedType == .income ? MacOverviewStyle.income : MacOverviewStyle.expense)
                    Text(MacOverviewStyle.money(row.originalAmount)).appFont(.amount, weight: .semibold, design: .default).monospacedDigit()
                    Text(row.originalCurrency).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    Divider()
                    detailField("类别", value: MacOverviewStyle.category(row.category), id: "recordSelectedCategory")
                    detailField("日期", value: MacDateDisplay.string(row.date), id: "recordDetailDate")
                    detailField("记账金额", value: "\(MacOverviewStyle.money(row.baseAmount)) \(row.baseCurrencyCode)", id: "recordBookAmount")
                    detailField("记账时汇率", value: row.exchangeRateToBase.formatted(.number.precision(.fractionLength(0...8))), id: "recordStoredFX")
                    detailField("备注", value: MacFinanceNotes.visible(row.note).isEmpty ? "无备注" : MacFinanceNotes.visible(row.note), id: "recordDetailNote")
                    if MacTransactionCRUD.isProtectedGeneratedPosting(row) {
                        Label("自动入账记录，请到对应财务页面核对。", systemImage: "lock").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            Divider()
            HStack {
                Button("编辑") { editingTransaction = row }.accessibilityIdentifier("editEntry")
                    .disabled(activeBookCurrency == nil || MacTransactionCRUD.isProtectedGeneratedPosting(row))
                Spacer()
                Button("删除", role: .destructive) { deletionAcknowledged = false; showsDeleteConfirmation = true }.accessibilityIdentifier("deleteEntry")
                    .disabled(MacTransactionCRUD.isProtectedGeneratedPosting(row))
            }
        }.appPadding(18).frame(maxHeight: .infinity)
            .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.045)))
        .sheet(isPresented: $showsDeleteConfirmation) {
            VStack(alignment: .leading, spacing: MacUI.space(18)) {
                Text("删除这笔账目？")
                    .appFont(.dialogTitle, weight: .semibold)
                    .accessibilityIdentifier("deleteConfirmationTitle")
                Text("账目将从本地账本删除，此操作无法撤销。")
                    .foregroundStyle(.secondary)
                if extraDeletionConfirmation { Toggle("我已核对此笔账目", isOn: $deletionAcknowledged) }
                HStack {
                    Spacer()
                    Button("取消") { showsDeleteConfirmation = false }
                        .accessibilityIdentifier("cancelDeleteEntry")
                    Button("删除", role: .destructive) {
                        guard let selectedTransaction else { return }
                        do {
                            try MacTransactionCRUD.delete(selectedTransaction, in: modelContext)
                            refreshLedgerState()
                            selectedTransactionID = nil
                            saveError = nil
                            showsDeleteConfirmation = false
                        } catch { saveError = MacLocalization.error(error) }
                    }
                    .accessibilityIdentifier("confirmDeleteEntry").disabled(extraDeletionConfirmation && !deletionAcknowledged)
                }
            }
            .appPadding(24)
            .appDialog(width: 460)
        }
    }
    private func detailField(_ label: String, value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(5)) {
            Text(label).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
            Text(value).appFont(.body, weight: .regular, design: .default).accessibilityIdentifier(id)
        }
    }
    private var timelinePanel: some View {
        VStack(alignment: .leading, spacing: MacUI.space(16)) {
            Text("筛选").appFont(.section, weight: .semibold)
            TextField("搜索账目", text: $searchText).textFieldStyle(.roundedBorder)
                .appHelp("可按类别、备注或币种搜索")
                .accessibilityLabel("搜索类别、备注或币种")
                .accessibilityIdentifier("recordSearch")
            ScrollView {
                VStack(alignment: .leading, spacing: MacUI.space(5)) {
                    rangeButton("全部记录", icon: "tray.full", id: "recordAll", selected: !dateFilterEnabled) {
                        dateFilterEnabled = false; rangeTitle = "全部记录"
                    }
                    rangeButton("最近30天", icon: "clock", id: "recordRecent", selected: rangeTitle == "最近30天") {
                        dateFrom = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: Date()))!
                        dateThrough = Date(); dateFilterEnabled = true; rangeTitle = "最近30天"
                    }
                    Divider().appPadding(.vertical, 10)
                    Text("按日期浏览").appFont(.caption, weight: .semibold, design: .default).foregroundStyle(.secondary)
                    ForEach(years, id: \.self) { year in
                        VStack(alignment: .leading, spacing: MacUI.space(5)) {
                            HStack(spacing: MacUI.space(3)) {
                                disclosure(expandedYears.contains(year), id: "recordExpandYear-\(year)") {
                                    if expandedYears.contains(year) { expandedYears.remove(year) } else { expandedYears.insert(year) }
                                }
                                Button { selectPeriod(year: year) } label: {
                                    treeLabel("\(year)年", count: timelineIndex.count(year: year), selected: rangeTitle == "\(year)年")
                                }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("recordYear-\(year)")
                            }
                            if expandedYears.contains(year) {
                                ForEach(months(in: year), id: \.self) { month in monthNode(year: year, month: month) }
                                    .appPadding(.leading, 7)
                            }
                        }.appPadding(.vertical, 4)
                    }
                }
            }.accessibilityIdentifier("recordTimeline")
            Divider()
            Toggle("限定日期", isOn: $dateFilterEnabled).toggleStyle(.checkbox).appFont(.caption, weight: .regular)
                .accessibilityIdentifier("recordDateEnabled")
            if dateFilterEnabled {
                MacDateTimeField(title: "从", date: $dateFrom).accessibilityIdentifier("recordFrom")
                MacDateTimeField(title: "至", date: $dateThrough).accessibilityIdentifier("recordThrough")
            }
        }.appPadding(18).frame(maxHeight: .infinity).background(MacOverviewStyle.filters)
        .onChange(of: dateFrom) { _, _ in updateRangeTitle() }
        .onChange(of: dateThrough) { _, _ in updateRangeTitle() }
        .onChange(of: dateFilterEnabled) { _, enabled in if !enabled { rangeTitle = "全部记录" } }
    }
    private var years: [Int] { timelineIndex.years }
    private func rows(year: Int, month: Int? = nil) -> [Transaction] { timelineIndex.rows(in: year, month: month) }
    private func months(in year: Int) -> [Int] { timelineIndex.months(in: year) }
    private func monthNode(year: Int, month: Int) -> some View {
        let key = "\(year)-\(month)"
        let days = timelineIndex.days(in: year, month: month)
        return VStack(alignment: .leading, spacing: MacUI.space(3)) {
            HStack(spacing: MacUI.space(3)) {
                disclosure(expandedMonths.contains(key), id: "recordExpandMonth-\(key)") {
                    if expandedMonths.contains(key) { expandedMonths.remove(key) } else { expandedMonths.insert(key) }
                }
                Button { selectPeriod(year: year, month: month) } label: {
                    treeLabel("\(month)月", count: timelineIndex.count(year: year, month: month), selected: rangeTitle == "\(year)年\(month)月")
                }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("recordMonth-\(key)")
            }
            if expandedMonths.contains(key) {
                ForEach(days, id: \.self) { day in
                    Button { selectDay(day) } label: {
                    treeLabel("\(Calendar.current.component(.day, from: day))日",
                            count: timelineIndex.count(on: day),
                            selected: dateFilterEnabled && Calendar.current.isDate(dateFrom, inSameDayAs: day) && Calendar.current.isDate(dateThrough, inSameDayAs: day))
                    }.buttonStyle(MacInteractiveButtonStyle()).appPadding(.leading, 18)
                        .accessibilityIdentifier("recordDay-\(year)-\(month)-\(Calendar.current.component(.day, from: day))")
                }
            }
        }.appPadding(.vertical, 3)
    }
    private func disclosure(_ expanded: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right").appFont(.caption, weight: .semibold, design: .default)
                .foregroundStyle(.secondary).frame(width: MacUI.space(14), height: MacUI.space(26)).contentShape(Rectangle())
        }.buttonStyle(MacInteractiveButtonStyle()).accessibilityLabel(expanded ? "收起目录" : "展开目录").accessibilityIdentifier(id)
    }

    private func treeLabel(_ text: String, count: Int, selected: Bool) -> some View {
        HStack(spacing: MacUI.space(3)) {
            Text(text).appFont(.caption, weight: .regular, design: .default); Spacer(minLength: 2)
            Text("\(count)").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
        }.appPadding(.vertical, 6).appPadding(.horizontal, 5).frame(maxWidth: .infinity).contentShape(Rectangle())
            .foregroundStyle(selected ? MacOverviewStyle.accent : .primary)
            .background(selected ? MacOverviewStyle.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
    private func rangeButton(_ text: String, icon: String, id: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: icon).appFont(.caption, weight: .regular, design: .default).frame(maxWidth: .infinity, alignment: .leading).appPadding(9)
                .foregroundStyle(selected ? MacOverviewStyle.accent : .primary)
                .background(selected ? MacOverviewStyle.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier(id)
    }
    private func selectPeriod(year: Int, month: Int? = nil) {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: year, month: month ?? 1, day: 1))!
        let range = calendar.dateInterval(of: month == nil ? .year : .month, for: start)!
        dateFrom = range.start; dateThrough = range.end.addingTimeInterval(-1); dateFilterEnabled = true
        rangeTitle = month.map { "\(year)年\($0)月" } ?? "\(year)年"
    }
    private func selectDay(_ date: Date) {
        dateFrom = date; dateThrough = date; dateFilterEnabled = true
        rangeTitle = date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_Hans_CN")))
    }
    private func updateRangeTitle() {
        guard dateFilterEnabled else { return }
        let calendar = Calendar.current
        let range = MacRecordsFilter.inclusiveDays(from: dateFrom, through: dateThrough)
        if calendar.isDate(dateFrom, inSameDayAs: dateThrough) {
            rangeTitle = MacDateDisplay.string(dateFrom)
        } else if range == calendar.dateInterval(of: .year, for: dateFrom) {
            rangeTitle = "\(calendar.component(.year, from: dateFrom))年"
        } else if range == calendar.dateInterval(of: .month, for: dateFrom) {
            rangeTitle = "\(calendar.component(.year, from: dateFrom))年\(calendar.component(.month, from: dateFrom))月"
        } else if calendar.isDate(dateThrough, inSameDayAs: Date()),
                  calendar.dateComponents([.day], from: range.start, to: range.end).day == 30 {
            rangeTitle = "最近30天"
        } else {
            rangeTitle = "\(MacDateDisplay.string(dateFrom)) – \(MacDateDisplay.string(dateThrough))"
        }
    }

    private func exportVisibleTransactions() {
        guard let url = CSVExporter.exportTransactionsCSV(transactions: visibleTransactions) else {
            feedback.show(.failure,title:"导出失败",message:"无法生成 CSV 文件，请重试。")
            return
        }
        defer { try? FileManager.default.removeItem(at:url) }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]; panel.nameFieldStringValue = url.lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try Data(contentsOf: url).write(to: destination, options: .atomic); saveError = nil
            feedback.show(.success,title:"导出成功",message:"已导出 \(visibleTransactions.count) 笔账目。\n\(destination.lastPathComponent)")
        } catch {
            saveError = MacLocalization.error(error)
            feedback.show(.failure,title:"导出失败",message:MacLocalization.error(error))
        }
    }

}
