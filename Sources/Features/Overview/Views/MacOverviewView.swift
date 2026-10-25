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

struct MacOverviewView: View {
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
    private var profile: FinancialProfile? { profiles.first { $0.deletedAt == nil } }
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
                            Label("账本包含不同本位币，请先在设置中核对后再汇总。", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange).accessibilityIdentifier("overviewMixedCurrency")
                        }
                        if !scope.isValid { Text("开始日期不能晚于结束日期。").foregroundStyle(.red) }
                        metrics(contentWidth: innerContentWidth)
                        trendCard
                        if keepsCardsInPairs {
                            HStack(alignment: .top, spacing: MacUI.space(15)) {
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
                        }.buttonStyle(MacInteractiveButtonStyle()).appHelp("快速记账")
                            .accessibilityLabel("快速记账").accessibilityIdentifier("overviewQuickRecord")
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
                Text("交易详情").appFont(.dialogTitle, weight: .semibold)
                LabeledContent("类别", value: MacOverviewStyle.category(row.category))
                LabeledContent("日期", value: MacDateDisplay.string(row.date))
                LabeledContent("原币金额", value: "\(MacOverviewStyle.money(row.originalAmount)) \(row.originalCurrency)")
                LabeledContent("记账金额", value: "\(MacOverviewStyle.money(row.baseAmount)) \(row.baseCurrencyCode)")
                if let note = row.note { Text(note).foregroundStyle(.secondary) }
                HStack {
                    Button("在账目中查看") { workspace.showRecords(scope); detailTransaction = nil }
                    Spacer(); Button("关闭") { detailTransaction = nil }.keyboardShortcut(.cancelAction)
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
            Text(scope.title + ((MacPreferences.isTesting && ProcessInfo.processInfo.environment["FINTRACK_V2_DEMO"] == "1") ? " · 演示账本（虚构）" : "") + (scope.category.map { " · " + MacOverviewStyle.category($0) } ?? ""))
                .appFont(.body, weight: .medium, design: .default).foregroundStyle(.secondary)
                .accessibilityIdentifier("overviewTitle")
            Spacer()
            Text("本位币  \(currency)").appFont(.caption, weight: .medium, design: .default).foregroundStyle(.secondary)
                .appHelp("金额使用已保存的本位币快照；修改本位币请前往设置。")
        }.appPadding(.bottom, 3)
    }
    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: MacUI.space(20)) {
            Text("筛选").appFont(.section, weight: .semibold)
            ScrollView { filterControls }
            Spacer(minLength: 8)
            Text("收支按所选期间统计\n资产与目标显示当前状态")
                .appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).lineSpacing(4)
        }.appPadding(18).frame(maxHeight: .infinity).background(MacOverviewStyle.filters)
    }
    private var filterControls: some View {
        let categoryRows = self.categoryRows
        return VStack(alignment: .leading, spacing: MacUI.space(18)) {
            Text("时间范围").appFont(.caption, weight: .semibold, design: .default).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MacUI.space(7)) {
                ForEach(MacOverviewScope.Period.allCases) { period in
                    Button { scope.period = period } label: {
                        Text(period.rawValue).appFont(.caption, weight: .regular, design: .default).frame(maxWidth: .infinity).appPadding(.vertical, 8)
                            .background(scope.period == period ? MacOverviewStyle.accent.opacity(0.16) : MacOverviewStyle.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(scope.period == period ? MacOverviewStyle.accent : .primary)
                    }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("overviewPeriod-\(period.id)")
                }
            }
            if scope.period == .month || scope.period == .year {
                HStack(spacing: MacUI.space(6)) {
                    Button { movePeriod(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("上一期间").accessibilityIdentifier("overviewPreviousPeriod")
                    Button { showsMonthPicker = true } label: { Text(scope.title).appFont(.caption, weight: .regular, design: .default).frame(maxWidth: .infinity) }
                        .focused($monthPickerAnchorFocused)
                        .accessibilityIdentifier("overviewMonthPicker")
                        .popover(isPresented: $showsMonthPicker) {
                            MacCalendarPickerPopover(
                                title: "选择日期",
                                selection: $scope.reference,
                                pickerIdentifier: "overviewMonthDatePicker",
                                doneIdentifier: "overviewMonthDateDone",
                                onDone: { showsMonthPicker = false }
                            )
                        }
                        .onChange(of: showsMonthPicker) { _, isPresented in if !isPresented { monthPickerAnchorFocused = true } }
                    Button { movePeriod(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("下一期间").accessibilityIdentifier("overviewNextPeriod")
                }.buttonStyle(MacInteractiveButtonStyle()).appPadding(10).background(MacOverviewStyle.card.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
            } else if scope.period == .custom {
                MacDateTimeField(title: "开始", date: $scope.from).accessibilityIdentifier("overviewFrom")
                MacDateTimeField(title: "结束", date: $scope.through).accessibilityIdentifier("overviewThrough")
            }
            Divider()
            Text("收支类型").appFont(.caption, weight: .semibold, design: .default).foregroundStyle(.secondary)
            MacSettingsMenu(selection: $scope.type, options: [("全部收支", TransactionType?.none), ("收入", Optional(TransactionType.income)), ("支出", Optional(TransactionType.expense))]).accessibilityIdentifier("overviewTypeFilter")
            Text("账目类别").appFont(.caption, weight: .semibold, design: .default).foregroundStyle(.secondary)
            Button { scope.category = nil } label: {
                filterRow("全部类别", icon: "square.grid.2x2", selected: scope.category == nil, count: nil)
            }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("overviewAllCategories")
            VStack(spacing: MacUI.space(3)) { ForEach(categoryRows) { row in
                Button { scope.category = row.id } label: {
                    filterRow(MacOverviewStyle.category(row.id), icon: MacCategoryCatalog.style(name: row.id, type: (scope.type ?? .expense).rawValue).symbol, selected: scope.category == row.id, count: row.count)
                }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("overviewCategory-\(row.id)")
            } }
            if categoryRows.isEmpty { Text("该期间暂无类别").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
            if scope.category != nil && !categoryRows.contains(where: { $0.id == scope.category }) {
                Button("清除已选类别") { scope.category = nil }.appFont(.caption, weight: .regular)
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
        let font = MacInterfaceFonts.font(size: MacUI.fontSize(.amount, tier: tier), weight: .semibold, monospacedDigits: true)
        let currencyFont = MacInterfaceFonts.font(size: MacUI.fontSize(.caption, tier: tier), weight: .medium)
        let amounts = [totals.income, totals.expense, totals.net, snapshot.availableAssets + snapshot.frozenDepositPrincipal]
        let textWidth = amounts.map { (MacOverviewStyle.money($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let currencyWidth = (currency as NSString).size(withAttributes: [.font: currencyFont]).width
        let spacing = MacUI.space(13)
        let minimumCardWidth = max(MacUI.space(220), textWidth + currencyWidth + MacUI.space(54))
        let columnCount = contentWidth >= minimumCardWidth * 4 + spacing * 3 ? 4
            : contentWidth >= minimumCardWidth * 2 + spacing ? 2 : 1
        let cellMinimum = columnCount == 1 ? min(minimumCardWidth, max(1, contentWidth)) : minimumCardWidth
        let columns = Array(repeating: GridItem(.flexible(minimum: cellMinimum), spacing: spacing), count: columnCount)
        return LazyVGrid(columns: columns, spacing: spacing) {
            metric("支出", value: totals.expense, prior: previous?.expense, icon: "arrow.down.right", color: MacOverviewStyle.expense, id: "overviewExpense", detail: .expense) {
                var records = scope; records.type = .expense; workspace.showRecords(records)
            }
            metric("收入", value: totals.income, prior: previous?.income, icon: "arrow.up.right", color: MacOverviewStyle.income, id: "overviewIncome", detail: .income) {
                var records = scope; records.type = .income; workspace.showRecords(records)
            }
            metric("净额", value: totals.net, prior: previous?.net, icon: "arrow.right", color: MacOverviewStyle.accent, id: "overviewNet", detail: .net) { workspace.showRecords(scope) }
            metric("资产总额", value: snapshot.availableAssets + snapshot.frozenDepositPrincipal, prior: nil, icon: "square.stack.3d.up", color: .blue, id: "overviewAssets", current: true) { showsAssets = true }
        }
    }
    private func metric(_ title: String, value: Double, prior: Double?, icon: String, color: Color, id: String,
                        current: Bool = false, detail: MacOverviewMetric? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            OverviewCard(help: current ? "查看当前资产、负债和净资产口径" : "查看该期间的\(title)账目", height: 114) {
                VStack(alignment: .leading, spacing: MacUI.space(8)) {
                    HStack(spacing: MacUI.space(9)) {
                        Image(systemName: icon).appFont(.body, weight: .medium, design: .default).foregroundStyle(color)
                            .frame(width: MacUI.space(29), height: MacUI.space(29)).background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                        Text(title).appFont(.body, weight: .semibold, design: .default); Spacer()
                        if detail == nil { Image(systemName: "chevron.right").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.tertiary) }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: MacUI.space(5)) {
                        Spacer(minLength: 0)
                        Text(bookCurrency == nil ? "—" : MacOverviewStyle.money(value)).appFont(.amount, weight: .semibold, design: .default).monospacedDigit().fixedSize(horizontal: true, vertical: false)
                        Text(MacSettingsVisual.symbol(currency)).appFont(.body, weight: .medium, design: .default).foregroundStyle(.secondary).fixedSize(horizontal: true, vertical: false)
                    }.accessibilityElement(children: .combine).accessibilityIdentifier(id)
                    if current {
                        Text("当前 · 不随期间筛选").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                    } else if let prior, let change = MacOverviewData.change(current: value, previous: prior) {
                        HStack(spacing: MacUI.space(4)) {
                            Text(scope.period == .year ? "较上年" : (scope.period == .custom ? "较前期" : "较上月")).foregroundStyle(.secondary)
                            Text((change >= 0 ? "+" : "") + change.formatted(.percent.precision(.fractionLength(1)))).foregroundStyle(color)
                        }.appFont(.caption, weight: .regular, design: .default).monospacedDigit()
                    } else { Text("暂无可比数据").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }
                }
            }
        }
        .buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier(id + "Card").disabled(bookCurrency == nil)
        .overlay(alignment: .topTrailing) {
            if let detail {
                Button { detailMetric = detail } label: {
                    Label("统计详情", systemImage: "chart.bar.xaxis").appFont(.caption, weight: .medium, design: .default)
                        .foregroundStyle(MacOverviewStyle.accent).padding(.horizontal, 8).padding(.vertical, 5)
                        .background(MacOverviewStyle.accent.opacity(0.07), in: Capsule())
                }
                .buttonStyle(MacInteractiveButtonStyle())
                .appHelp("打开\(title)统计详情；卡片主体仍可直接查看账目")
                .accessibilityIdentifier(id + "Statistics")
                .padding(.top, MacUI.space(23)).padding(.trailing, MacUI.space(17))
                .disabled(bookCurrency == nil)
            }
        }
    }

    private var trendCard: some View {
        MacOverviewTrendCard(scope: scope, currency: currency, trendMonths: $trendMonths,
                             trend: trend, showRecords: { workspace.showRecords($0) })
    }
    private var goalCard: some View {
        let snapshot = self.snapshot
        return Button { showsGoals = true } label: {
            OverviewCard(help: "查看、新建、编辑或暂停财务目标", height: 250) {
                VStack(alignment: .leading, spacing: MacUI.space(13)) {
                    HStack { Text("财务目标").appFont(.body, weight: .semibold, design: .default); Spacer(); Image(systemName: "arrow.up.right").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
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
                            VStack(alignment: .leading, spacing: MacUI.space(6)) { Text("当前净资产").foregroundStyle(.secondary); Text(bookCurrency == nil ? "待核对币种" : "\(MacOverviewStyle.money(snapshot.netWorth)) \(currency)").monospacedDigit() }
                            Spacer()
                            VStack(alignment: .leading, spacing: MacUI.space(6)) { Text("期望时间").foregroundStyle(.secondary); Text(MacGoalTargetDate.label(goal)) }
                        }.appFont(.caption, weight: .regular, design: .default)
                        Text(goal.isPaused ? "已暂停" : (goal.includesCurrentAssets ? "净资产目标 · 当前状态" : "新增资产目标 · 当前状态")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "target").appIconFont(30, weight: .light, design: .default).foregroundStyle(MacOverviewStyle.accent).appPadding(.top, 10)
                        Text("为下一步设定目标").appFont(.body, weight: .medium, design: .default)
                        Text("从当前资产出发，记录你的进度。").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                        Text("新建财务目标  +").appFont(.caption, weight: .medium, design: .default).foregroundStyle(MacOverviewStyle.accent)
                    }
                }.frame(minHeight: MacUI.space(185), alignment: .top)
            }
        }.buttonStyle(MacInteractiveButtonStyle())
            .accessibilityRepresentation {
                Button("财务目标") { showsGoals = true }.accessibilityIdentifier("overviewGoals")
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
                result.append(.init(id: "deposit-\(deposit.id)", date: deposit.maturityDate, title: "存款到期", name: deposit.bankName,
                    status: deposit.maturityDate < today ? "待处理" : "即将到期", amount: "\(MacOverviewStyle.money(deposit.originalPrincipal)) \(deposit.originalCurrency)", icon: "building.columns", color: .orange, section: .deposits))
            }
            if let payout = deposit.nextInterestPayoutDate, payout <= horizon {
                result.append(.init(id: "interest-\(deposit.id)", date: payout, title: "存款结息", name: deposit.bankName,
                    status: payout < now ? "待确认" : "计划发生", amount: "按结息明细", icon: "arrow.down.to.line", color: MacOverviewStyle.income, section: .deposits))
            }
        }
        for rule in recurring where rule.deletedAt == nil && rule.isActive && rule.nextExecutionDate <= horizon
            && (rule.endDate == nil || rule.nextExecutionDate <= rule.endDate!) && !(rule.projectIdentifier ?? "").hasPrefix(MacLoanRepayment.originalGeneratedPrefix) {
            let income = rule.typedType == .income
            result.append(.init(id: "rule-\(rule.id)", date: rule.nextExecutionDate, title: income ? "周期收入" : "周期支出", name: rule.title,
                status: rule.nextExecutionDate < now ? "待处理" : "计划发生", amount: "\(income ? "+" : "−")\(MacOverviewStyle.money(rule.originalAmount)) \(rule.originalCurrency)", icon: "clock.arrow.circlepath", color: income ? MacOverviewStyle.income : MacOverviewStyle.expense, section: .recurring))
        }
        if let bookCurrency {
            for loan in loans where loan.deletedAt == nil {
                // Read the existing receipt audit with a future horizon; never infer payment from the schedule.
                if let next = try? MacLoanRepayment.nextPayment(loan, now: horizon, bookCurrency: bookCurrency, in: context) {
                    result.append(.init(id: "loan-\(loan.id)", date: next.payment.date, title: "贷款还款", name: loan.title,
                        status: next.payment.date < today ? "待确认" : "计划发生", amount: "−\(MacOverviewStyle.money(next.payment.total)) \(loan.currency)", icon: "banknote", color: .purple, section: .loans))
                }
            }
        }
        return result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
    private var scheduleCard: some View {
        OverviewCard(help: "日程是计划或待确认事项，点击进入财务管理核对", height: 258) {
            VStack(alignment: .leading, spacing: MacUI.space(12)) {
                HStack {
                    Text("近期财务日程").appFont(.body, weight: .semibold, design: .default).accessibilityIdentifier("overviewScheduleTitle"); Spacer()
                    Text("未来 30 天及待处理").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                }
                if schedule.isEmpty { empty("暂无近期财务日程", icon: "calendar").frame(height: MacUI.space(145)) }
                else {
                    VStack(spacing: MacUI.space(0)) { ForEach(schedule.prefix(4)) { row in
                        Button { workspace.section = row.section } label: {
                            HStack(spacing: MacUI.space(10)) {
                                Text(row.date, format: .dateTime.month(.defaultDigits).day()).appFont(.caption, weight: .regular, design: .default).frame(width: MacUI.space(49), alignment: .leading)
                                Image(systemName: row.icon).foregroundStyle(row.color).frame(width: MacUI.space(29), height: MacUI.space(29)).background(row.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: MacUI.space(4)) { Text(row.title).appFont(.caption, weight: .medium, design: .default).lineLimit(1); Text(row.name).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail) }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Spacer(minLength: 3)
                                Text(row.status).appFont(.caption, weight: .regular, design: .default).foregroundStyle(row.color).appPadding(5).background(row.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                                Text(row.amount).appFont(.caption, weight: .regular, design: .default).monospacedDigit().lineLimit(1).fixedSize(horizontal: true, vertical: false).layoutPriority(1)
                            }.appPadding(.vertical, 4).contentShape(Rectangle())
                        }.buttonStyle(MacInteractiveButtonStyle()).appHelp("查看\(row.name)的详情").accessibilityIdentifier("overviewSchedule-" + row.id)
                        if row.id != schedule.prefix(4).last?.id { Divider() }
                    } }
                }
                Text("日程金额为计划，确认到账或付款后才入账。").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
            }.frame(minHeight: MacUI.space(185), alignment: .top)
        }
    }

    private var recentCard: some View {
        OverviewCard(help: "点击一笔交易查看原币和本位币快照") {
            VStack(alignment: .leading, spacing: MacUI.space(13)) {
                HStack {
                    Text("最近交易").appFont(.body, weight: .semibold, design: .default); Spacer()
                    Button("查看全部 ›") { workspace.showRecords(scope) }.buttonStyle(MacInteractiveButtonStyle()).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).accessibilityIdentifier("overviewAllRecords")
                }
                if periodRows.isEmpty { empty("该期间暂无交易", icon: "doc.text").appMinHeight(100).accessibilityIdentifier("overviewNoRecords") }
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
                    Text("日期").frame(width: MacUI.space(90), alignment: .leading)
                    Text("说明").frame(maxWidth: .infinity, alignment: .leading)
                    Text("类别").frame(width: MacUI.space(85), alignment: .leading)
                    Text("收入").frame(width: recentAmountColumnWidth, alignment: .trailing)
                    Text("支出").frame(width: recentAmountColumnWidth, alignment: .trailing)
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
                            Text(row.typedType == .income ? "收入" : "支出").foregroundStyle(row.typedType == .income ? MacOverviewStyle.income : .secondary)
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
            Text("当前资产与负债").appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("overviewAssetDetails")
            Text("时点：\(MacDateDisplay.string(Date())) · \(currency)").foregroundStyle(.secondary)
            LabeledContent("可用资产", value: MacOverviewStyle.money(snapshot.availableAssets))
            LabeledContent("存款本金", value: MacOverviewStyle.money(snapshot.frozenDepositPrincipal))
            LabeledContent("手工负债", value: MacOverviewStyle.money(snapshot.manualDebtBalance))
            LabeledContent("贷款余额", value: MacOverviewStyle.money(snapshot.loanBalance))
            Text("贷款按核验收据扣减本金；未核验的贷款暂保留完整本金。").appFont(.caption).foregroundStyle(.secondary)
            Divider()
            LabeledContent("净资产", value: MacOverviewStyle.money(snapshot.netWorth)).appFont(.section, weight: .semibold)
            Text("净资产 = 可用资产 + 存款本金 − 手工负债 − 贷款余额。历史时点余额不可用；期间筛选不改变当前资产。实际还款请在贷款模块核对。")
                .appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            HStack {
                Button("编辑初始资产与负债") { showsProfileEditor = true }
                    .accessibilityIdentifier("overviewEditAssets").disabled(bookCurrency == nil)
                Spacer(); Button("关闭") { showsAssets = false }.keyboardShortcut(.cancelAction).accessibilityIdentifier("overviewCloseAssets")
            }
        }.appPadding(26).appDialog(width: 540)
    }
}

private struct MacOverviewGoalManager: View {
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
                Text("财务目标").appFont(.dialogTitle, weight: .semibold); Spacer()
                Button("新建目标", systemImage: "plus") { adding = true }.disabled(currency == nil).accessibilityIdentifier("overviewAddGoal")
            }
            if goals.filter({ $0.deletedAt == nil }).isEmpty {
                ContentUnavailableView("还没有财务目标", systemImage: "target", description: Text("设定净资产目标或新增资产目标。"))
            } else {
                List(goals.filter { $0.deletedAt == nil }, id: \.id) { goal in
                    HStack {
                        MacSettingsIcon(symbol: presentation(goal).icon, color: MacAccent.color(presentation(goal).color), size: 34)
                        VStack(alignment: .leading, spacing: MacUI.space(7)) {
                            Text(goal.title).appFont(.section, weight: .semibold)
                            Text("\(MacOverviewStyle.money(goal.targetAmount)) \(currency ?? "待核对币种") · \(goal.isPaused ? "已暂停" : "进行中")").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                            Text(goal.includesCurrentAssets ? "净资产目标" : "新增资产目标").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("编辑 / 暂停") { editing = goal }.buttonStyle(.borderless).disabled(currency == nil)
                            .accessibilityIdentifier("overviewEditGoal-\(goal.id)")
                    }.appPadding(.vertical, 8)
                }
            }
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("overviewCloseGoals") }
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
    private var title: String { metric.rawValue + "统计详情" }
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
                    Button("关闭") { dismiss() }.accessibilityIdentifier("overviewMetricDetailClose")
                }
                HStack(spacing: MacUI.space(20)) {
                    VStack(alignment: .leading, spacing: MacUI.space(4)) {
                        Text(metric.rawValue).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                        Text(MacOverviewStyle.money(amount) + " " + currency).appFont(.dialogTitle, weight: .semibold).monospacedDigit()
                            .accessibilityIdentifier("overviewMetricDetailValue")
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: MacUI.space(4)) {
                        Text("账目数量").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                        Text("\(matchingCount)").appFont(.section, weight: .semibold).monospacedDigit()
                            .accessibilityIdentifier("overviewMetricDetailCount")
                    }
                }
                .appPadding(14)
                .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 11))

                GroupBox("分类明细") {
                    VStack(alignment: .leading, spacing: MacUI.space(12)) {
                        if metric != .expense { distribution(.income) }
                        if metric != .income { distribution(.expense) }
                    }.frame(maxWidth: .infinity, alignment: .leading).appPadding(.top, 5)
                }
                GroupBox("近期趋势") {
                    Chart(monthRows) { month in
                        if metric != .expense {
                            LineMark(x: .value("月份", month.id, unit: .month), y: .value("收入", month.income), series: .value("收支", "收入"))
                                .foregroundStyle(MacOverviewStyle.income)
                        }
                        if metric != .income {
                            LineMark(x: .value("月份", month.id, unit: .month), y: .value("支出", month.expense), series: .value("收支", "支出"))
                                .foregroundStyle(MacOverviewStyle.expense)
                        }
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month()) } }
                    .frame(height: MacUI.space(175)).appPadding(.vertical, 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("overviewMetricDetailTrend")
                    .accessibilityLabel("\(scopeDescription)的近期收入与支出趋势")
                }
                HStack {
                    Button("在账目中查看") { onOpenRecords() }.accessibilityIdentifier("overviewMetricDetailRecords")
                    Spacer()
                    Text("期间、币种、类别与收支筛选沿用概览").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
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
        let name = type == .income ? "收入" : "支出"
        if rows.isEmpty {
            Text("当前筛选下暂无\(name)类别").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                .accessibilityIdentifier("overviewMetricDetail-\(name)-empty")
        } else {
            VStack(alignment: .leading, spacing: MacUI.space(6)) {
                Text(name + "类别").appFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                Chart(rows.prefix(8)) { row in
                    BarMark(x: .value("金额", row.amount), y: .value("类别", MacOverviewStyle.category(row.id)))
                        .foregroundStyle(type == .income ? MacOverviewStyle.income : MacOverviewStyle.expense)
                }
                .chartXAxis { AxisMarks(position: .bottom) }
                .frame(height: MacUI.space(CGFloat(min(156, 44 + rows.prefix(8).count * 23))))
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("overviewMetricDetail-\(name)-categories")
                .accessibilityLabel("\(scopeDescription) · \(name)类别：\(rows.prefix(8).map { MacOverviewStyle.category($0.id) + " " + MacOverviewStyle.money($0.amount) }.joined(separator: "、"))")
            }
        }
    }
}

/// Pointer movement updates only the chart, not ledger queries and all cards.
private struct MacOverviewTrendCard: View {
    let scope: MacOverviewScope
    let currency: String
    @Binding var trendMonths: Int
    let trend: [MacOverviewData.Month]
    let showRecords: (MacOverviewScope) -> Void
    @State private var hoveredMonth: MacOverviewData.Month?

    var body: some View {
        OverviewCard(help: "点击查看趋势期间的账目；类别和收支筛选同步生效", height: 250) {
            VStack(alignment: .leading, spacing: MacUI.space(16)) {
                HStack {
                    Text("收支趋势").appFont(.body, weight: .semibold, design: .default); Spacer()
                    MacSettingsMenu(selection: $trendMonths, options: [("近 6 个月", 6), ("近 12 个月", 12)]).frame(width: MacUI.space(130)).accessibilityIdentifier("overviewTrendRange")
                    Button { var records = scope; records.period = .custom; records.from = trend.first?.id ?? scope.reference; records.through = Calendar.current.dateInterval(of: .month, for: scope.reference)!.end.addingTimeInterval(-1); showRecords(records) } label: { Image(systemName: "arrow.up.right") }
                        .buttonStyle(MacInteractiveButtonStyle()).appHelp("查看趋势账目")
                }
                Chart(trend) { month in
                    BarMark(x: .value("月份", month.id, unit: .month), y: .value("金额", month.income))
                        .position(by: .value("类型", "收入")).foregroundStyle(by: .value("类型", "收入"))
                        .cornerRadius(3)
                    BarMark(x: .value("月份", month.id, unit: .month), y: .value("金额", month.expense))
                        .position(by: .value("类型", "支出")).foregroundStyle(by: .value("类型", "支出"))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale(["收入": MacOverviewStyle.income, "支出": MacOverviewStyle.expense])
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.defaultDigits), centered: true) } }
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
                            Text("收入  \(MacOverviewStyle.money(month.income)) \(currency)")
                            Text("支出  \(MacOverviewStyle.money(month.expense)) \(currency)")
                        }.appFont(.caption, weight: .regular, design: .default).monospacedDigit().appPadding(9)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                            .allowsHitTesting(false)
                    }
                }
                .appMinHeight(140).accessibilityIdentifier("overviewTrendChart")
                Text("至\(scope.reference.formatted(.dateTime.year().month().locale(Locale(identifier: "zh_Hans_CN")))) · 同类别筛选 · \(currency)").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
            }
        }
    }

}
