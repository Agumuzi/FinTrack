import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// Native record editing, search, filtering, export and batch actions.
struct MacRecordSection: View {
    @ObservedObject private var localizationState = LocalizationController.shared
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
            _rangeTitle = State(initialValue: MacRecordRangeIdentity.resolve(from: scope.interval()?.start ?? scope.from, through: scope.interval().map { $0.end.addingTimeInterval(-1) } ?? scope.through, enabled: scope.interval() != nil))
            _dateFilterEnabled = State(initialValue: scope.interval() != nil)
            _dateFrom = State(initialValue: scope.interval()?.start ?? scope.from)
            _dateThrough = State(initialValue: scope.interval().map { $0.end.addingTimeInterval(-1) } ?? scope.through)
            _categoryFilter = State(initialValue: scope.category ?? "All")
            _typeFilter = State(initialValue: scope.type?.rawValue ?? "All")
        } else {
            _rangeTitle = State(initialValue: MacRecordRangeIdentity.normalize(navigationState.rangeTitle, from: navigationState.dateFrom, through: navigationState.dateThrough, enabled: navigationState.dateFilterEnabled))
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
    @State private var recordSort = MacRecordSort.stored(MacPreferences.defaults.string(forKey: "v2_sort")).legacyValue
    @State private var displayLimit = MacPreferences.defaults.object(forKey: "v2_page_size") as? Int ?? 50
    @AppStorage("v2_notes") private var showsNotesPreview = true
    @State private var rangeTitle = MacRecordRangeIdentity.all
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
            compact: compact, selecting: showsSelectionBoxes, revision: "\(displayLimit)-\(visibleTransactions.count)-\(recordSort)-\(measuredFontName)-\(MacUI.fontTier.bodySize)-\(measuredCustomBody)-\(localizationState.effectiveLanguage)",
            titles: (showsSelectionBoxes ? [""] : []) + (compact ? [L10n.text("Date"), L10n.text("Category"), L10n.text("Amount") + " (\(activeBookCurrency ?? "—"))"] : [L10n.text("Date"), L10n.text("Category"), L10n.text("Note"), L10n.text("Original Currency"), L10n.text("Amount") + " (\(activeBookCurrency ?? "—"))"]),
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
            let shortViewport = geometry.size.height < MacUI.space(620)
            HStack(spacing: MacUI.space(0)) {
                timelinePanel.frame(width: filterWidth)
                Divider()
                VStack(alignment: .leading, spacing: MacUI.space(12)) {
                    header
                    if activeBookCurrency == nil {
                        Label(L10n.text("mac.recordsView.GeometryReader.833b01ff62"), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange).accessibilityIdentifier("mixedCurrencyBlocked")
                    }
                    summaryCards(compact: geometry.size.width - filterWidth < MacUI.space(760))
                    filterBar
                    if let saveError {
                        Text(L10n.format("mac.recordsView.GeometryReader.fcc6eb49b9", "\(saveError)")).foregroundStyle(.red).accessibilityIdentifier("saveError")
                    }
                    HStack(alignment: .top, spacing: MacUI.space(14)) {
                        VStack(alignment: .leading, spacing: MacUI.space(0)) {
                            tableToolbar
                            Divider()
                            if visibleTransactions.isEmpty {
                                ContentUnavailableView(L10n.text("mac.recordsView.ContentUnavailableView.1931f99d4e"), systemImage: "doc.text.magnifyingglass",
                                    description: Text(L10n.text("mac.recordsView.ContentUnavailableView.9e598dcedd")))
                                    .accessibilityIdentifier("recordsEmptyState")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                GeometryReader { tableGeometry in
                                    let columns = showsSelectionBoxes ? 6 : 5
                                    let checkbox = showsSelectionBoxes ? MacUI.space(26) : 0
                                    let required = dateColumnWidth + amountColumnWidth + max(100,MacUI.fontTier.bodySize*4+36) + max(48,MacUI.fontTier.bodySize*2.1+24) + max(120,MacUI.fontTier.bodySize*5) + checkbox + CGFloat(columns)*24+20
                                    let compactMinimum=dateColumnWidth+amountColumnWidth+max(60,MacUI.fontTier.bodySize*2+30)+checkbox+92
                                    if tableGeometry.size.width < compactMinimum {cardTransactionList}
                                    else if tableGeometry.size.width < required { compactTransactionTable(availableWidth: tableGeometry.size.width) }
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
                    }.frame(minHeight: shortViewport ? MacUI.space(230) : 0, maxHeight: .infinity)
                    Text(L10n.text("mac.recordsView.GeometryReader.d43c44bc11"))
                        .appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                }.appPadding(20).frame(width: max(1, geometry.size.width - filterWidth - 1))
                    .modifier(MacRecordsPageScrolling(enabled:shortViewport))
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
                Text(L10n.format("mac.recordsView.body.561e8cb9a5", Int64(deletableSelection.count))).appFont(.dialogTitle, weight: .semibold)
                Text(L10n.text("mac.recordsView.body.75bf1269a1")).foregroundStyle(.secondary)
                if extraDeletionConfirmation { Toggle(L10n.text("mac.recordsView.body.4fe4c86b61"), isOn: $deletionAcknowledged) }
                HStack {
                    Spacer()
                    Button(L10n.text("mac.recordsView.body.2cd0f3be87")) { confirmsBatchDelete = false }.accessibilityIdentifier("cancelBatchDeletion")
                    Button(L10n.text("mac.recordsView.body.a3ea3c17b4"), role: .destructive) {
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
    private var recordRangeTitle: some View {
        Text(MacRecordRangeIdentity.title(rangeTitle, from: dateFrom, through: dateThrough))
            .appFont(.body, weight: .medium).foregroundStyle(.secondary)
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("recordsTitle")
    }
    @ViewBuilder private var recordCurrency: some View {
        if isNewLedger {
            MacCurrencyMenu(selection:$preferredBookCurrency,codes:["USD","RUB","EUR","CNY"],identifier:"bookCurrencyPicker")
        } else {
            Text(L10n.format("mac.recordsView.header.08cd60a4dc", "\(activeBookCurrency ?? L10n.text("mac.recordsView.header.33df16b4af"))"))
                .appFont(.caption).foregroundStyle(.secondary).fixedSize(horizontal:true,vertical:false)
        }
    }
    private var newRecordButton: some View {
        Button { showsNewTransaction = true } label: {
            Label(L10n.text("mac.recordsView.header.61a6ed6623"),systemImage:"plus").fixedSize(horizontal:true,vertical:false)
        }.buttonStyle(.borderedProminent).tint(MacOverviewStyle.accent)
            .accessibilityIdentifier("addEntry").disabled(activeBookCurrency == nil)
    }
    private var recordHeaderActions: some View {
        ViewThatFits(in:.horizontal) {
            HStack { recordCurrency; Spacer(minLength:12); newRecordButton }
            VStack(alignment:.leading,spacing:8) {recordCurrency;newRecordButton}
        }
    }
    private var header: some View {
        ViewThatFits(in:.horizontal) {
            HStack {recordRangeTitle;Spacer(minLength:16);recordCurrency;newRecordButton}
            VStack(alignment:.leading,spacing:MacUI.space(10)) {recordRangeTitle;recordHeaderActions}
        }
    }
    @ViewBuilder private func summaryCards(compact: Bool) -> some View {
        if compact {
            VStack(spacing: MacUI.space(8)) {
                compactMetric(L10n.text("mac.recordsView.compactMetric.e679096865"), amount: totals.expense, color: MacOverviewStyle.expense, id: "bookExpense", filter: "Expense")
                compactMetric(L10n.text("mac.recordsView.compactMetric.117d8f914d"), amount: totals.income, color: MacOverviewStyle.income, id: "bookIncome", filter: "Income")
                compactMetric(L10n.text("mac.recordsView.compactMetric.d26ca9aea9"), amount: totals.net, color: .primary, id: "bookNet", filter: "All")
            }.appPadding(12).background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 13))
        } else {
        HStack(spacing: MacUI.space(12)) {
            metric(L10n.text("mac.recordsView.metric.e679096865"), amount: totals.expense, color: MacOverviewStyle.expense, id: "bookExpense", filter: "Expense")
            metric(L10n.text("mac.recordsView.metric.117d8f914d"), amount: totals.income, color: MacOverviewStyle.income, id: "bookIncome", filter: "Income")
            metric(L10n.text("mac.recordsView.metric.d26ca9aea9"), amount: totals.net, color: .primary, id: "bookNet", filter: "All")
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
                Text(activeBookCurrency ?? L10n.text("mac.recordsView.metric.b837dbe9c8")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
            }.appPadding(15).frame(maxWidth: .infinity, alignment: .leading).appMinHeight(108)
                .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.04)))
        }.buttonStyle(MacInteractiveButtonStyle()).appHelp(L10n.format("mac.recordsView.metric.efe409d08d", "\(id == "bookNet" ? L10n.text("mac.recordsView.metric.9ca02895b2") : title + L10n.text("mac.recordsView.metric.e3cb9c00b5"))"))
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
            VStack(alignment:.leading,spacing:MacUI.space(8)) {
                typePicker; currencyPicker; categoryPicker; clearFilters
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("recordFilters")
    }
    private var typePicker: some View {
        MacIconMenu(selection:$typeFilter,options:[
            .init(title:L10n.text("mac.recordsView.MacIconMenu.7a35c42462"),value:"All",symbol:"arrow.up.arrow.down"),
            .init(title:L10n.text("mac.recordsView.MacIconMenu.117d8f914d"),value:"Income",symbol:"arrow.down.left"),
            .init(title:L10n.text("mac.recordsView.MacIconMenu.e679096865"),value:"Expense",symbol:"arrow.up.right")
        ],identifier:"recordTypeFilter",accessibilityTitle:L10n.text("mac.recordsView.MacIconMenu.f0bbe3fb0f"),width: localizationState.effectiveLanguage == "en" ? 200 : 148)
    }
    private var categoryPicker: some View {
        let separator = "\u{1f}"
        var options: [MacIconMenuOption] = [.init(title:L10n.text("mac.recordsView.options.33f222a369"),value:"All",symbol:"square.grid.2x2")]
        // Scope drill-downs can intentionally select a name across both types.
        if categoryFilter != "All", typeFilter == "All" {
            options.append(.init(title:MacOverviewStyle.category(categoryFilter),value:"All" + separator + categoryFilter,symbol:"tag"))
        }
        let styles: [String:MacCategoryStyle] = MacSettingsStore.load("v2_category_styles",fallback:[:])
        let types = TransactionType(rawValue:typeFilter).map { [$0] } ?? [.income,.expense]
        for type in types {
            let names = filterCategoryNames[type.rawValue] ?? []
            if !names.isEmpty {
                options.append(.init(title:type == .income ? L10n.text("mac.recordsView.categoryPicker.ba01282192") : L10n.text("mac.recordsView.categoryPicker.b6a1a504a8"),value:nil))
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
        }),options:options,identifier:"recordCategoryFilter",accessibilityTitle:L10n.text("mac.recordsView.MacIconMenu.0d12cbd656"),width: localizationState.effectiveLanguage == "en" ? 200 : 164)
    }
    private var currencyPicker: some View {
        MacCurrencyMenu(selection:$currencyFilter,codes:filterCurrencyCodes,identifier:"recordCurrencyFilter",prefixOptions:[(L10n.text("mac.recordsView.MacCurrencyMenu.efeb7909d4"),"All")],width: localizationState.effectiveLanguage == "en" ? 200 : MacCurrencyMenuStyle.width)
    }
    private var clearFilters: some View {
        Button(L10n.text("mac.recordsView.clearFilters.cb5d682bac")) {
            searchText = ""; typeFilter = "All"; categoryFilter = "All"; currencyFilter = "All"
            dateFilterEnabled = false; rangeTitle = MacRecordRangeIdentity.all
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
            Text(L10n.format("mac.recordsView.selectionActions.a422c54f92", Int64(batchSelection.count))).appFont(.caption).foregroundStyle(.secondary)
            Button(L10n.text("mac.recordsView.selectionActions.2cd0f3be87")) { selectionMode = false; batchSelection.removeAll() }.accessibilityIdentifier("recordCancelSelection")
            Button(L10n.text("mac.recordsView.selectionActions.2f9daa8289"), role: .destructive) { deletionAcknowledged = false; confirmsBatchDelete = true }
                .disabled(deletableSelection.isEmpty).accessibilityIdentifier("recordDeleteSelection")
        } else {
            Button(L10n.text("mac.recordsView.selectionActions.461e085d5c")) { selectionMode = true; showsDetails = false }.disabled(visibleTransactions.isEmpty).accessibilityIdentifier("recordStartSelection")
        }
    }
    private var tablePagination: some View {
        VStack(spacing:0) {
            Divider()
            HStack {
                Text(L10n.format("mac.recordsView.tablePagination.24a21925e2", "\(min(displayLimit, visibleTransactions.count))", Int64(visibleTransactions.count)))
                    .appFont(.caption).foregroundStyle(.secondary).accessibilityIdentifier("recordDisplayedCount")
                Spacer()
                if displayLimit < visibleTransactions.count {
                    Button(L10n.text("mac.recordsView.tablePagination.331af79f34")) { displayLimit += MacPreferences.defaults.object(forKey: "v2_page_size") as? Int ?? 50 }
                        .accessibilityIdentifier("recordLoadMore")
                }
            }.appPadding(.horizontal, 12).appPadding(.vertical, 8)
        }
    }
    private var tableCount: some View {
        Text(L10n.format("mac.recordsView.tableCount.c53221b969", Int64(visibleTransactions.count))).appFont(.caption, weight: .medium, design: .default)
            .accessibilityIdentifier("transactionCount")
    }
    private var sortPicker: some View {
        MacSettingsMenu(selection: $recordSort, options: MacRecordSort.allCases.map { ($0.title, $0.legacyValue) }).frame(width: max(132, MacUI.fontTier.bodySize * 7 + 32)).accessibilityIdentifier("recordSort")
    }
    private var batchMenu: some View {
        Menu(L10n.format("mac.recordsView.Menu.992a186570", "\(batchSelection.isEmpty ? "" : "（\(batchSelection.count)）")")) {
            Button(L10n.text("mac.recordsView.Menu.c6cea5d6d9")) { batchSelection = Set(visibleTransactions.filter { !MacTransactionCRUD.isProtectedGeneratedPosting($0) }.map(\.id)) }
                .accessibilityIdentifier("selectVisibleRecords")
            Button(L10n.text("mac.recordsView.Menu.5288519d85")) { batchSelection.removeAll() }.disabled(batchSelection.isEmpty)
            Divider()
            Button(L10n.text("mac.recordsView.Menu.9e43c97fce"), role: .destructive) { deletionAcknowledged = false; confirmsBatchDelete = true }
                .disabled(deletableSelection.isEmpty).accessibilityIdentifier("deleteSelectedRecords")
        }.menuStyle(.borderlessButton).fixedSize().accessibilityIdentifier("recordBatchMenu")
    }
    private var detailsButton: some View {
        Button { showsDetails = true } label: { Image(systemName: "sidebar.right") }
            .buttonStyle(MacInteractiveButtonStyle()).disabled(selectedTransaction == nil).appHelp(L10n.text("mac.recordsView.detailsButton.f8a298955a"))
            .accessibilityLabel(L10n.text("mac.recordsView.detailsButton.5e77ec6326")).accessibilityIdentifier("recordOpenDetails")
    }
    private var exportButton: some View {
        Button { exportVisibleTransactions() } label: { Label(L10n.text("mac.recordsView.exportButton.76420433f2"), systemImage: "square.and.arrow.up") }
            .buttonStyle(MacInteractiveButtonStyle()).disabled(visibleTransactions.isEmpty).appHelp(L10n.text("mac.recordsView.exportButton.2754b95293"))
            .accessibilityIdentifier("recordExport")
    }
    private func selectAllRecords() {
        selectionMode = true; showsDetails = false
        displayLimit = max(displayLimit, visibleTransactions.count)
        batchSelection = Set(visibleTransactions.map(\.id))
    }
    private func selectionCheckbox(_ row: Transaction) -> some View {
        Toggle(L10n.text("mac.recordsView.selectionCheckbox.38b8a732f4"), isOn: Binding(get: { batchSelection.contains(row.id) }, set: { value in
            selectionMode = true
            if value { batchSelection.insert(row.id) } else { batchSelection.remove(row.id) }
        })).toggleStyle(.checkbox).labelsHidden().accessibilityIdentifier("recordSelect-" + row.id.uuidString)
    }
    @ViewBuilder private func recordContextMenu(_ ids: Set<UUID>) -> some View {
        let rows = visibleTransactions.filter { ids.contains($0.id) }
        if rows.count == 1, let row = rows.first {
            Button(L10n.text("mac.recordsView.recordContextMenu.a748cc074f"), systemImage: "sidebar.right") { selectedTransactionID = row.id; showsDetails = true }
            Button(L10n.text("mac.recordsView.recordContextMenu.0518365699"), systemImage: "pencil") { editingTransaction = row }.disabled(activeBookCurrency == nil || MacTransactionCRUD.isProtectedGeneratedPosting(row))
        }
        if !rows.isEmpty {
            Button(rows.count == 1 ? L10n.text("mac.recordsView.recordContextMenu.baa83a825b") : L10n.format("mac.recordsView.recordContextMenu.b832f0218b", Int64(rows.count)), systemImage: "trash", role: .destructive) {
                batchSelection = ids; deletionAcknowledged = false; confirmsBatchDelete = true
            }.disabled(rows.allSatisfy(MacTransactionCRUD.isProtectedGeneratedPosting))
            Divider()
        }
        Button(showsSelectionBoxes ? L10n.text("mac.recordsView.recordContextMenu.ad74fe9ca3") : L10n.text("mac.recordsView.recordContextMenu.461e085d5c"), systemImage: "checklist") {
            if showsSelectionBoxes { selectionMode = false; batchSelection.removeAll() }
            else { selectionMode = true; batchSelection.formUnion(ids); showsDetails = false }
        }.accessibilityIdentifier("recordContextMultiSelect")
        Button(L10n.text("mac.recordsView.recordContextMenu.3a5040b68a"), systemImage: "checkmark.circle") { selectAllRecords() }.keyboardShortcut("a", modifiers: .command).disabled(visibleTransactions.isEmpty).accessibilityIdentifier("recordContextSelectAll")
        Button(L10n.text("mac.recordsView.recordContextMenu.74966e20df")) { batchSelection.removeAll() }.disabled(batchSelection.isEmpty)
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
            TableColumn(L10n.text("mac.recordsView.TableColumn.70d0c1b336")) { row in
                Text(MacDateDisplay.string(row.date))
                    .appFont(.body, weight: .regular, design: .default)
                    .monospacedDigit()
            }.width(min: 60, ideal: dateColumnWidth, max: 600)
            TableColumn(L10n.text("mac.recordsView.TableColumn.0d12cbd656")) { row in categoryCell(row) }.width(min: 35, ideal: category, max: 2000)
            TableColumn(L10n.text("mac.recordsView.TableColumn.daede98817")) { row in
                Text(showsNotesPreview ? (MacFinanceNotes.visible(row.note).isEmpty ? "—" : MacFinanceNotes.visible(row.note)) : "—").appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary).lineLimit(1)
            }.width(min: 35, ideal: notes, max: 10000)
            TableColumn(L10n.text("mac.recordsView.TableColumn.1e878068f9")) { row in Text(row.originalCurrency).appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary) }
                .width(min: 42, ideal: 50, max: 200)
            TableColumn(L10n.format("mac.recordsView.TableColumn.474f15922f", "\(activeBookCurrency ?? L10n.text("mac.recordsView.TableColumn.8865cec527"))")) { row in signedTableAmount(row) }
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
    private var cardTransactionList: some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:10) {
                if showsSelectionBoxes {Button(L10n.text("mac.recordsView.LazyVStack.c826ba489d")) {toggleAllRecords()}.accessibilityIdentifier("recordSelectAllCards")}
                ForEach(Array(visibleTransactions.prefix(displayLimit)),id:\.id) {row in
                    Button {
                        if showsSelectionBoxes {if batchSelection.contains(row.id){batchSelection.remove(row.id)}else{batchSelection.insert(row.id)}}
                        else {selectedTransactionID=row.id;showsDetails=true}
                    } label: {
                        HStack(alignment:.top,spacing:8) {
                            if showsSelectionBoxes {Image(systemName:batchSelection.contains(row.id) ? "checkmark.square.fill":"square")}
                            VStack(alignment:.leading,spacing:8) {
                                Text(MacDateDisplay.string(row.date)).appFont(.caption).foregroundStyle(.secondary)
                                categoryCell(row)
                                signedTableAmount(row)
                                if row.originalCurrency != row.baseCurrencyCode {Text(L10n.text("mac.recordsView.ForEach.494804e991")+row.originalCurrency).appFont(.caption).foregroundStyle(.secondary)}
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }.padding(12).contentShape(Rectangle()).background(.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:8))
                    }.buttonStyle(MacInteractiveButtonStyle()).contextMenu {recordContextMenu([row.id])}
                }
            }.padding(10)
        }.accessibilityIdentifier("recordsTable").background(MacRecordsKeyboardActions(selectAll:selectAllRecords).frame(width:0,height:0))
    }
    private func compactTransactionTable(availableWidth: CGFloat) -> some View {
        let columns = showsSelectionBoxes ? 4 : 3
        let category = max(40, availableWidth - dateColumnWidth - amountColumnWidth - (showsSelectionBoxes ? MacUI.space(26) : 0) - CGFloat(columns) * 24 - 20)
        return Table(Array(visibleTransactions.prefix(displayLimit)), selection: $batchSelection) {
            if showsSelectionBoxes {
                TableColumn("") { row in selectionCheckbox(row) }.width(MacUI.space(26))
            }
            TableColumn(L10n.text("mac.recordsView.TableColumn.70d0c1b336")) { row in Text(MacDateDisplay.string(row.date)).appFont(.body, weight: .regular, design: .default).monospacedDigit() }.width(min: 60, ideal: dateColumnWidth, max: 600)
            TableColumn(L10n.text("mac.recordsView.TableColumn.0d12cbd656")) { row in categoryCell(row) }.width(min: 35, ideal: category, max: 2000)
            TableColumn(L10n.format("mac.recordsView.TableColumn.474f15922f", "\(activeBookCurrency ?? L10n.text("mac.recordsView.TableColumn.8865cec527"))")) { row in
                VStack(alignment:.trailing,spacing:1) {
                    signedTableAmount(row)
                    if row.originalCurrency != row.baseCurrencyCode {
                        Text(L10n.text("mac.recordsView.TableColumn.494804e991") + row.originalCurrency).appFont(.caption).foregroundStyle(.secondary)
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
            .appPadding(.trailing, 10)
            .accessibilityIdentifier("recordAmount-" + row.id.uuidString)
            .accessibilityLabel((income ? L10n.text("mac.recordsView.signedTableAmount.7a7425968b") : L10n.text("mac.recordsView.signedTableAmount.38d69dcb62")) + MacOverviewStyle.money(row.baseAmount) + " " + row.baseCurrencyCode)
    }
    private func detailPanel(_ row: Transaction) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(18)) {
            HStack {
                Text(L10n.text("mac.recordsView.detailPanel.fa21fd53f4")).appFont(.section, weight: .semibold); Spacer()
                Button { showsDetails = false } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }
                    .buttonStyle(MacInteractiveButtonStyle()).accessibilityLabel(L10n.text("mac.recordsView.detailPanel.9071cfe7cd")).accessibilityIdentifier("recordCloseDetails")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: MacUI.space(18)) {
                    Label(row.typedType == .income ? L10n.text("mac.recordsView.ScrollView.117d8f914d") : L10n.text("mac.recordsView.ScrollView.e679096865"), systemImage: row.typedType == .income ? "arrow.down.left" : "arrow.up.right")
                        .appFont(.caption, weight: .regular).foregroundStyle(row.typedType == .income ? MacOverviewStyle.income : MacOverviewStyle.expense)
                    Text(MacOverviewStyle.money(row.originalAmount)).appFont(.amount, weight: .semibold, design: .default).monospacedDigit()
                    Text(row.originalCurrency).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    Divider()
                    detailField(L10n.text("mac.recordsView.detailField.0d12cbd656"), value: MacOverviewStyle.category(row.category), id: "recordSelectedCategory")
                    detailField(L10n.text("mac.recordsView.detailField.70d0c1b336"), value: MacDateDisplay.string(row.date), id: "recordDetailDate")
                    detailField(L10n.text("mac.recordsView.detailField.38bc61ab91"), value: "\(MacOverviewStyle.money(row.baseAmount)) \(row.baseCurrencyCode)", id: "recordBookAmount")
                    detailField(L10n.text("mac.recordsView.detailField.ff80360122"), value: row.exchangeRateToBase.formatted(.number.precision(.fractionLength(0...8))), id: "recordStoredFX")
                    detailField(L10n.text("mac.recordsView.detailField.daede98817"), value: MacFinanceNotes.visible(row.note).isEmpty ? L10n.text("mac.recordsView.detailField.8445d1bad0") : MacFinanceNotes.visible(row.note), id: "recordDetailNote")
                    if MacTransactionCRUD.isProtectedGeneratedPosting(row) {
                        Label(L10n.text("mac.recordsView.ScrollView.bca1f9d7ea"), systemImage: "lock").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            Divider()
            HStack {
                Button(L10n.text("mac.recordsView.detailPanel.0518365699")) { editingTransaction = row }.accessibilityIdentifier("editEntry")
                    .disabled(activeBookCurrency == nil || MacTransactionCRUD.isProtectedGeneratedPosting(row))
                Spacer()
                Button(L10n.text("mac.recordsView.detailPanel.2f9daa8289"), role: .destructive) { deletionAcknowledged = false; showsDeleteConfirmation = true }.accessibilityIdentifier("deleteEntry")
                    .disabled(MacTransactionCRUD.isProtectedGeneratedPosting(row))
            }
        }.appPadding(18).frame(maxHeight: .infinity)
            .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.045)))
        .sheet(isPresented: $showsDeleteConfirmation) {
            VStack(alignment: .leading, spacing: MacUI.space(18)) {
                Text(L10n.text("mac.recordsView.detailPanel.4608daaa48"))
                    .appFont(.dialogTitle, weight: .semibold)
                    .accessibilityIdentifier("deleteConfirmationTitle")
                Text(L10n.text("mac.recordsView.detailPanel.1427ef9d1b"))
                    .foregroundStyle(.secondary)
                if extraDeletionConfirmation { Toggle(L10n.text("mac.recordsView.detailPanel.fa57a1018f"), isOn: $deletionAcknowledged) }
                HStack {
                    Spacer()
                    Button(L10n.text("mac.recordsView.detailPanel.2cd0f3be87")) { showsDeleteConfirmation = false }
                        .accessibilityIdentifier("cancelDeleteEntry")
                    Button(L10n.text("mac.recordsView.detailPanel.2f9daa8289"), role: .destructive) {
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
            Text(L10n.text("mac.recordsView.timelinePanel.b5f15473fd")).appFont(.section, weight: .semibold)
            TextField(L10n.text("mac.recordsView.timelinePanel.da1e2a7a36"), text: $searchText).textFieldStyle(.roundedBorder)
                .appHelp(L10n.text("mac.recordsView.timelinePanel.445326eb66"))
                .accessibilityLabel(L10n.text("mac.recordsView.timelinePanel.2346e64db7"))
                .accessibilityIdentifier("recordSearch")
            ScrollView {
                VStack(alignment: .leading, spacing: MacUI.space(5)) {
                    rangeButton(L10n.text("mac.recordsView.rangeButton.e425792084"), icon: "tray.full", id: "recordAll", selected: !dateFilterEnabled) {
                        dateFilterEnabled = false; rangeTitle = MacRecordRangeIdentity.all
                    }
                    rangeButton(L10n.text("mac.recordsView.rangeButton.178393de56"), icon: "clock", id: "recordRecent", selected: rangeTitle == MacRecordRangeIdentity.recent) {
                        dateFrom = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: Date()))!
                        dateThrough = Date(); dateFilterEnabled = true; rangeTitle = MacRecordRangeIdentity.recent
                    }
                    Divider().appPadding(.vertical, 10)
                    Text(L10n.text("mac.recordsView.ScrollView.0136fb1836")).appFont(.caption, weight: .semibold, design: .default).foregroundStyle(.secondary)
                    ForEach(years, id: \.self) { year in
                        VStack(alignment: .leading, spacing: MacUI.space(5)) {
                            HStack(spacing: MacUI.space(3)) {
                                disclosure(expandedYears.contains(year), id: "recordExpandYear-\(year)") {
                                    if expandedYears.contains(year) { expandedYears.remove(year) } else { expandedYears.insert(year) }
                                }
                                Button { selectPeriod(year: year) } label: {
                                    treeLabel(L10n.format("mac.recordsView.updateRangeTitle.344415d04a", "\(year)"), count: timelineIndex.count(year: year), selected: rangeTitle == MacRecordRangeIdentity.year(year))
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
            Toggle(L10n.text("mac.recordsView.timelinePanel.8a43007a89"), isOn: $dateFilterEnabled).toggleStyle(.checkbox).appFont(.caption, weight: .regular)
                .accessibilityIdentifier("recordDateEnabled")
            if dateFilterEnabled {
                MacDateTimeField(title: L10n.text("mac.recordsView.MacDateTimeField.2719a8ea30"), date: $dateFrom).accessibilityIdentifier("recordFrom")
                MacDateTimeField(title: L10n.text("mac.recordsView.MacDateTimeField.65edbf9f1c"), date: $dateThrough).accessibilityIdentifier("recordThrough")
            }
        }.appPadding(18).frame(maxHeight: .infinity).background(MacOverviewStyle.filters)
        .onChange(of: dateFrom) { _, _ in updateRangeTitle() }
        .onChange(of: dateThrough) { _, _ in updateRangeTitle() }
        .onChange(of: dateFilterEnabled) { _, enabled in if !enabled { rangeTitle = MacRecordRangeIdentity.all } }
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
                    treeLabel(L10n.format("mac.recordsView.treeLabel.a71cefcdd1", "\(month)"), count: timelineIndex.count(year: year, month: month), selected: rangeTitle == MacRecordRangeIdentity.month(year, month))
                }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("recordMonth-\(key)")
            }
            if expandedMonths.contains(key) {
                ForEach(days, id: \.self) { day in
                    Button { selectDay(day) } label: {
                    treeLabel(L10n.format("mac.recordsView.treeLabel.d847e2eaf9", "\(Calendar.current.component(.day, from: day))"),
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
        }.buttonStyle(MacInteractiveButtonStyle()).accessibilityLabel(expanded ? L10n.text("mac.recordsView.disclosure.47c91fadcc") : L10n.text("mac.recordsView.disclosure.a49f5287fc")).accessibilityIdentifier(id)
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
        rangeTitle = month.map { MacRecordRangeIdentity.month(year, $0) } ?? MacRecordRangeIdentity.year(year)
    }
    private func selectDay(_ date: Date) {
        dateFrom = date; dateThrough = date; dateFilterEnabled = true
        rangeTitle = "day"
    }
    private func updateRangeTitle() {
        rangeTitle = MacRecordRangeIdentity.resolve(from: dateFrom, through: dateThrough, enabled: dateFilterEnabled)
    }

    private func exportVisibleTransactions() {
        guard let url = CSVExporter.exportTransactionsCSV(transactions: visibleTransactions) else {
            feedback.show(.failure,title:L10n.text("mac.recordsView.exportVisibleTransactions.6e4445df69"),message:L10n.text("mac.recordsView.exportVisibleTransactions.aa35cbf61c"))
            return
        }
        defer { try? FileManager.default.removeItem(at:url) }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]; panel.nameFieldStringValue = url.lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try Data(contentsOf: url).write(to: destination, options: .atomic); saveError = nil
            feedback.show(.success,title:L10n.text("mac.recordsView.exportVisibleTransactions.5603e01058"),message:L10n.format("mac.recordsView.exportVisibleTransactions.085df6c8b2", Int64(visibleTransactions.count), "\(destination.lastPathComponent)"))
        } catch {
            saveError = MacLocalization.error(error)
            feedback.show(.failure,title:L10n.text("mac.recordsView.exportVisibleTransactions.6e4445df69"),message:MacLocalization.error(error))
        }
    }

}

/// Keep headers and the row viewport reachable when zoom consumes vertical space.
private struct MacRecordsPageScrolling: ViewModifier {
    var enabled: Bool
    func body(content: Content) -> some View {
        if enabled { ScrollView(.vertical) { content.fixedSize(horizontal:false,vertical:true) } }
        else { content }
    }
}
