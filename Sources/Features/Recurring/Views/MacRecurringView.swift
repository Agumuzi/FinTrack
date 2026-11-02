import SwiftUI
import SwiftData

struct MacRecurringView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
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
                    else { ContentUnavailableView(L10n.text("mac.recurringView.ContentUnavailableView.ab961b3deb"), systemImage: "clock.arrow.circlepath", description: Text(L10n.text("mac.recurringView.ContentUnavailableView.e575b1bc66"))).frame(maxWidth: .infinity) }
                }
            }
            .sheet(isPresented: $showsDetails) {
                if !wide, let selected {
                    VStack(spacing: MacUI.space(0)) {
                        HStack { Text(L10n.text("mac.recurringView.GeometryReader.0af8be2738")).appFont(.section, weight: .semibold); Spacer(); Button(L10n.text("mac.recurringView.GeometryReader.3fd47edce4")) { showsDetails = false }.accessibilityIdentifier("recurringCloseDetails") }.appPadding(18)
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
                Text(L10n.text("mac.recurringView.filters.b5f15473fd")).appFont(.section, weight: .semibold); Spacer()
                Button { showsNew = true } label: { Image(systemName: "plus").frame(width: MacUI.space(24), height: MacUI.space(24)) }
                    .buttonStyle(MacInteractiveButtonStyle()).appHelp(L10n.text("mac.recurringView.filters.6462811026")).accessibilityLabel(L10n.text("mac.recurringView.filters.6462811026")).accessibilityIdentifier("financeAdd").disabled(bookCurrency == nil || posting)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: MacUI.space(7)) {
                    filter(L10n.text("mac.recurringView.filter.083c49cca2"), count: active.count, selected: type == nil, id: "recurringAll") { type = nil }
                    filter(L10n.text("mac.recurringView.filter.117d8f914d"), count: active.filter { $0.typedType == .income }.count, selected: type == .income, id: "recurringIncome") { type = .income }
                    filter(L10n.text("mac.recurringView.filter.e679096865"), count: active.filter { $0.typedType == .expense }.count, selected: type == .expense, id: "recurringExpense") { type = .expense }
                    Divider().appPadding(.vertical, 8)
                    Text(L10n.text("mac.recurringView.ScrollView.6320b4a872")).appFont(.caption, weight: .semibold).foregroundStyle(.secondary).appPadding(.leading, 8)
                    filter(L10n.text("mac.recurringView.filter.0a379c1e73"), selected: status == nil, id: "recurringStatusAll") { status = nil }
                    ForEach(MacRecurringData.Status.allCases) { item in
                        filter(L10n.builtIn(item.rawValue), count: active.filter { MacRecurringData.status($0) == item }.count, selected: status == item, id: "recurringStatus-\(item.rawValue)") { status = item }
                    }
                    Divider().appPadding(.vertical, 8)
                    Text(L10n.text("mac.recurringView.ScrollView.0d12cbd656")).appFont(.caption, weight: .semibold).foregroundStyle(.secondary).appPadding(.leading, 8)
                    filter(L10n.text("mac.recurringView.filter.33f222a369"), selected: category == nil, id: "recurringCategoryAll") { category = nil }
                    ForEach(Array(Set(active.map(\.category))).sorted(), id: \.self) { item in
                        filter(MacOverviewStyle.category(item), selected: category == item, id: "recurringCategory-\(item)") { category = item }
                    }
                    Divider().appPadding(.vertical, 8)
                    Text(L10n.text("mac.recurringView.ScrollView.1e878068f9")).appFont(.caption, weight: .semibold).foregroundStyle(.secondary).appPadding(.leading, 8)
                    filter(L10n.text("mac.recurringView.filter.efeb7909d4"), selected: currency == nil, id: "recurringCurrencyAll") { currency = nil }
                    ForEach(Array(Set(active.map(\.originalCurrency))).sorted(), id: \.self) { item in
                        filter(item, selected: currency == item, id: "recurringCurrency-\(item)") { currency = item }
                    }
                }
            }
            Button(L10n.text("mac.recurringView.filters.13a431e59b")) { search = ""; type = nil; status = nil; category = nil; currency = nil }.buttonStyle(MacInteractiveButtonStyle()).foregroundStyle(.secondary).accessibilityIdentifier("recurringReset")
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
                Text(L10n.format("mac.recurringView.list.eb0c9b5f2f", Int64(visible.count))).appFont(.section, weight: .semibold).accessibilityIdentifier("recurringCount"); Spacer()
                if !wide, selected != nil { Button { showsDetails = true } label: { Image(systemName: "sidebar.right") }.appHelp(L10n.text("mac.recurringView.list.a748cc074f")).accessibilityLabel(L10n.text("mac.recurringView.list.a748cc074f")).accessibilityIdentifier("recurringOpenDetails") }
            }
            TextField(L10n.text("mac.recurringView.list.0d6307bfa9"), text: $search).textFieldStyle(.roundedBorder).accessibilityIdentifier("recurringSearch")
            MacFinanceListToolbar(columns: $listColumns, sort: $sort, options: MacRecurringData.Sort.allCases.map { (L10n.builtIn($0.rawValue), $0) }, prefix: "recurring")
            if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red).accessibilityIdentifier("financeActionError") }
            if let message { Text(message).appFont(.caption, weight: .regular).foregroundStyle(MacOverviewStyle.income).accessibilityIdentifier("financeActionMessage") }
            if bookCurrency == nil { Text(L10n.text("mac.recurringView.list.33e3d7368a")).appFont(.caption, weight: .regular).foregroundStyle(.orange) }
            if visible.isEmpty {
                ContentUnavailableView(active.isEmpty ? L10n.text("mac.recurringView.ContentUnavailableView.d1b1391329") : L10n.text("mac.recurringView.ContentUnavailableView.ab9cb31a4b"), systemImage: "repeat", description: Text(active.isEmpty ? L10n.text("mac.recurringView.ContentUnavailableView.1cfa7e0419") : L10n.text("mac.recurringView.ContentUnavailableView.a66a4eba48")))
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
            HStack(alignment: .center, spacing: MacUI.space(10)) {
                Image(systemName: rule.typedType == .income ? "arrow.down.left" : "arrow.up.right").appFont(.section, weight: .semibold).foregroundStyle(color(rule))
                    .frame(width: MacUI.space(36), height: MacUI.space(36)).background(color(rule).opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: MacUI.space(4)) { Text(rule.title).appFont(.section, weight: .semibold).fixedSize(horizontal: false, vertical: true); Text("\(MacRecurringData.frequency(rule)) · \(MacOverviewStyle.category(rule.category))").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            HStack { Text(amount(rule)).appFont(.section, weight: .semibold, design: .default).monospacedDigit().foregroundStyle(color(rule)); Spacer(minLength: 0); badge(rule) }
            Text(L10n.format("mac.recurringView.row.9a34abc007", "\(MacDateDisplay.string(rule.nextExecutionDate))")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
        }.appPadding(14).frame(maxWidth: .infinity, alignment: .leading)
            .macFinanceSelectableRow(selected: selectedID == rule.id)
    }
    private func color(_ rule: RecurringTransaction) -> Color { rule.typedType == .income ? MacOverviewStyle.income : MacOverviewStyle.expense }
    private func badge(_ rule: RecurringTransaction) -> some View {
        let state = MacRecurringData.status(rule), color: Color = state == .active ? MacOverviewStyle.income : .secondary
        return Text(L10n.builtIn(state.rawValue)).appFont(.caption, weight: .regular).foregroundStyle(color).appPadding(.horizontal, 7).appPadding(.vertical, 4).background(color.opacity(0.1), in: Capsule())
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
                    Button(L10n.text("mac.recurringView.ScrollView.0518365699"), systemImage: "pencil") { editing = .recurring(rule) }.accessibilityIdentifier("recurringEdit").disabled(bookCurrency == nil || posting || linkedLoan)
                    if state != .ended {
                        Button(rule.isActive ? L10n.text("mac.recurringView.ScrollView.6a774fe98e") : L10n.text("mac.recurringView.ScrollView.61fbe05306")) { request(rule, action: rule.isActive ? .pause : .resume) }
                            .accessibilityIdentifier("recurringToggle").disabled(posting || linkedLoan || (!rule.isActive && !managed))
                    }
                    Menu { Button(L10n.text("mac.recurringView.Menu.cdb50f1982"), role: .destructive) { request(rule, action: .remove) }.accessibilityIdentifier("recurringRemove") }
                        label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: MacUI.space(30)).accessibilityIdentifier("recurringMore").disabled(posting || linkedLoan)
                    Spacer()
                }
                card {
                    Text(amount(rule)).appFont(.amount, weight: .semibold, design: .default).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).foregroundStyle(color(rule)).accessibilityIdentifier("recurringAmount").id("amount-\(rule.id)-\(rule.originalAmount)")
                    Text(L10n.format("mac.recurringView.card.8e0635a84c", "\(rule.typedType == .income ? L10n.text("mac.recurringView.card.117d8f914d") : L10n.text("mac.recurringView.card.e679096865"))")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    Divider()
                    HStack(alignment: .top) {
                        metric(L10n.text("mac.recurringView.metric.d12e204014"), MacRecurringData.frequency(rule)); Spacer()
                        metric(L10n.text("mac.recurringView.metric.895cd52fbb"), rule.endDate.map(MacDateDisplay.string) ?? L10n.text("mac.recurringView.metric.21e3ac90ce")); Spacer()
                        metric(L10n.text("mac.recurringView.metric.0d12cbd656"), MacOverviewStyle.category(rule.category))
                    }
                }
                card {
                    Text(L10n.text("mac.recurringView.card.f7a134f521")).appFont(.section, weight: .semibold)
                    Text(MacDateDisplay.string(rule.nextExecutionDate)).appFont(.section, weight: .semibold).accessibilityIdentifier("recurringNextDate").id("next-\(rule.id)-\(rule.nextExecutionDate)")
                    if linkedLoan {
                        Text(L10n.text("mac.recurringView.card.87237007b7")).appFont(.caption, weight: .regular).foregroundStyle(.orange)
                    } else if !managed {
                        Text(L10n.text("mac.recurringView.card.641c20a9db")).appFont(.caption, weight: .regular).foregroundStyle(.orange)
                        Button(L10n.text("mac.recurringView.card.cb1b6923d6")) { reviewing = .recurring(rule) }.accessibilityIdentifier("recurringReview").disabled(posting)
                    } else if state == .ended {
                        Text(L10n.text("mac.recurringView.card.e8e750b2ec")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    } else if !rule.isActive {
                        Text(L10n.text("mac.recurringView.card.7c2961ffd3")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    } else if let dates, !dates.isEmpty {
                        Text(L10n.format("mac.recurringView.card.68d2830477", Int64(dates.count))).appFont(.caption, weight: .regular).foregroundStyle(.orange).accessibilityIdentifier("recurringDueCount")
                        Button(L10n.text("mac.recurringView.card.d81a7a2933")) { request(rule, action: .post) }.accessibilityIdentifier("postRecurring").disabled(bookCurrency == nil || posting)
                    } else if dates == nil {
                        Text(L10n.text("mac.recurringView.card.54a9c89049")).appFont(.caption, weight: .regular).foregroundStyle(.orange)
                        Button(L10n.text("mac.recurringView.card.ab5a3aa9bf")) { reviewing = .recurring(rule) }.accessibilityIdentifier("recurringReview").disabled(posting)
                    } else {
                        Text(L10n.text("mac.recurringView.card.7c959fac2c")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    }
                    Button(L10n.text("mac.recurringView.card.aed5b2af52")) { schedule = rule }.accessibilityIdentifier("recurringSchedule")
                }
                card {
                    HStack { Text(L10n.text("mac.recurringView.card.9c1c4e34d1")).appFont(.section, weight: .semibold); Spacer(); Text(L10n.format("mac.recurringView.card.2dbaf05e6e", Int64(audit.receipts.count))).appFont(.caption, weight: .regular).foregroundStyle(.secondary).accessibilityIdentifier("recurringReceiptCount").id("receipts-\(rule.id)-\(audit.receipts.count)") }
                    if audit.unverifiedCount > 0 { Text(L10n.format("mac.recurringView.card.2317ee5a32", "\(audit.unverifiedCount)")).appFont(.caption, weight: .regular).foregroundStyle(.orange) }
                    if audit.receipts.isEmpty { Text(L10n.text("mac.recurringView.card.f5aacc593f")).appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                    ForEach(audit.receipts, id: \.id) { entry in
                        VStack(alignment: .leading, spacing: MacUI.space(5)) {
                            HStack { Text(MacDateDisplay.string(entry.date)); Spacer(); Text("\(entry.typedType == .income ? "+" : "−")\(MacOverviewStyle.money(entry.originalAmount)) \(entry.originalCurrency)").monospacedDigit() }.appFont(.caption, weight: .regular)
                            if entry.originalCurrency != entry.baseCurrencyCode { Text(L10n.format("mac.recurringView.ForEach.164567eb02", "\(MacOverviewStyle.money(entry.baseAmount))", "\(entry.baseCurrencyCode)", "\(entry.exchangeRateToBase.formatted())")).appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                        }.appPadding(.vertical, 5)
                    }
                    if let last = rule.lastExecutionDate { Text(L10n.format("mac.recurringView.card.e49185532d", "\(MacDateDisplay.string(last))")).appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                }
                if rule.originalCurrency != rule.baseCurrencyCode || !MacFinanceNotes.visible(rule.note).isEmpty {
                    card {
                        if rule.originalCurrency != rule.baseCurrencyCode {
                            HStack { Text(L10n.format("mac.recurringView.card.2ab0b4e818", "\(MacOverviewStyle.money(rule.baseAmount))", "\(rule.baseCurrencyCode)")).monospacedDigit().accessibilityIdentifier("recurringBookAmount"); Spacer(); Text(L10n.format("mac.recurringView.card.ced2e3b8ed", "\(rule.exchangeRateToBase.formatted())")).foregroundStyle(.secondary) }.appFont(.caption)
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
        case .pause: title = L10n.text("mac.recurringView.confirmationView.100b647162"); explanation = L10n.text("mac.recurringView.confirmationView.d8cfbf31a6")
        case .resume: title = L10n.text("mac.recurringView.confirmationView.35c402b78e"); explanation = L10n.text("mac.recurringView.confirmationView.5dcd4d297e")
        case .remove: title = L10n.text("mac.recurringView.confirmationView.094a494f85"); explanation = L10n.text("mac.recurringView.confirmationView.042aa4a319")
        case .post: title = L10n.text("mac.recurringView.confirmationView.10c732811e"); explanation = L10n.format("mac.recurringView.confirmationView.39d442f40e", Int64(item.dates.count))
        }
        return VStack(alignment: .leading, spacing: MacUI.space(18)) {
            Text(title).appFont(.dialogTitle, weight: .semibold); Text(item.rule.title).appFont(.section, weight: .semibold); Text(explanation)
            if item.action == .post {
                ScrollView { VStack(alignment: .leading, spacing: MacUI.space(6)) {
                    ForEach(item.dates, id: \.self) { date in Text("\(MacDateDisplay.string(date)) · \(amount(item.rule))").appFont(.caption, weight: .regular).monospacedDigit() }
                } }.frame(maxHeight: MacUI.space(200))
            }
            HStack { Spacer(); Button(L10n.text("mac.recurringView.confirmationView.2cd0f3be87")) { confirmation = nil }.accessibilityIdentifier("recurringCancelConfirmation")
                Button(item.action == .remove ? L10n.text("mac.recurringView.confirmationView.ee7dea070d") : L10n.text("mac.recurringView.confirmationView.36f33adaf0")) { apply(item); confirmation = nil }.accessibilityIdentifier("recurringConfirm")
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
                    saved(); message = L10n.format("mac.recurringView.Task.07c2f0d496", "\(count)")
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
    private func saved() { error = nil; message = L10n.text("mac.recurringView.saved.1bd91a7d0c"); now = Date(); Task { try? await MacNotifications.schedule(in: context) } }
}
