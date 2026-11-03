import SwiftUI
import SwiftData
import Charts
import AppKit

struct OverviewCard<Content: View>: View {
    var help: String
    var height: CGFloat? = nil
    @ViewBuilder var content: Content
    var body: some View {
        content.appPadding(18).frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(minHeight: height.map { MacUI.space($0) }, alignment: .topLeading)
            .macHoverCardSurface().appHelp(help)
    }
}

// The financial goal determines the paired row height. The schedule scrolls
// within the same height instead of making the entire overview row taller.
private struct MacOverviewGoalScheduleRow: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? MacUI.space(900)
        let column = max(1, (width - spacing) / 2)
        let height = subviews.first?.sizeThatFits(.init(width: column, height: nil)).height ?? 0
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let column = max(1, (bounds.width - spacing) / 2)
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (column + spacing), y: bounds.minY), anchor: .topLeading, proposal: .init(width: column, height: bounds.height))
        }
    }
}

struct MacOverviewView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @AppStorage(MacCustomTypography.bodyKey, store: MacPreferences.defaults) private var layoutBodyPoints = 16
    @AppStorage(MacCustomTypography.captionKey, store: MacPreferences.defaults) private var layoutCaptionPoints = 12
    @AppStorage("v2_font_tier", store: MacPreferences.defaults) private var layoutTier = "standard"
    @AppStorage(MacInterfaceFonts.preferenceKey, store: MacPreferences.defaults) private var interfaceFont = ""
    let bookCurrency: String?
    // This page only sends navigation actions. Observing section changes also
    // rebuilt the outgoing page before SwiftUI removed it from the hierarchy.
    let workspace: MacWorkspaceSession
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var deposits: [DepositRecord]
    @Query private var loans: [LoanRule]
    @Query private var recurring: [RecurringTransaction]
    @Query(sort: \Goal.createdAt) private var goals: [Goal]
    @Query(sort: \FinancialProfile.createdAt) private var profiles: [FinancialProfile]
    @State private var scope = MacOverviewScope()
    @State private var trendMonths = MacPreferences.defaults.object(forKey: "v2_chart_months") as? Int ?? 6
    @State private var showsGoals = false
    @State private var showsAssets = false
    @State private var showsProfileEditor = false
    @State private var detailTransaction: Transaction?
    @State private var detailMetric: MacOverviewMetric?
    @State private var showsMonthPicker = false
    @FocusState private var monthPickerAnchorFocused: Bool

    private var currency: String { bookCurrency ?? "—" }
    private var periodRows: [Transaction] {
        guard bookCurrency != nil else { return [] }
        return scope.matching(transactions, currency: currency)
    }
    private var totals: (income: Double, expense: Double, net: Double) {
        MacTransactionCRUD.totals(transactions: periodRows, currency: currency)
    }
    private var previous: (income: Double, expense: Double, net: Double)? {
        guard let range = scope.previousInterval(), bookCurrency != nil else { return nil }
        return MacTransactionCRUD.totals(transactions: scope.matching(transactions, currency: currency, interval: range), currency: currency)
    }
    private var categoryRows: [MacOverviewData.Bucket] {
        var allCategories = scope; allCategories.category = nil
        return MacOverviewData.categories(allCategories.matching(transactions, currency: currency), type: scope.type ?? .expense)
    }
    private var categoryScopeRows: [Transaction] {
        var filter = scope; filter.type = nil
        return filter.matching(transactions, currency: currency)
    }
    private var expenses: [MacOverviewData.Bucket] { MacOverviewData.categories(categoryScopeRows, type: .expense) }
    private var incomes: [MacOverviewData.Bucket] { MacOverviewData.categories(categoryScopeRows, type: .income) }
    private var trend: [MacOverviewData.Month] { MacOverviewData.months(transactions, scope: scope, currency: currency, count: trendMonths) }
    private var profile: FinancialProfile? { profiles.first { $0.deletedAt == nil && $0.liquidityData != nil } ?? profiles.first { $0.deletedAt == nil } }
    private var snapshot: FinancialProfileSnapshot {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
        return MacFinancialSettings.snapshot(profile: profile, transactions: transactions.filter { $0.date < tomorrow },
            loans: loans, deposits: deposits, currency: currency, asOf: Date())
    }
    private var activeGoals: [Goal] { goals.filter { $0.deletedAt == nil } }
    private var currentGoal: Goal? { activeGoals.first { !$0.isPaused && !$0.isAccomplished } ?? activeGoals.first }
    private var goalPresentations: [String: MacGoalPresentation] { MacSettingsStore.load("v2_goal_presentation", fallback: [:]) }
    private func goalPresentation(_ goal: Goal) -> MacGoalPresentation { goalPresentations[goal.id.uuidString] ?? .init() }

    var body: some View {
        let _ = layoutBodyPoints; let _ = layoutCaptionPoints
        GeometryReader { geometry in
            let categoryScopeRows = self.categoryScopeRows
            let incomes = MacOverviewData.categories(categoryScopeRows, type: .income)
            let expenses = MacOverviewData.categories(categoryScopeRows, type: .expense)
            let incomeCategoryTotal = incomes.reduce(0) { $0 + $1.amount }
            let expenseCategoryTotal = expenses.reduce(0) { $0 + $1.amount }
            let filterWidth = MacUI.filterColumnWidth(available: geometry.size.width, wide: geometry.size.width >= MacUI.space(950))
            HStack(spacing: MacUI.space(0)) {
                filterPanel.frame(width: filterWidth); Divider()
                let contentWidth = max(1, geometry.size.width - filterWidth - 1)
                let innerContentWidth = max(1, contentWidth - MacUI.space(40))
                let keepsCardsInPairs = innerContentWidth >= MacUI.space(720)
                let categoryChartSize: CGFloat = keepsCardsInPairs && innerContentWidth < MacUI.space(900) ? MacUI.space(130) : MacUI.space(158)
                ScrollView {
                    VStack(alignment: .leading, spacing: MacUI.space(15)) {
                        header
                        MacInAppReminders(workspace: workspace)
                        if bookCurrency == nil {
                            Label(L10n.text("mac.overviewView.ScrollView.bde784bff3"), systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange).accessibilityIdentifier("overviewMixedCurrency")
                        }
                        if !scope.isValid { Text(L10n.text("mac.overviewView.ScrollView.90de26a62a")).foregroundStyle(.red) }
                        metrics(contentWidth: innerContentWidth)
                        trendCard
                        if keepsCardsInPairs {
                            MacOverviewGoalScheduleRow(spacing: MacUI.space(15)) {
                                goalCard.frame(maxWidth: .infinity)
                                scheduleCard.frame(maxWidth: .infinity)
                            }
                            HStack(alignment: .top, spacing: MacUI.space(15)) {
                                categoryCard(.expense, rows: expenses, total: expenseCategoryTotal, chartSize: categoryChartSize).frame(maxWidth: .infinity)
                                categoryCard(.income, rows: incomes, total: incomeCategoryTotal, chartSize: categoryChartSize).frame(maxWidth: .infinity)
                            }
                        } else {
                            goalCard; scheduleCard
                            categoryCard(.expense, rows: expenses, total: expenseCategoryTotal, chartSize: categoryChartSize)
                            categoryCard(.income, rows: incomes, total: incomeCategoryTotal, chartSize: categoryChartSize)
                        }
                        recentCard
                    }
                    .frame(width: innerContentWidth, alignment: .leading)
                    .appPadding(.horizontal, 20)
                    .appPadding(.bottom, 74)
                }
                .frame(width: max(1, contentWidth))
                .accessibilityIdentifier("overviewScroll")
                .overlay(alignment: .bottomTrailing) {
                        Button { workspace.showsQuickRecord = true } label: {
                        Image(systemName: "plus").appIconFont(26, weight: .medium, design: .default)
                            .foregroundStyle(.white).frame(width: MacUI.space(58), height: MacUI.space(58))
                            .background(MacOverviewStyle.accent, in: Circle())
                            .shadow(color: MacOverviewStyle.accent.opacity(0.2), radius: 8, y: 4)
                        }.buttonStyle(MacInteractiveButtonStyle()).appHelp(L10n.text("mac.overviewView.GeometryReader.e81051e879"))
                            .accessibilityLabel(L10n.text("mac.overviewView.GeometryReader.e81051e879")).accessibilityIdentifier("overviewQuickRecord")
                            .disabled(bookCurrency == nil)
                        .appPadding(.trailing, 20).appPadding(.bottom, 16)
                }
            }
        }
        .onChange(of: scope.through) { _, value in if scope.period == .custom { scope.reference = value } }
        .sheet(isPresented: $showsGoals) { MacOverviewGoalManager(currency: bookCurrency) }
        .sheet(isPresented: $showsAssets) {
            assetDetails.sheet(isPresented: $showsProfileEditor) {
                MacFinancialProfileEditor(currency: currency, profile: profile)
            }
        }
        .sheet(item: $detailTransaction) { row in
            VStack(alignment: .leading, spacing: MacUI.space(16)) {
                Text(L10n.text("mac.overviewView.body.fa21fd53f4")).appFont(.dialogTitle, weight: .semibold)
                LabeledContent(L10n.text("mac.overviewView.LabeledContent.0d12cbd656"), value: MacOverviewStyle.category(row.category))
                LabeledContent(L10n.text("mac.overviewView.LabeledContent.70d0c1b336"), value: MacDateDisplay.string(row.date))
                LabeledContent(L10n.text("mac.overviewView.LabeledContent.fee8c0943c"), value: "\(MacOverviewStyle.money(row.originalAmount)) \(row.originalCurrency)")
                LabeledContent(L10n.text("mac.overviewView.LabeledContent.38bc61ab91"), value: "\(MacOverviewStyle.money(row.baseAmount)) \(row.baseCurrencyCode)")
                if let note = row.note { Text(note).foregroundStyle(.secondary) }
                HStack {
                    Button(L10n.text("mac.overviewView.body.d78ecdf7e8")) { workspace.showRecords(scope); detailTransaction = nil }
                    Spacer(); Button(L10n.text("mac.overviewView.body.3fd47edce4")) { detailTransaction = nil }.keyboardShortcut(.cancelAction)
                }
            }.appPadding(24).appDialog(width: 480)
        }
        .sheet(item: $detailMetric) { metric in
            MacOverviewMetricDetails(metric: metric, scope: scope, currency: currency, transactions: transactions,
                                     trendMonths: trendMonths) {
                var records = scope
                if metric == .income { records.type = .income }
                if metric == .expense { records.type = .expense }
                detailMetric = nil
                workspace.showRecords(records)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(scope.title + ((MacPreferences.isTesting && ProcessInfo.processInfo.environment["FINTRACK_V2_DEMO"] == "1") ? L10n.text("mac.overviewView.header.83debda181") : "") + (scope.category.map { " · " + MacOverviewStyle.category($0) } ?? ""))
                .appFont(.body, weight: .medium, design: .default).foregroundStyle(.secondary)
                .accessibilityIdentifier("overviewTitle")
            Spacer()
            Text(L10n.format("mac.overviewView.header.08cd60a4dc", "\(currency)")).appFont(.caption, weight: .medium, design: .default).foregroundStyle(.secondary)
                .appHelp(L10n.text("mac.overviewView.header.ff7625b55a"))
        }.appPadding(.bottom, 3)
    }
    private var previousPeriodButton: some View {Button {movePeriod(-1)} label:{Image(systemName:"chevron.left")}.accessibilityLabel(L10n.text("mac.overviewView.previousPeriodButton.aee70020c1")).accessibilityIdentifier("overviewPreviousPeriod")}
    private var nextPeriodButton: some View {Button {movePeriod(1)} label:{Image(systemName:"chevron.right")}.accessibilityLabel(L10n.text("mac.overviewView.nextPeriodButton.0d6dacd9d1")).accessibilityIdentifier("overviewNextPeriod")}
    private var monthPickerButton: some View {
        Button {showsMonthPicker=true} label:{Text(scope.title).appFont(.caption).lineLimit(1)}
            .focused($monthPickerAnchorFocused).accessibilityIdentifier("overviewMonthPicker")
            .popover(isPresented:$showsMonthPicker) {MacCalendarPickerPopover(title:L10n.text("mac.overviewView.MacCalendarPickerPopover.680c78ec60"),selection:$scope.reference,pickerIdentifier:"overviewMonthDatePicker",doneIdentifier:"overviewMonthDateDone",onDone:{showsMonthPicker=false})}
            .onChange(of:showsMonthPicker) {_,shown in if !shown {monthPickerAnchorFocused=true}}
    }
    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: MacUI.space(20)) {
            Text(L10n.text("mac.overviewView.filterPanel.b5f15473fd")).appFont(.section, weight: .semibold)
            ScrollView { filterControls }
            Spacer(minLength: 8)
            Text(L10n.text("mac.overviewView.filterPanel.1aefeced8e"))
                .appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).lineSpacing(4)
        }.appPadding(18).frame(maxHeight: .infinity).background(MacOverviewStyle.filters)
    }
    private var filterControls: some View {
        let categoryRows = self.categoryRows
        return VStack(alignment: .leading, spacing: MacUI.space(18)) {
            Text(L10n.text("mac.overviewView.filterControls.07eb730af8")).appFont(.caption, weight: .semibold, design: .default).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MacUI.space(7)) {
                ForEach(MacOverviewScope.Period.allCases) { period in
                    Button { scope.period = period } label: {
                        Text(L10n.builtIn(period.rawValue)).appFont(.caption, weight: .regular, design: .default).frame(maxWidth: .infinity).appPadding(.vertical, 8)
                            .background(scope.period == period ? MacOverviewStyle.accent.opacity(0.16) : MacOverviewStyle.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(scope.period == period ? MacOverviewStyle.accent : .primary)
                    }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("overviewPeriod-\(period.id)")
                }
            }
            if scope.period == .month || scope.period == .year {
                ViewThatFits(in:.horizontal) {
                    HStack(spacing:6) {previousPeriodButton;monthPickerButton.fixedSize();nextPeriodButton}
                    VStack(spacing:8) {monthPickerButton.fixedSize();HStack {previousPeriodButton;Spacer();nextPeriodButton}}
                }.buttonStyle(MacInteractiveButtonStyle()).appPadding(10).background(MacOverviewStyle.card.opacity(0.65),in:RoundedRectangle(cornerRadius:9))
            } else if scope.period == .custom {
                MacDateTimeField(title: L10n.text("mac.overviewView.MacDateTimeField.d2bb025a2e"), date: $scope.from).accessibilityIdentifier("overviewFrom")
                MacDateTimeField(title: L10n.text("mac.overviewView.MacDateTimeField.c7b24e7997"), date: $scope.through).accessibilityIdentifier("overviewThrough")
            }
            Divider()
            Text(L10n.text("mac.overviewView.filterControls.2c6559f35d")).appFont(.caption, weight: .semibold, design: .default).foregroundStyle(.secondary)
            MacSettingsMenu(selection: $scope.type, options: [(L10n.text("mac.overviewView.MacSettingsMenu.7a35c42462"), TransactionType?.none), (L10n.text("mac.overviewView.MacSettingsMenu.117d8f914d"), Optional(TransactionType.income)), (L10n.text("mac.overviewView.MacSettingsMenu.e679096865"), Optional(TransactionType.expense))]).accessibilityIdentifier("overviewTypeFilter")
            Text(L10n.text("mac.overviewView.filterControls.101a654f60")).appFont(.caption, weight: .semibold, design: .default).foregroundStyle(.secondary)
            Button { scope.category = nil } label: {
                filterRow(L10n.text("mac.overviewView.filterRow.33f222a369"), icon: "square.grid.2x2", selected: scope.category == nil, count: nil)
            }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("overviewAllCategories")
            VStack(spacing: MacUI.space(3)) { ForEach(categoryRows) { row in
                Button { scope.category = row.id } label: {
                    filterRow(MacOverviewStyle.category(row.id), icon: MacCategoryCatalog.style(name: row.id, type: (scope.type ?? .expense).rawValue).symbol, selected: scope.category == row.id, count: row.count)
                }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("overviewCategory-\(row.id)")
            } }
            if categoryRows.isEmpty { Text(L10n.text("mac.overviewView.filterControls.1e0f6553e0")).appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
            if scope.category != nil && !categoryRows.contains(where: { $0.id == scope.category }) {
                Button(L10n.text("mac.overviewView.filterControls.8a1bb302e4")) { scope.category = nil }.appFont(.caption, weight: .regular)
            }
        }
    }
    private func filterRow(_ title: String, icon: String, selected: Bool, count: Int?) -> some View {
        HStack(spacing: MacUI.space(9)) {
            MacSettingsSymbol(symbol: icon, size: 14).frame(width: MacUI.space(17), height: MacUI.space(17)).accessibilityHidden(true)
            Text(title).lineLimit(1); Spacer(minLength: 3)
            if let count { Text("\(count)").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
        }.appFont(.caption, weight: .regular, design: .default).appPadding(9)
            .background(selected ? MacOverviewStyle.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(selected ? MacOverviewStyle.accent : .primary)
    }
    private func movePeriod(_ value: Int) {
        scope.reference = Calendar.current.date(byAdding: scope.period == .year ? .year : .month, value: value, to: scope.reference)!
    }

    private func metrics(contentWidth: CGFloat) -> some View {
        // One read-only result per render, with no persistent cache or invalidation policy.
        let totals = self.totals, previous = self.previous, snapshot = self.snapshot
        let tier = MacUI.fontTier
        let spacing = MacUI.space(13)
        // Geometry is independent of the amount text's ideal width. Unbounded
        // text widths must never feed back into the grid's proposed width.
        let minimumCardWidth = max(240, 220 + (tier.bodySize - 16) * 7)
        let columnCount = contentWidth >= minimumCardWidth * 4 + spacing * 3 ? 4
            : contentWidth >= minimumCardWidth * 2 + spacing ? 2 : 1
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: spacing), count: columnCount)
        return LazyVGrid(columns: columns, spacing: spacing) {
            metric(L10n.text("mac.overviewView.metric.e679096865"), value: totals.expense, prior: previous?.expense, icon: "arrow.down.right", color: MacOverviewStyle.expense, id: "overviewExpense", detail: .expense) {
                var records = scope; records.type = .expense; workspace.showRecords(records)
            }
            metric(L10n.text("mac.overviewView.metric.117d8f914d"), value: totals.income, prior: previous?.income, icon: "arrow.up.right", color: MacOverviewStyle.income, id: "overviewIncome", detail: .income) {
                var records = scope; records.type = .income; workspace.showRecords(records)
            }
            metric(L10n.text("mac.overviewView.metric.d26ca9aea9"), value: totals.net, prior: previous?.net, icon: "arrow.right", color: MacOverviewStyle.accent, id: "overviewNet", detail: .net) { workspace.showRecords(scope) }
            metric(L10n.text("mac.overviewView.metric.2240ac84aa"), value: snapshot.availableAssets + snapshot.frozenDepositPrincipal, prior: nil, icon: "square.stack.3d.up", color: .blue, id: "overviewAssets", current: true) { showsAssets = true }
        }
    }
    private func metric(_ title: String, value: Double, prior: Double?, icon: String, color: Color, id: String,
                        current: Bool = false, detail: MacOverviewMetric? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            OverviewCard(help: current ? L10n.text("mac.overviewView.OverviewCard.1df256cb34") : L10n.format("mac.overviewView.OverviewCard.516a291f7d", "\(title)"), height: max(114, MacUI.fontSize(.amount, tier: MacUI.fontTier) + MacUI.fontTier.bodySize + MacUI.fontTier.captionSize + 56)) {
                VStack(alignment: .leading, spacing: MacUI.space(8)) {
                    HStack(spacing: MacUI.space(9)) {
                        Image(systemName: icon).appFont(.body, weight: .medium, design: .default).foregroundStyle(color)
                            .frame(width: MacUI.space(29), height: MacUI.space(29)).background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                        Text(title).appFont(.body, weight: .semibold, design: .default); Spacer()
                        if detail == nil { Image(systemName: "chevron.right").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.tertiary) }
                    }.padding(.trailing, detail == nil ? 0 : MacUI.space(30))
                    HStack(alignment: .firstTextBaseline, spacing: MacUI.space(5)) {
                        Spacer(minLength: 0)
                        Text(bookCurrency == nil ? "—" : MacOverviewStyle.money(value)).appFont(.amount, weight: .semibold, design: .default).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                        Text(MacSettingsVisual.symbol(currency)).appFont(.body, weight: .medium, design: .default).foregroundStyle(.secondary).fixedSize(horizontal: true, vertical: false)
                    }.accessibilityElement(children: .combine).accessibilityIdentifier(id)
                    if current {
                        Text(L10n.text("mac.overviewView.OverviewCard.1976cf517b")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                    } else if let prior, let change = MacOverviewData.change(current: value, previous: prior) {
                        HStack(spacing: MacUI.space(4)) {
                            Text(scope.period == .year ? L10n.text("mac.overviewView.OverviewCard.b74882e370") : (scope.period == .custom ? L10n.text("mac.overviewView.OverviewCard.64ca963831") : L10n.text("mac.overviewView.OverviewCard.8c266542f8"))).foregroundStyle(.secondary)
                            Text((change >= 0 ? "+" : "") + change.formatted(.percent.precision(.fractionLength(1)))).foregroundStyle(color)
                        }.appFont(.caption, weight: .regular, design: .default).monospacedDigit()
                    } else { Text(L10n.text("mac.overviewView.OverviewCard.580011fdb4")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }
                }
            }
        }
        .buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier(id + "Card").disabled(bookCurrency == nil)
        .overlay(alignment: .topTrailing) {
            if let detail {
                Button { detailMetric = detail } label: {
                    Image(systemName: "chart.bar.xaxis").appFont(.caption, weight: .medium, design: .default)
                        .accessibilityLabel(L10n.text("mac.overviewView.metric.55630dd739"))
                        .foregroundStyle(MacOverviewStyle.accent).padding(.horizontal, 8).padding(.vertical, 5)
                        .background(MacOverviewStyle.accent.opacity(0.07), in: Capsule())
                }
                .buttonStyle(MacInteractiveButtonStyle())
                .appHelp(L10n.format("mac.overviewView.metric.a5956bb5fe", "\(title)"))
                .accessibilityIdentifier(id + "Statistics")
                .padding(.top, MacUI.space(23)).padding(.trailing, MacUI.space(17))
                .disabled(bookCurrency == nil)
            }
        }
    }

    private var trendCard: some View {
        MacOverviewTrendCard(scope: scope, currency: currency, trendMonths: $trendMonths,
                             trend: trend, showRecords: { workspace.showRecords($0) }, createRecord: {workspace.showsQuickRecord=true})
    }
    private var goalCard: some View {
        let snapshot = self.snapshot
        return Button { showsGoals = true } label: {
            OverviewCard(help: L10n.text("mac.overviewView.OverviewCard.9b1467383b"), height: 250) {
                VStack(alignment: .leading, spacing: MacUI.space(13)) {
                    HStack { Text(L10n.text("mac.overviewView.OverviewCard.9d3fe41a1e")).appFont(.body, weight: .semibold, design: .default); Spacer(); Image(systemName: "arrow.up.right").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                    if let goal = currentGoal {
                        let presentation = goalPresentation(goal)
                        HStack(spacing: MacUI.space(9)) {
                            MacSettingsIcon(symbol: presentation.icon, color: MacAccent.color(presentation.color), size: 30)
                            Text(goal.title).appFont(.body, weight: .regular, design: .default).lineLimit(1)
                        }
                        Text("\(MacOverviewStyle.money(goal.targetAmount)) \(currency)").appFont(.amount, weight: .semibold, design: .default).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                        let progress = goal.clampedProgressValue(currentNetWorth: snapshot.netWorth, baselineNetWorth: Goal.baselineNetWorth(from: profile))
                        HStack { ProgressView(value: bookCurrency == nil ? 0 : progress).tint(MacOverviewStyle.accent); Text(bookCurrency == nil ? "—" : "\(goal.displayPercent(currentNetWorth: snapshot.netWorth, baselineNetWorth: Goal.baselineNetWorth(from: profile)))%").appFont(.caption, weight: .regular).monospacedDigit() }
                        HStack {
                            VStack(alignment: .leading, spacing: MacUI.space(6)) { Text(L10n.text("mac.overviewView.OverviewCard.8d1288c011")).foregroundStyle(.secondary); Text(bookCurrency == nil ? L10n.text("mac.overviewView.OverviewCard.7710d6e903") : "\(MacOverviewStyle.money(snapshot.netWorth)) \(currency)").monospacedDigit() }
                            Spacer()
                            VStack(alignment: .leading, spacing: MacUI.space(6)) { Text(L10n.text("mac.overviewView.OverviewCard.bf2cb28701")).foregroundStyle(.secondary); Text(MacGoalTargetDate.label(goal)) }
                        }.appFont(.caption, weight: .regular, design: .default)
                        Text(goal.isPaused ? L10n.text("mac.overviewView.OverviewCard.eb0c326b60") : (goal.includesCurrentAssets ? L10n.text("mac.overviewView.OverviewCard.5290042e0f") : L10n.text("mac.overviewView.OverviewCard.00dda524a5"))).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "target").appIconFont(30, weight: .light, design: .default).foregroundStyle(MacOverviewStyle.accent).appPadding(.top, 10)
                        Text(L10n.text("mac.overviewView.OverviewCard.e5099eb489")).appFont(.body, weight: .medium, design: .default)
                        Text(L10n.text("mac.overviewView.OverviewCard.f30bd204d8")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                        Text(L10n.text("mac.overviewView.OverviewCard.67fc9f0f67")).appFont(.caption, weight: .medium, design: .default).foregroundStyle(MacOverviewStyle.accent)
                    }
                }.frame(minHeight: MacUI.space(185), alignment: .top)
            }
        }.buttonStyle(MacInteractiveButtonStyle())
            .accessibilityRepresentation {
                Button(L10n.text("mac.overviewView.goalCard.9d3fe41a1e")) { showsGoals = true }.accessibilityIdentifier("overviewGoals")
            }
    }

    private func categoryCard(_ type: TransactionType, rows: [MacOverviewData.Bucket], total: Double, chartSize: CGFloat) -> some View {
        MacOverviewCategoryCard(type: type, rows: rows, total: total, currency: currency, chartSize: chartSize) { category in
            var records = scope; records.category = category; records.type = type; workspace.showRecords(records)
        }
    }

    private func categoryDot(_ row: MacOverviewData.Bucket, kind: String) -> some View {
        Circle().fill(MacAccent.color(MacCategoryCatalog.style(name: row.id, type: kind).color))
            .frame(width: MacUI.space(8), height: MacUI.space(8))
    }

    private func categoryPercent(_ row: MacOverviewData.Bucket, total: Double, width: CGFloat) -> some View {
        Text((total > 0 ? row.amount / total : 0).formatted(.percent.precision(.fractionLength(0))))
            .foregroundStyle(.secondary).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .frame(width: width, alignment: .trailing)
    }

    private struct ScheduleItem: Identifiable {
        var id: String
        var date: Date
        var title: String
        var name: String
        var status: String
        var amount: String
        var icon: String
        var color: Color
        var section: MacWorkspaceSection
    }
    private var schedule: [ScheduleItem] {
        let now = Date(), today = Calendar.current.startOfDay(for: Date())
        let horizon = Calendar.current.date(byAdding: .day, value: 30, to: today)!
        var result: [ScheduleItem] = []
        for deposit in deposits where deposit.deletedAt == nil && deposit.isActive {
            if deposit.maturityDate <= horizon {
                result.append(.init(id: "deposit-\(deposit.id)", date: deposit.maturityDate, title: L10n.text("mac.overviewView.schedule.578f974b8f"), name: deposit.bankName,
                    status: deposit.maturityDate < today ? L10n.text("mac.overviewView.schedule.999a459c3f") : L10n.text("mac.overviewView.schedule.d3bec7add3"), amount: "\(MacOverviewStyle.money(deposit.originalPrincipal)) \(deposit.originalCurrency)", icon: "building.columns", color: .orange, section: .deposits))
            }
            if let payout = deposit.nextInterestPayoutDate, payout <= horizon {
                result.append(.init(id: "interest-\(deposit.id)", date: payout, title: L10n.text("mac.overviewView.schedule.fb9f253d5a"), name: deposit.bankName,
                    status: payout < now ? L10n.text("mac.overviewView.schedule.a8b0bd9c65") : L10n.text("mac.overviewView.schedule.92a4ddf489"), amount: L10n.text("mac.overviewView.schedule.39948ec137"), icon: "arrow.down.to.line", color: MacOverviewStyle.income, section: .deposits))
            }
        }
        for rule in recurring where rule.deletedAt == nil && rule.isActive && rule.nextExecutionDate <= horizon
            && (rule.endDate == nil || rule.nextExecutionDate <= rule.endDate!) && !(rule.projectIdentifier ?? "").hasPrefix(MacLoanRepayment.originalGeneratedPrefix) {
            let income = rule.typedType == .income
            result.append(.init(id: "rule-\(rule.id)", date: rule.nextExecutionDate, title: income ? L10n.text("mac.overviewView.schedule.3ed30b1533") : L10n.text("mac.overviewView.schedule.098c936766"), name: rule.title,
                status: rule.nextExecutionDate < now ? L10n.text("mac.overviewView.schedule.999a459c3f") : L10n.text("mac.overviewView.schedule.92a4ddf489"), amount: "\(income ? "+" : "−")\(MacOverviewStyle.money(rule.originalAmount)) \(rule.originalCurrency)", icon: "clock.arrow.circlepath", color: income ? MacOverviewStyle.income : MacOverviewStyle.expense, section: .recurring))
        }
        if let bookCurrency {
            for loan in loans where loan.deletedAt == nil {
                // Read the existing receipt audit with a future horizon; never infer payment from the schedule.
                if let next = try? MacLoanRepayment.nextPayment(loan, now: horizon, bookCurrency: bookCurrency, in: context) {
                    result.append(.init(id: "loan-\(loan.id)", date: next.payment.date, title: L10n.text("mac.overviewView.schedule.5bbe75029c"), name: loan.title,
                        status: next.payment.date < today ? L10n.text("mac.overviewView.schedule.a8b0bd9c65") : L10n.text("mac.overviewView.schedule.92a4ddf489"), amount: "−\(MacOverviewStyle.money(next.payment.total)) \(loan.currency)", icon: "banknote", color: .purple, section: .loans))
                }
            }
        }
        return result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
    private var scheduleCard: some View {
        OverviewCard(help: L10n.text("mac.overviewView.OverviewCard.90398cb8ba"), height: 250) {
            VStack(alignment: .leading, spacing: MacUI.space(12)) {
                VStack(alignment: .leading, spacing: MacUI.space(4)) {
                    Text(L10n.text("mac.overviewView.OverviewCard.e1c1309b39")).appFont(.body, weight: .semibold, design: .default).accessibilityIdentifier("overviewScheduleTitle")
                    Text(L10n.text("mac.overviewView.OverviewCard.06fef03fc9")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                }
                if schedule.isEmpty { empty(L10n.text("mac.overviewView.empty.f880b7b62b"), icon: "calendar").frame(height: MacUI.space(145)) }
                else {
                    ScrollView {
                        VStack(spacing: 0) { ForEach(schedule.prefix(4)) { row in
                            Button { workspace.section = row.section } label: {
                                HStack(spacing: MacUI.space(8)) {
                                    Image(systemName: row.icon).foregroundStyle(row.color).frame(width: MacUI.space(27), height: MacUI.space(27)).background(row.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: MacUI.space(3)) {
                                        HStack(spacing: MacUI.space(6)) {
                                            Text(row.title).appFont(.caption, weight: .medium).lineLimit(1)
                                            scheduleStatus(row)
                                            Spacer(minLength: 0)
                                            Text(row.date, format: .dateTime.month(.abbreviated).day().locale(L10n.locale)).appFont(.caption).foregroundStyle(.secondary).fixedSize()
                                        }
                                        HStack(spacing: MacUI.space(6)) {
                                            Text(row.name).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                                            Spacer(minLength: 0)
                                            scheduleAmount(row)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.appPadding(.vertical, 4).contentShape(Rectangle())
                            }.buttonStyle(MacInteractiveButtonStyle()).appHelp(row.title + " · " + row.name + " · " + row.amount).accessibilityIdentifier("overviewSchedule-" + row.id)
                            if row.id != schedule.prefix(4).last?.id { Divider() }
                        } }
                    }.frame(maxWidth: .infinity).accessibilityIdentifier("overviewScheduleList")
                }

                Text(L10n.text("mac.overviewView.OverviewCard.78afe68cd4")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("overviewScheduleCard")
    }
    private func scheduleStatus(_ row: ScheduleItem) -> some View {
        Text(row.status).appFont(.caption).foregroundStyle(row.color).lineLimit(1).minimumScaleFactor(0.8)
            .appPadding(.horizontal, 4).appPadding(.vertical, 1).background(row.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }
    private func scheduleAmount(_ row: ScheduleItem) -> some View {
        Text(row.amount).appFont(.caption).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).layoutPriority(1)
    }

    private var recentCard: some View {
        OverviewCard(help: L10n.text("mac.overviewView.OverviewCard.d0be7bc663")) {
            VStack(alignment: .leading, spacing: MacUI.space(13)) {
                HStack {
                    Text(L10n.text("mac.overviewView.OverviewCard.c2233955c3")).appFont(.body, weight: .semibold, design: .default); Spacer()
                    Button(L10n.text("mac.overviewView.OverviewCard.b92c0ea98b")) { workspace.showRecords(scope) }.buttonStyle(MacInteractiveButtonStyle()).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).accessibilityIdentifier("overviewAllRecords")
                }
                if periodRows.isEmpty { empty(L10n.text("mac.overviewView.empty.8eb6f974ea"), icon: "doc.text").appMinHeight(100).accessibilityIdentifier("overviewNoRecords") }
                else {
                    recentTransactionTable(Array(periodRows.prefix(5)))
                }
            }
        }
    }

    private var recentAmountColumnWidth: CGFloat {
        let font = MacInterfaceFonts.font(size: MacUI.fontSize(.caption, tier: MacUI.fontTier), weight: .regular, monospacedDigits: true)
        let values = periodRows.prefix(5).map { (MacOverviewStyle.money($0.baseAmount) as NSString).size(withAttributes: [.font: font]).width }
        return max(MacUI.space(105), (values.max() ?? 0) + MacUI.space(10))
    }

    @ViewBuilder
    private func recentTransactionTable(_ rows: [Transaction]) -> some View {
        ViewThatFits(in: .horizontal) {
            VStack(spacing: MacUI.space(0)) {
                HStack(spacing: MacUI.space(8)) {
                    Text(L10n.text("mac.overviewView.ViewThatFits.70d0c1b336")).frame(width: MacUI.space(90), alignment: .leading)
                    Text(L10n.text("mac.overviewView.ViewThatFits.4262c45dc7")).frame(maxWidth: .infinity, alignment: .leading)
                    Text(L10n.text("mac.overviewView.ViewThatFits.0d12cbd656")).frame(width: MacUI.space(85), alignment: .leading)
                    Text(L10n.text("mac.overviewView.ViewThatFits.117d8f914d")).frame(width: recentAmountColumnWidth, alignment: .trailing)
                    Text(L10n.text("mac.overviewView.ViewThatFits.e679096865")).frame(width: recentAmountColumnWidth, alignment: .trailing)
                }.appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                ForEach(rows, id: \.id) { row in recentTransactionRow(row, compact: false); Divider() }
            }

            VStack(spacing: MacUI.space(0)) {
                ForEach(rows, id: \.id) { row in recentTransactionRow(row, compact: true); Divider() }
            }
        }
    }

    private func recentTransactionRow(_ row: Transaction, compact: Bool) -> some View {
        let note = MacPreferences.defaults.object(forKey: "v2_notes") as? Bool == false || MacFinanceNotes.visible(row.note).isEmpty
            ? MacOverviewStyle.category(row.category) : MacFinanceNotes.visible(row.note)
        let amount = MacOverviewStyle.money(row.baseAmount)
        return Button { detailTransaction = row } label: {
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: MacUI.space(4)) {
                        HStack(spacing: MacUI.space(8)) {
                            Text(MacDateDisplay.string(row.date)).lineLimit(1)
                            Text(MacOverviewStyle.category(row.category)).lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 3)
                            Text(row.typedType == .income ? L10n.text("mac.overviewView.recentTransactionRow.117d8f914d") : L10n.text("mac.overviewView.recentTransactionRow.e679096865")).foregroundStyle(row.typedType == .income ? MacOverviewStyle.income : .secondary)
                        }
                        HStack(spacing: MacUI.space(8)) {
                            Text(note).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1).truncationMode(.tail)
                            Text(amount).monospacedDigit().lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                .foregroundStyle(row.typedType == .income ? MacOverviewStyle.income : .primary)
                        }
                    }.appPadding(.vertical, 7)
                } else {
                    HStack(spacing: MacUI.space(8)) {
                        Text(MacDateDisplay.string(row.date)).frame(width: MacUI.space(90), alignment: .leading)
                        Text(note).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1).truncationMode(.tail)
                        Text(MacOverviewStyle.category(row.category)).frame(width: MacUI.space(85), alignment: .leading).lineLimit(1).truncationMode(.tail)
                        Text(row.typedType == .income ? amount : "—").foregroundStyle(row.typedType == .income ? MacOverviewStyle.income : .secondary)
                            .frame(width: recentAmountColumnWidth, alignment: .trailing)
                        Text(row.typedType == .expense ? amount : "—").frame(width: recentAmountColumnWidth, alignment: .trailing)
                    }.appPadding(.vertical, 6)
                }
            }
            .appFont(.caption, weight: .regular, design: .default).monospacedDigit().contentShape(Rectangle())
        }
        .buttonStyle(MacInteractiveButtonStyle())
        .accessibilityIdentifier("overviewTransaction-\(row.id)")
        .accessibilityValue(amount + " " + row.baseCurrencyCode)
    }
    private func empty(_ title: String, icon: String) -> some View {
        VStack(spacing: MacUI.space(12)) {
            Image(systemName: icon).appIconFont(26, weight: .light, design: .default).foregroundStyle(.tertiary)
            Text(title).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
    private var assetDetails: some View {
        let snapshot = self.snapshot
        return VStack(alignment: .leading, spacing: MacUI.space(13)) {
            Text(L10n.text("mac.overviewView.assetDetails.435ca0ba9e")).appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("overviewAssetDetails")
            Text(L10n.format("mac.overviewView.assetDetails.4604728bdc", "\(MacDateDisplay.string(Date()))", "\(currency)")).foregroundStyle(.secondary)
            LabeledContent(L10n.text("mac.overviewView.LabeledContent.daa53f7d33"), value: MacOverviewStyle.money(snapshot.availableAssets))
            LabeledContent(L10n.text("mac.overviewView.LabeledContent.4b283a8dec"), value: MacOverviewStyle.money(snapshot.frozenDepositPrincipal))
            LabeledContent(L10n.text("mac.overviewView.LabeledContent.5b5c033985"), value: MacOverviewStyle.money(snapshot.manualDebtBalance))
            LabeledContent(L10n.text("mac.overviewView.LabeledContent.a4312bb4fa"), value: MacOverviewStyle.money(snapshot.loanBalance))
            Text(L10n.text("mac.overviewView.assetDetails.45a7124494")).appFont(.caption).foregroundStyle(.secondary)
            Divider()
            LabeledContent(L10n.text("mac.overviewView.LabeledContent.be2f841884"), value: MacOverviewStyle.money(snapshot.netWorth)).appFont(.section, weight: .semibold)
            Text(L10n.text("mac.overviewView.assetDetails.168490e724"))
                .appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            HStack {
                Button(L10n.text("mac.overviewView.assetDetails.2109f74eb1")) { showsProfileEditor = true }
                    .accessibilityIdentifier("overviewEditAssets").disabled(bookCurrency == nil)
                Spacer(); Button(L10n.text("mac.overviewView.assetDetails.3fd47edce4")) { showsAssets = false }.keyboardShortcut(.cancelAction).accessibilityIdentifier("overviewCloseAssets")
            }
        }.appPadding(26).appDialog(width: 540)
    }
}

private struct MacOverviewGoalManager: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    let currency: String?
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Goal.createdAt) private var goals: [Goal]
    @State private var adding = false
    @State private var editing: Goal?
    private var presentations: [String: MacGoalPresentation] { MacSettingsStore.load("v2_goal_presentation", fallback: [:]) }
    private func presentation(_ goal: Goal) -> MacGoalPresentation { presentations[goal.id.uuidString] ?? .init() }
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(18)) {
            HStack {
                Text(L10n.text("mac.overviewView.body.9d3fe41a1e")).appFont(.dialogTitle, weight: .semibold); Spacer()
                Button(L10n.text("mac.overviewView.body.da6caff0fb"), systemImage: "plus") { adding = true }.disabled(currency == nil).accessibilityIdentifier("overviewAddGoal")
            }
            if goals.filter({ $0.deletedAt == nil }).isEmpty {
                ContentUnavailableView(L10n.text("mac.overviewView.ContentUnavailableView.5e4beda275"), systemImage: "target", description: Text(L10n.text("mac.overviewView.ContentUnavailableView.50e728d728")))
            } else {
                List(goals.filter { $0.deletedAt == nil }, id: \.id) { goal in
                    HStack {
                        MacSettingsIcon(symbol: presentation(goal).icon, color: MacAccent.color(presentation(goal).color), size: 34)
                        VStack(alignment: .leading, spacing: MacUI.space(7)) {
                            Text(goal.title).appFont(.section, weight: .semibold)
                            Text("\(MacOverviewStyle.money(goal.targetAmount)) \(currency ?? L10n.text("mac.overviewView.List.7710d6e903")) · \(goal.isPaused ? L10n.text("mac.overviewView.List.eb0c326b60") : L10n.text("mac.overviewView.List.dc9591e56d"))").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                            Text(goal.includesCurrentAssets ? L10n.text("mac.overviewView.List.8b61957eea") : L10n.text("mac.overviewView.List.3d7a76110f")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L10n.text("mac.overviewView.List.ea5e05f38c")) { editing = goal }.buttonStyle(.borderless).disabled(currency == nil)
                            .accessibilityIdentifier("overviewEditGoal-\(goal.id)")
                    }.appPadding(.vertical, 8)
                }
            }
            HStack { Spacer(); Button(L10n.text("mac.overviewView.body.c0b3fbff51")) { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("overviewCloseGoals") }
        }.appPadding(24).appPanel(width: 590, height: 430)
        .sheet(isPresented: $adding) { if let currency { MacFinanceEditor(panel: .goals, currency: currency, onSaved: {}) } }
        .sheet(item: $editing) { goal in if let currency { MacFinanceEditor(panel: .goals, currency: currency, existing: .goal(goal), onSaved: {}) } }
    }
}

private enum MacOverviewMetric: String, Identifiable {
    case income = "收入"
    case expense = "支出"
    case net = "净额"
    var id: String { rawValue }
}

private struct MacOverviewMetricDetails: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    let metric: MacOverviewMetric
    let scope: MacOverviewScope
    let currency: String
    let transactions: [Transaction]
    let trendMonths: Int
    let onOpenRecords: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var matchingRows: [Transaction] { transactions.filter { scope.matches($0, currency: currency) } }
    private var totals: (income: Double, expense: Double, net: Double) {
        MacTransactionCRUD.totals(transactions: matchingRows, currency: currency)
    }
    private var amount: Double {
        switch metric {
        case .income: totals.income
        case .expense: totals.expense
        case .net: totals.net
        }
    }
    private var matchingCount: Int {
        switch metric {
        case .income: matchingRows.filter { $0.typedType == .income }.count
        case .expense: matchingRows.filter { $0.typedType == .expense }.count
        case .net: matchingRows.count
        }
    }
    private var monthRows: [MacOverviewData.Month] {
        MacOverviewData.months(transactions, scope: scope, currency: currency, count: trendMonths)
    }
    private var title: String { L10n.builtIn(metric.rawValue) + L10n.text("mac.overviewView.title.55630dd739") }
    private var scopeDescription: String {
        scope.title + " · " + currency + (scope.category.map { " · " + MacOverviewStyle.category($0) } ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacUI.space(16)) {
                HStack {
                    VStack(alignment: .leading, spacing: MacUI.space(5)) {
                        Text(title).appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("overviewMetricDetailTitle")
                        Text(scopeDescription).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                            .accessibilityIdentifier("overviewMetricDetailScope")
                    }
                    Spacer()
                    Button(L10n.text("mac.overviewView.ScrollView.3fd47edce4")) { dismiss() }.accessibilityIdentifier("overviewMetricDetailClose")
                }
                HStack(spacing: MacUI.space(20)) {
                    VStack(alignment: .leading, spacing: MacUI.space(4)) {
                        Text(L10n.builtIn(metric.rawValue)).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                        Text(MacOverviewStyle.money(amount) + " " + currency).appFont(.dialogTitle, weight: .semibold).monospacedDigit()
                            .accessibilityIdentifier("overviewMetricDetailValue")
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: MacUI.space(4)) {
                        Text(L10n.text("mac.overviewView.ScrollView.3c69207349")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                        Text("\(matchingCount)").appFont(.section, weight: .semibold).monospacedDigit()
                            .accessibilityIdentifier("overviewMetricDetailCount")
                    }
                }
                .appPadding(14)
                .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 11))

                GroupBox(L10n.text("mac.overviewView.GroupBox.099b7967fd")) {
                    VStack(alignment: .leading, spacing: MacUI.space(12)) {
                        if metric != .expense { distribution(.income) }
                        if metric != .income { distribution(.expense) }
                    }.frame(maxWidth: .infinity, alignment: .leading).appPadding(.top, 5)
                }
                GroupBox(L10n.text("mac.overviewView.GroupBox.0f43f91f9c")) {
                    Chart(monthRows) { month in
                        if metric != .expense {
                            LineMark(x: .value(L10n.text("mac.overviewView.LineMark.a27822d135"), month.id, unit: .month), y: .value(L10n.text("mac.overviewView.LineMark.117d8f914d"), month.income), series: .value(L10n.text("mac.overviewView.LineMark.f0bbe3fb0f"), L10n.text("mac.overviewView.LineMark.117d8f914d")))
                                .foregroundStyle(MacOverviewStyle.income)
                        }
                        if metric != .income {
                            LineMark(x: .value(L10n.text("mac.overviewView.LineMark.a27822d135"), month.id, unit: .month), y: .value(L10n.text("mac.overviewView.LineMark.e679096865"), month.expense), series: .value(L10n.text("mac.overviewView.LineMark.f0bbe3fb0f"), L10n.text("mac.overviewView.LineMark.e679096865")))
                                .foregroundStyle(MacOverviewStyle.expense)
                        }
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month()) } }
                    .frame(height: MacUI.space(175)).appPadding(.vertical, 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("overviewMetricDetailTrend")
                    .accessibilityLabel(L10n.format("mac.overviewView.GroupBox.7f2f55debd", "\(scopeDescription)"))
                }
                HStack {
                    Button(L10n.text("mac.overviewView.ScrollView.d78ecdf7e8")) { onOpenRecords() }.accessibilityIdentifier("overviewMetricDetailRecords")
                    Spacer()
                    Text(L10n.text("mac.overviewView.ScrollView.edcbaeb5a0")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                }
            }
            .appPadding(22)
        }
        .frame(minWidth: 610, idealWidth: 760, maxWidth: 780, minHeight: 440, maxHeight: 760)
        .appDialog(width: 780)
    }

    @ViewBuilder
    private func distribution(_ type: TransactionType) -> some View {
        let rows = MacOverviewData.categories(matchingRows, type: type)
        let name = type == .income ? L10n.text("mac.overviewView.name.117d8f914d") : L10n.text("mac.overviewView.name.e679096865")
        if rows.isEmpty {
            Text(L10n.format("mac.overviewView.distribution.cbd05802e0", "\(name)")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                .accessibilityIdentifier("overviewMetricDetail-\(name)-empty")
        } else {
            VStack(alignment: .leading, spacing: MacUI.space(6)) {
                Text(name + L10n.text("mac.overviewView.distribution.0d12cbd656")).appFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                Chart(rows.prefix(8)) { row in
                    BarMark(x: .value(L10n.text("mac.overviewView.BarMark.ffc624300d"), row.amount), y: .value(L10n.text("mac.overviewView.BarMark.0d12cbd656"), MacOverviewStyle.category(row.id)))
                        .foregroundStyle(type == .income ? MacOverviewStyle.income : MacOverviewStyle.expense)
                }
                .chartXAxis { AxisMarks(position: .bottom) }
                .frame(height: MacUI.space(CGFloat(min(156, 44 + rows.prefix(8).count * 23))))
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("overviewMetricDetail-\(name)-categories")
                .accessibilityLabel(L10n.format("mac.overviewView.distribution.9f7e237b50", "\(scopeDescription)", "\(name)", "\(rows.prefix(8).map { MacOverviewStyle.category($0.id) + " " + MacOverviewStyle.money($0.amount) }.joined(separator: "、"))"))
            }
        }
    }
}

/// Pointer movement updates only the chart, not ledger queries and all cards.
private struct MacOverviewTrendCard: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    let scope: MacOverviewScope
    let currency: String
    @Binding var trendMonths: Int
    let trend: [MacOverviewData.Month]
    let showRecords: (MacOverviewScope) -> Void
    let createRecord: () -> Void
    @State private var hoveredMonth: MacOverviewData.Month?

    var body: some View {
        OverviewCard(help: L10n.text("mac.overviewView.OverviewCard.cda6b079a1"), height: 250) {
            VStack(alignment: .leading, spacing: MacUI.space(16)) {
                HStack {
                    Text(L10n.text("mac.overviewView.OverviewCard.01a96bd794")).appFont(.body, weight: .semibold, design: .default); Spacer()
                    MacSettingsMenu(selection: $trendMonths, options: [(L10n.text("mac.overviewView.MacSettingsMenu.9111ba53c3"), 6), (L10n.text("mac.overviewView.MacSettingsMenu.0c00594c25"), 12)]).frame(width: max(170, MacUI.fontTier.bodySize * 9 + 30)).accessibilityIdentifier("overviewTrendRange")
                    Button { var records = scope; records.period = .custom; records.from = trend.first?.id ?? scope.reference; records.through = Calendar.current.dateInterval(of: .month, for: scope.reference)!.end.addingTimeInterval(-1); showRecords(records) } label: { Image(systemName: "arrow.up.right") }
                        .buttonStyle(MacInteractiveButtonStyle()).appHelp(L10n.text("mac.overviewView.OverviewCard.2d7f7d57db"))
                }
                if trend.allSatisfy({$0.income == 0 && $0.expense == 0}) {
                    ContentUnavailableView {Label(L10n.text("mac.overviewView.ContentUnavailableView.10ca4df494"),systemImage:"chart.bar")} description:{Text(L10n.text("mac.overviewView.ContentUnavailableView.d373c437c8"))} actions:{Button(L10n.text("mac.overviewView.ContentUnavailableView.5a15649c24"),action:createRecord)}.frame(maxWidth:.infinity,maxHeight:.infinity)
                } else {
                Chart(trend) { month in
                    BarMark(x: .value(L10n.text("mac.overviewView.BarMark.a27822d135"), month.id, unit: .month), y: .value(L10n.text("mac.overviewView.BarMark.ffc624300d"), month.income))
                        .position(by: .value(L10n.text("mac.overviewView.Chart.ba40014ff4"), L10n.text("mac.overviewView.Chart.117d8f914d"))).foregroundStyle(by: .value(L10n.text("mac.overviewView.Chart.ba40014ff4"), L10n.text("mac.overviewView.Chart.117d8f914d")))
                        .cornerRadius(3)
                    BarMark(x: .value(L10n.text("mac.overviewView.BarMark.a27822d135"), month.id, unit: .month), y: .value(L10n.text("mac.overviewView.BarMark.ffc624300d"), month.expense))
                        .position(by: .value(L10n.text("mac.overviewView.Chart.ba40014ff4"), L10n.text("mac.overviewView.Chart.e679096865"))).foregroundStyle(by: .value(L10n.text("mac.overviewView.Chart.ba40014ff4"), L10n.text("mac.overviewView.Chart.e679096865")))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale([L10n.text("mac.overviewView.Chart.117d8f914d"): MacOverviewStyle.income, L10n.text("mac.overviewView.Chart.e679096865"): MacOverviewStyle.expense])
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { value in AxisValueLabel(centered: true) { if let date = value.as(Date.self) { Text(date.formatted(.dateTime.month(.abbreviated).locale(L10n.locale))) } } } }
                .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() } }
                .chartLegend(position: .top, alignment: .trailing)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let point):
                                    guard let anchor = proxy.plotFrame else { return }
                                    let frame = geometry[anchor]
                                    guard frame.contains(point), let date: Date = proxy.value(atX: point.x - frame.minX) else { hoveredMonth = nil; return }
                                    hoveredMonth = trend.first { Calendar.current.isDate($0.id, equalTo: date, toGranularity: .month) }
                                case .ended: hoveredMonth = nil
                                }
                            }
                            .onTapGesture {
                                guard let month = hoveredMonth, let range = Calendar.current.dateInterval(of: .month, for: month.id) else { return }
                                var records = scope; records.period = .custom; records.from = range.start; records.through = range.end.addingTimeInterval(-1)
                                showRecords(records)
                            }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let month = hoveredMonth {
                        VStack(alignment: .leading, spacing: MacUI.space(5)) {
                            Text(month.id, format: .dateTime.year().month()).fontWeight(.semibold)
                            Text(L10n.format("mac.overviewView.OverviewCard.2df00b9cfd", "\(MacOverviewStyle.money(month.income))", "\(currency)"))
                            Text(L10n.format("mac.overviewView.OverviewCard.c4d61958c4", "\(MacOverviewStyle.money(month.expense))", "\(currency)"))
                        }.appFont(.caption, weight: .regular, design: .default).monospacedDigit().appPadding(9)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                            .allowsHitTesting(false)
                    }
                }
                .appMinHeight(140).accessibilityIdentifier("overviewTrendChart")
                }
                Text(L10n.format("mac.overviewView.OverviewCard.198b557967", "\(scope.reference.formatted(.dateTime.year().month().locale(L10n.locale)))", "\(currency)")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
            }
        }
    }

}
