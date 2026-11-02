import SwiftUI
import SwiftData
import Charts

struct MacLoansView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @AppStorage(MacCustomTypography.bodyKey, store: MacPreferences.defaults) private var layoutBodyPoints = 16
    @AppStorage(MacCustomTypography.captionKey, store: MacPreferences.defaults) private var layoutCaptionPoints = 12
    @AppStorage("v2_font_tier", store: MacPreferences.defaults) private var layoutTier = "standard"
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
    @State private var calendarReview: LoanRule?
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
    private var automaticListWidth: Double { MacFinanceSplitSizing.minimumListWidth(columns: listColumns, bodySize: MacUI.fontTier.bodySize, titles: active.map(\.title)) }
    private var listWidth: Double {
        if let transientWidth { return transientWidth }
        let key = listColumns == 2 ? "v13_loans_double_list_width" : "v13_loans_single_list_width"
        let deltaKey = "v144_loans_list_delta_" + String(listColumns)
        if let delta = MacPreferences.defaults.object(forKey: deltaKey) as? NSNumber { return max(300, automaticListWidth + delta.doubleValue) }
        guard MacPreferences.defaults.object(forKey: key) != nil else { return automaticListWidth }
        let originalAutomatic = MacFinanceSplitSizing.minimumListWidth(columns: listColumns, bodySize: 16, titles: active.map(\.title))
        return max(300, (listColumns == 2 ? doubleListWidth : singleListWidth) + automaticListWidth - originalAutomatic)
    }
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
        let _ = layoutBodyPoints; let _ = layoutCaptionPoints
        GeometryReader { geometry in
            let filterWidth = MacUI.filterColumnWidth(available: geometry.size.width, wide: geometry.size.width >= MacUI.space(1000))
            let detailMinimum = MacFinanceSplitSizing.detailMinimum(bodySize: MacUI.fontTier.bodySize)
            let wide = geometry.size.width - filterWidth >= 300 + detailMinimum + 10
            let maximum = max(300, Double(geometry.size.width - filterWidth - detailMinimum - 10))
            HStack(spacing: MacUI.space(0)) {
                filters.frame(width: filterWidth)
                Divider()
                list(wide: wide).accessibilityElement(children:.contain).accessibilityIdentifier("loansListPane").frame(width: wide ? min(max(300, listWidth), maximum) : nil).frame(maxWidth: wide ? nil : .infinity, maxHeight: .infinity)
                if wide {
                    MacFinanceListDivider(width: widthBinding, maximum: maximum) { value in
                        if listColumns == 2 { doubleListWidth = value } else { singleListWidth = value }
                        MacPreferences.defaults.set(value - automaticListWidth, forKey: "v144_loans_list_delta_" + String(listColumns)); transientWidth = nil
                    }.accessibilityIdentifier("loansListDivider")
                    if let selected { presentedDetail(selected).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else { ContentUnavailableView(L10n.text("mac.loansView.ContentUnavailableView.7eda36d081"), systemImage: "banknote", description: Text(L10n.text("mac.loansView.ContentUnavailableView.2e74cc9e0c"))).frame(maxWidth: .infinity) }
                }
            }
            .sheet(isPresented: $showsDetails) {
                if !wide, let selected {
                    VStack(spacing: MacUI.space(0)) {
                        HStack { Text(L10n.text("mac.loansView.GeometryReader.99e555ac78")).appFont(.section, weight: .semibold); Spacer(); Button(L10n.text("mac.loansView.GeometryReader.3fd47edce4")) { showsDetails = false }.accessibilityIdentifier("loansCloseDetails") }.appPadding(18)
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
                Text(L10n.text("mac.loansView.filters.b5f15473fd")).appFont(.section, weight: .semibold); Spacer()
                Button { showsNew = true } label: { Image(systemName: "plus").frame(width: MacUI.space(24), height: MacUI.space(24)) }
                    .buttonStyle(MacInteractiveButtonStyle()).appHelp(L10n.text("mac.loansView.filters.49607c540f")).accessibilityLabel(L10n.text("mac.loansView.filters.49607c540f")).accessibilityIdentifier("financeAdd").disabled(bookCurrency == nil)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: MacUI.space(7)) {
                    filter(L10n.text("mac.loansView.filter.24255887b6"), count: active.count, selected: status == nil, id: "loansAll") { status = nil }
                    ForEach(MacLoansData.Status.allCases) { item in
                        filter(L10n.builtIn(item.rawValue), count: active.filter { MacLoansData.matches(audits[$0.id].map { MacLoansData.status($0, now: now) } ?? .review, filter: item) }.count,
                               selected: status == item, id: "loansStatus-\(item.rawValue)") { status = item }
                    }
                    Divider().appPadding(.vertical, 8)
                    Text(L10n.text("mac.loansView.ScrollView.c6318d87d7")).appFont(.caption, weight: .semibold).foregroundStyle(.secondary).appPadding(.leading, 8)
                    filter(L10n.text("mac.loansView.filter.33f222a369"), selected: category == nil, id: "loansCategoryAll") { category = nil }
                    ForEach(Array(Set(active.map(\.category))).sorted(), id: \.self) { item in
                        filter(MacOverviewStyle.category(item), selected: category == item, id: "loansCategory-\(item)") { category = item }
                    }
                    Divider().appPadding(.vertical, 8)
                    Text(L10n.text("mac.loansView.ScrollView.1e878068f9")).appFont(.caption, weight: .semibold).foregroundStyle(.secondary).appPadding(.leading, 8)
                    filter(L10n.text("mac.loansView.filter.efeb7909d4"), selected: currency == nil, id: "loansCurrencyAll") { currency = nil }
                    ForEach(Array(Set(active.map(\.currency))).sorted(), id: \.self) { item in
                        filter(item, selected: currency == item, id: "loansCurrency-\(item)") { currency = item }
                    }
                }
            }
            Button(L10n.text("mac.loansView.filters.13a431e59b")) { search = ""; status = nil; category = nil; currency = nil }.buttonStyle(MacInteractiveButtonStyle()).foregroundStyle(.secondary).accessibilityIdentifier("loansReset")
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
                Text(L10n.format("mac.loansView.list.2cdad5492c", Int64(visible.count))).appFont(.section, weight: .semibold).accessibilityIdentifier("loansCount"); Spacer()
                if !wide, selected != nil { Button { showsDetails = true } label: { Image(systemName: "sidebar.right") }.appHelp(L10n.text("mac.loansView.list.a748cc074f")).accessibilityLabel(L10n.text("mac.loansView.list.a748cc074f")).accessibilityIdentifier("loansOpenDetails") }
            }
            TextField(L10n.text("mac.loansView.list.dc982a65e3"), text: $search).textFieldStyle(.roundedBorder).accessibilityIdentifier("loansSearch")
            MacFinanceListToolbar(columns: $listColumns, sort: $sort, options: MacLoansData.Sort.allCases.map { (L10n.builtIn($0.rawValue), $0) }, prefix: "loans")
            if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red).accessibilityIdentifier("financeActionError") }
            if let message { Text(message).appFont(.caption, weight: .regular).foregroundStyle(MacOverviewStyle.income).accessibilityIdentifier("financeActionMessage") }
            if bookCurrency == nil { Text(L10n.text("mac.loansView.list.171b2e5d90")).appFont(.caption, weight: .regular).foregroundStyle(.orange) }
            if visible.isEmpty {
                ContentUnavailableView(active.isEmpty ? L10n.text("mac.loansView.ContentUnavailableView.8a92076644") : L10n.text("mac.loansView.ContentUnavailableView.5f0ae1575f"), systemImage: "banknote", description: Text(active.isEmpty ? L10n.text("mac.loansView.ContentUnavailableView.be0f1d686b") : L10n.text("mac.loansView.ContentUnavailableView.a66a4eba48")))
                    .accessibilityIdentifier("loansEmptyState").frame(maxHeight: .infinity)
            } else {
                ScrollView { LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: listColumns == 2 ? 2 : 1), spacing: 10) {
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
            HStack(alignment: .center, spacing: MacUI.space(10)) {
                Image(systemName: "banknote").appFont(.section, weight: .semibold).foregroundStyle(MacOverviewStyle.accent)
                    .frame(width: MacUI.space(36), height: MacUI.space(36)).background(MacOverviewStyle.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: MacUI.space(4)) { Text(loan.title).appFont(.section, weight: .semibold).fixedSize(horizontal: false, vertical: true); Text("\(MacOverviewStyle.category(loan.category)) · \(MacLoansData.method(loan.method))").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            HStack { Text(money(loan.principal, loan)).appFont(.section, weight: .semibold, design: .default).monospacedDigit(); Spacer(minLength: 0) }
            HStack { Text(L10n.text("mac.loansView.row.39d617d186")).appFont(.caption, weight: .regular).foregroundStyle(.secondary); Spacer(); badge(audit) }
            if let outstanding = audit.outstanding {
                Text(L10n.format("mac.loansView.row.bab4ce5e81", "\(money(outstanding, loan))")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                ProgressView(value: Double(audit.paid.count), total: Double(max(1, payments.filter { $0.total > 0 }.count))).appHelp(L10n.text("mac.loansView.row.85368c6bdd"))
                Text(L10n.format("mac.loansView.row.06999bdbf3", Int64(audit.paid.count), "\(payments.filter { $0.total > 0 }.count)") + (payments.contains { $0.total == 0 } ? L10n.text("mac.loansView.row.02a5bc1df0") : L10n.format("mac.loansView.row.7a00f5e7b7", "\(loan.termMonths - audit.paid.count)"))).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            } else { Text(L10n.text("mac.loansView.row.d586b563cc")).appFont(.caption, weight: .regular).foregroundStyle(.orange) }
            if let end = loan.amortizationSchedule.last?.date { Text(L10n.format("mac.loansView.row.eb90f96d4e", "\(MacDateDisplay.string(end))")).appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
        }.appPadding(14).frame(maxWidth: .infinity, alignment: .leading)
            .macFinanceSelectableRow(selected: selectedID == loan.id)
    }
    private func badge(_ audit: MacLoansData.Audit) -> some View {
        let state = MacLoansData.status(audit, now: now)
        let color: Color = state == .settled ? MacOverviewStyle.income : (state == .review || state == .overdue ? .orange : MacOverviewStyle.accent)
        return Text(L10n.builtIn(state.rawValue)).appFont(.caption, weight: .regular).foregroundStyle(color).appPadding(.horizontal, 7).appPadding(.vertical, 4).background(color.opacity(0.1), in: Capsule())
    }
    private func presentedDetail(_ loan: LoanRule) -> some View {
        detail(loan)
            .sheet(item: $editing) { item in if let bookCurrency { MacFinanceEditor(panel: .loans, currency: bookCurrency, existing: item) { saved() } } }
            .sheet(item: $reviewing) { MacFinanceReviewView(record: $0) }
            .sheet(item: $schedule) { item in MacLoansScheduleView(loan: item, audit: MacLoansData.audit(item, transactions: transactions, rules: rules)) }
            .sheet(item: $legacy) { legacyReport($0) }
            .sheet(item: $receipt) { receiptDetail($0) }
            .sheet(item: $calendarReview) { MacLoanCalendarReviewView(loan: $0) }
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
                    Button(L10n.text("mac.loansView.ScrollView.0518365699"), systemImage: "pencil") { editing = .loan(loan) }.accessibilityIdentifier("loansEdit").disabled(bookCurrency == nil)
                    Button(L10n.text("mac.loansView.ScrollView.a822061dd5"), systemImage: "calendar") { schedule = loan }.accessibilityIdentifier("loansSchedule")
                    Menu { Button(L10n.text("mac.loansView.Menu.ffcfd840ff"), role: .destructive) { removal = loan }.accessibilityIdentifier("loansRemove") }
                        label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: MacUI.space(30)).accessibilityIdentifier("loansMore")
                    Spacer()
                }
                card {
                    Text(money(loan.principal, loan)).appFont(.amount, weight: .semibold, design: .default).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).accessibilityIdentifier("loansPrincipal").id("principal-\(loan.id)-\(loan.principal)")
                    Text(L10n.format("mac.loansView.card.ee0f24ac23", "\(MacOverviewStyle.category(loan.category))")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    Divider()
                    ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) {
                        metric(L10n.text("mac.loansView.metric.7f32635153"), "\(loan.annualRate.formatted())%"); Spacer()
                        metric(L10n.text("mac.loansView.metric.b6207e5e1f"), MacLoansData.method(loan.method)); Spacer()
                        metric(L10n.text("mac.loansView.metric.4535099b43"), L10n.format("mac.loansView.metric.0a4242f4ed", "\(loan.termMonths)"))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        metric(L10n.text("mac.loansView.metric.7f32635153"), "\(loan.annualRate.formatted())%")
                        metric(L10n.text("mac.loansView.metric.b6207e5e1f"), MacLoansData.method(loan.method))
                        metric(L10n.text("mac.loansView.metric.4535099b43"), L10n.format("mac.loansView.metric.0a4242f4ed", "\(loan.termMonths)"))
                    }
                    }
                    Text(L10n.format("mac.loansView.card.ce645a7ff3", "\(MacDateDisplay.string(loan.startDate))", "\(payments.last.map { MacDateDisplay.string($0.date) } ?? L10n.text("mac.loansView.card.33df16b4af"))")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    if loan.downPaymentAmount > 0 { Text(L10n.format("mac.loansView.card.744c2044da", "\(money(loan.totalAmount, loan))", "\(money(loan.downPaymentAmount, loan))")).appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                }
                card {
                    Text(L10n.text("mac.loansView.card.363b02c05c")).appFont(.section, weight: .semibold)
                    if let outstanding = audit.outstanding {
                        Text(L10n.format("mac.loansView.card.bab4ce5e81", "\(money(outstanding, loan))")).appFont(.section, weight: .semibold).monospacedDigit().accessibilityIdentifier("loansOutstanding").id("remaining-\(loan.id)-\(outstanding)")
                        ProgressView(value: Double(audit.paid.count), total: Double(max(1, payments.filter { $0.total > 0 }.count)))
                        Text(L10n.format("mac.loansView.card.06999bdbf3", Int64(audit.paid.count), "\(payments.filter { $0.total > 0 }.count)") + (payments.contains { $0.total == 0 } ? L10n.text("mac.loansView.card.02a5bc1df0") : L10n.format("mac.loansView.card.7a00f5e7b7", "\(loan.termMonths - audit.paid.count)"))).appFont(.caption, weight: .regular).accessibilityIdentifier("loansProgress").id("progress-\(loan.id)-\(audit.paid.count)")
                        HStack { metric(L10n.text("mac.loansView.metric.d734015949"), money(audit.principalPaid ?? 0, loan)); Spacer(); metric(L10n.text("mac.loansView.metric.747af361f6"), money(audit.interestPaid ?? 0, loan)) }
                        if let warning = audit.warning { Text(warning).appFont(.caption).foregroundStyle(.orange) }
                        else { Text(L10n.text("mac.loansView.card.7e45a7607f")).appFont(.caption).foregroundStyle(.secondary) }
                    } else {
                        Text(L10n.text("mac.loansView.card.e3e603defb")).appFont(.section, weight: .semibold).accessibilityIdentifier("loansUnverified")
                        Text(audit.warning ?? L10n.text("mac.loansView.card.13fc26b84e")).appFont(.caption, weight: .regular).foregroundStyle(.orange)
                    }
                }
                nextCard(loan, audit: audit)
                if MacLoanSchedule.requiresReview(loan) {
                    Button(L10n.text("mac.loansView.ScrollView.13c7fb1c12")) { calendarReview = loan }
                        .accessibilityIdentifier("loansCalendarReview").disabled(bookCurrency == nil)
                }
                card {
                    HStack { Text(L10n.text("mac.loansView.card.fb0212c63f")).appFont(.section, weight: .semibold); Spacer(); Text(loan.currency).appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                    Text(audit.reliable ? L10n.text("mac.loansView.card.619cd33ee8") : L10n.text("mac.loansView.card.fb995f4709")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    composition(loan, audit: audit)
                    HStack { metric(L10n.text("mac.loansView.metric.16b0bbaaea"), money(LoanAmortizationEngine.totalInterest(schedule: payments), loan)); Spacer(); metric(L10n.text("mac.loansView.metric.89b3d54bf1"), money(LoanAmortizationEngine.totalRepayment(schedule: payments), loan)) }
                }
                card {
                    HStack { Text(L10n.text("mac.loansView.card.1880484eb2")).appFont(.section, weight: .semibold); Spacer(); Text(audit.reliable ? L10n.format("mac.loansView.card.2dbaf05e6e", Int64(audit.receipts.count)) : L10n.text("mac.loansView.card.33df16b4af")).appFont(.caption, weight: .regular).foregroundStyle(.secondary).accessibilityIdentifier("loansReceiptCount").id("receipts-\(loan.id)-\(audit.receipts.count)-\(audit.reliable)") }
                    if audit.receipts.isEmpty { Text(audit.reliable ? L10n.text("mac.loansView.card.ac29a41255") : L10n.text("mac.loansView.card.719db08237")).appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                    ForEach(audit.receipts, id: \.id) { entry in
                        Button { receipt = entry } label: {
                            HStack { Text(MacDateDisplay.string(entry.date)); Spacer(); Text("−\(MacOverviewStyle.money(entry.originalAmount)) \(entry.originalCurrency)").monospacedDigit(); Image(systemName: "chevron.right").appFont(.caption, weight: .regular) }.appFont(.caption, weight: .regular).appPadding(.vertical, 7).contentShape(Rectangle())
                        }.buttonStyle(MacInteractiveButtonStyle()).appHelp(L10n.text("mac.loansView.ForEach.e471176ad9")).accessibilityIdentifier("loansReceipt-\(entry.id)")
                    }
                }
                if loan.currency != loan.baseCurrencyCode {
                    card {
                        HStack { Text(L10n.format("mac.loansView.card.20001fb1ea", "\(MacOverviewStyle.money(loan.basePrincipal))", "\(loan.baseCurrencyCode)")).monospacedDigit(); Spacer(); Text(L10n.format("mac.loansView.card.ced2e3b8ed", "\(loan.exchangeRateToBase.formatted())")).foregroundStyle(.secondary) }.appFont(.caption)
                        Text(L10n.text("mac.loansView.card.fef2ecebd7")).appFont(.caption).foregroundStyle(.secondary)
                    }
                }
                if !MacFinanceNotes.visible(loan.note).isEmpty { card { Text(L10n.text("mac.loansView.card.daede98817")).appFont(.section, weight: .semibold); Text(MacFinanceNotes.visible(loan.note)).textSelection(.enabled) } }
            }.appPadding(20)
        }.accessibilityIdentifier("loansDetailScroll").id(loan.id)
    }
    private func nextCard(_ loan: LoanRule, audit: MacLoansData.Audit) -> some View {
        card {
            Text(L10n.text("mac.loansView.card.130fd4a9ff")).appFont(.section, weight: .semibold)
            if let next = audit.next {
                Text(L10n.format("mac.loansView.card.95a75dd293", "\(next.index)", "\(loan.termMonths)", "\(MacDateDisplay.string(next.date))")).appFont(.body, weight: .medium).accessibilityIdentifier("loansNext")
                Text(money(next.total, loan)).appFont(.dialogTitle, weight: .semibold).monospacedDigit()
                Text(L10n.format("mac.loansView.card.140c0cc7d1", "\(money(next.principal, loan))", "\(money(next.interest, loan))")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                if Calendar.current.startOfDay(for: next.date) <= Calendar.current.startOfDay(for: now) {
                    Button(L10n.text("mac.loansView.card.2ad1a7b7f0")) { prepare(loan) }.accessibilityIdentifier("loansRecordPayment").disabled(bookCurrency == nil)
                    Text(L10n.text("mac.loansView.card.d107bd0ce1")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                } else { Text(L10n.text("mac.loansView.card.7c959fac2c")).appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
            } else if audit.reliable { Text(audit.warning == nil ? L10n.text("mac.loansView.card.20dfee721b") : L10n.text("mac.loansView.card.cbfbd3d312")).appFont(.body, weight: .regular).foregroundStyle(MacOverviewStyle.income) }
            else {
                Text(audit.warning ?? L10n.text("mac.loansView.card.9671f590c4")).appFont(.caption, weight: .regular).foregroundStyle(.orange)
                if !MacLoanRepayment.isManaged(loan) || rules.contains(where: { ($0.projectIdentifier ?? "").hasPrefix("loan_generated:\(loan.id.uuidString):") }) {
                    Button(L10n.text("mac.loansView.card.9a7456d274")) { do { legacy = try MacLegacyLoanAudit.inspect(loan, in: context) } catch { self.error = MacLocalization.error(error) } }.accessibilityIdentifier("loansLegacyAudit")
                    Button(L10n.text("mac.loansView.card.56fb0c7308")) { reviewing = .loan(loan) }.accessibilityIdentifier("loansReview").disabled(bookCurrency == nil)
                    Text(L10n.text("mac.loansView.card.6dd7dfc3af")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func composition(_ loan: LoanRule, audit: MacLoansData.Audit) -> some View {
        let payments = Array((audit.schedule.isEmpty ? loan.amortizationSchedule : audit.schedule).filter { !audit.reliable || !audit.paid.contains($0.index) }.prefix(12))
        return Group {
            if payments.isEmpty { Text(L10n.text("mac.loansView.composition.a1ff8d772f")).appFont(.caption, weight: .regular).foregroundStyle(.secondary).appMinHeight(100) }
            else {
                Chart(payments, id: \.index) { item in
                    BarMark(x: .value(L10n.text("mac.loansView.BarMark.4a703a03f5"), String(item.index)), y: .value(L10n.text("mac.loansView.BarMark.ffc624300d"), item.principal)).foregroundStyle(by: .value(L10n.text("mac.loansView.Chart.fb7c65e8ec"), L10n.text("mac.loansView.Chart.2fa66a53e4")))
                        .accessibilityLabel(L10n.format("mac.loansView.Chart.5b01e0ad32", "\(item.index)")).accessibilityValue("\(MacOverviewStyle.money(item.principal)) \(loan.currency)")
                    BarMark(x: .value(L10n.text("mac.loansView.BarMark.4a703a03f5"), String(item.index)), y: .value(L10n.text("mac.loansView.BarMark.ffc624300d"), item.interest)).foregroundStyle(by: .value(L10n.text("mac.loansView.Chart.fb7c65e8ec"), L10n.text("mac.loansView.Chart.3dd1b22caa")))
                        .accessibilityLabel(L10n.format("mac.loansView.Chart.e474da5d01", "\(item.index)")).accessibilityValue("\(MacOverviewStyle.money(item.interest)) \(loan.currency)")
                }.chartForegroundStyleScale(["本金": MacOverviewStyle.accent, "利息": MacOverviewStyle.accent.opacity(0.32)])
                    .chartXAxisLabel(L10n.text("mac.loansView.composition.4a703a03f5")).frame(height: MacUI.space(160)).accessibilityIdentifier("loansCompositionChart")
                    .appHelp(L10n.text("mac.loansView.composition.2cab0d95e9"))
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
            Text(L10n.text("mac.loansView.paymentConfirmation.33d336873e")).appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("confirmLoanPaymentTitle")
            Text(item.loan.title).appFont(.section, weight: .semibold)
            Text(L10n.format("mac.loansView.paymentConfirmation.95a75dd293", "\(p.index)", "\(item.preview.totalCount)", "\(MacDateDisplay.string(p.date))"))
            Text(L10n.format("mac.loansView.paymentConfirmation.e7ebee26c2", "\(MacOverviewStyle.money(p.principal))", "\(MacOverviewStyle.money(p.interest))", "\(MacOverviewStyle.money(p.total))", "\(item.source)")).accessibilityIdentifier("loanExpectedPayment")
            if item.source != item.book {
                TextField(L10n.format("mac.loansView.paymentConfirmation.2247d566a7", "\(item.source)", "\(item.book)"), text: $paymentRate).accessibilityIdentifier("loanPaymentExchangeRate")
                Button(L10n.text("mac.loansView.paymentConfirmation.a22ab06f1d")) {
                    loadingRate = true
                    Task { @MainActor in
                        defer { loadingRate = false }
                        do {
                            let rate = try await MacExchangeRates.shared.quote(from: item.source, to: item.book, on: p.date)
                            if confirmation?.id == item.id { paymentRate = String(rate) }
                        } catch { self.error = MacLocalization.error(error) }
                    }
                }.disabled(loadingRate)
                Text(L10n.format("mac.loansView.paymentConfirmation.7d5d537c22", "\(item.book)")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            }
            if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red) }
            Text(L10n.text("mac.loansView.paymentConfirmation.4c0d963c66"))
            HStack { Spacer(); Button(L10n.text("mac.loansView.paymentConfirmation.2cd0f3be87")) { confirmation = nil }.accessibilityIdentifier("loansCancelPayment").disabled(loadingRate)
                Button(L10n.text("mac.loansView.paymentConfirmation.5197d81918")) {
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
            Text(L10n.text("mac.loansView.removalConfirmation.eb58d33b44")).appFont(.dialogTitle, weight: .semibold); Text(loan.title).appFont(.section, weight: .semibold)
            Text(L10n.text("mac.loansView.removalConfirmation.db53f1f24b"))
            HStack { Spacer(); Button(L10n.text("mac.loansView.removalConfirmation.2cd0f3be87")) { removal = nil }.accessibilityIdentifier("loansCancelRemoval")
                Button(L10n.text("mac.loansView.removalConfirmation.ee7dea070d"), role: .destructive) { do { try MacFinanceEditing.retire(.loan(loan), in: context); saved(); removal = nil } catch { self.error = MacLocalization.error(error) } }.accessibilityIdentifier("loansConfirmRemoval")
            }
        }.appPadding(24).appDialog(width: 500)
    }
    private func legacyReport(_ report: MacLegacyLoanAudit.Report) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(16)) {
            Text(L10n.text("mac.loansView.legacyReport.802eebeaaa")).appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("legacyLoanAuditTitle")
            Text(report.loanTitle).appFont(.section, weight: .semibold)
            Text(L10n.format("mac.loansView.legacyReport.e62b5ea691", "\(report.linkedRuleCount)", "\(report.orphanRuleCount)", "\(report.missingPeriodCount)", "\(report.duplicatePeriodCount)", "\(report.malformedRuleCount)")).accessibilityIdentifier("legacyLoanAuditSummary")
            Text(L10n.text("mac.loansView.legacyReport.09fd0c9daf")).appFont(.body, weight: .regular).foregroundStyle(.orange).accessibilityIdentifier("legacyLoanAuditUnverified")
            ScrollView { VStack(alignment: .leading, spacing: MacUI.space(10)) { ForEach(report.installments) { row in
                Text(L10n.format("mac.loansView.ForEach.bd370cf734", "\(row.index)", "\(MacDateDisplay.string(row.dueDate))", "\(MacOverviewStyle.money(row.scheduledAmount))", "\(report.currency)", "\(row.linkedRuleCount)", "\(row.possibleCashExpenseCount)")).appFont(.caption, weight: .regular)
            } } }.frame(maxHeight: MacUI.space(280))
            HStack { Spacer(); Button(L10n.text("mac.loansView.legacyReport.3fd47edce4")) { legacy = nil }.accessibilityIdentifier("closeLegacyLoanAudit") }
        }.appPadding(24).appDialog(width: 650)
    }
    private func receiptDetail(_ entry: Transaction) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(16)) {
            Text(L10n.text("mac.loansView.receiptDetail.f94b3a252d")).appFont(.dialogTitle, weight: .semibold)
            Text(MacDateDisplay.string(entry.date))
            Text(L10n.format("mac.loansView.receiptDetail.fe04c48668", "\(MacOverviewStyle.money(entry.originalAmount))", "\(entry.originalCurrency)")).appFont(.section, weight: .semibold)
            Text(L10n.format("mac.loansView.receiptDetail.2ab0b4e818", "\(MacOverviewStyle.money(entry.baseAmount))", "\(entry.baseCurrencyCode)")).accessibilityIdentifier("loansReceiptBookAmount")
            Text(L10n.format("mac.loansView.receiptDetail.39ee388707", "\(entry.exchangeRateToBase.formatted())", "\(MacOverviewStyle.category(entry.category))"))
            Text(L10n.text("mac.loansView.receiptDetail.7836f2ce50")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            Text((entry.note ?? "").components(separatedBy: " [FTLoan:").first!.replacingOccurrences(of: "Loan installment ", with: "还款期次 ").replacingOccurrences(of: "Principal:", with: "本金：").replacingOccurrences(of: "Interest:", with: "利息：")).appFont(.caption, weight: .regular).textSelection(.enabled)
            HStack { Spacer(); Button(L10n.text("mac.loansView.receiptDetail.3fd47edce4")) { receipt = nil }.accessibilityIdentifier("loansCloseReceipt") }
        }.appPadding(24).appDialog(width: 560)
    }
    private func saved() { error = nil; message = L10n.text("mac.loansView.saved.1bd91a7d0c"); now = Date(); Task { try? await MacNotifications.schedule(in: context) } }
}

struct MacLoansScheduleView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
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
            Text(L10n.format("mac.loansView.body.273d190395", "\(loan.currency)", "\(MacLoansData.method(loan.method))")).appFont(.section, weight: .semibold)
            Text(L10n.text("mac.loansView.body.9f86e21af5")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            Table((audit.schedule.isEmpty ? loan.amortizationSchedule : audit.schedule).map { Row(payment: $0) }) {
                TableColumn(L10n.text("mac.loansView.TableColumn.4a703a03f5")) { Text(String($0.payment.index)) }.width(MacUI.space(40))
                TableColumn(L10n.text("mac.loansView.TableColumn.70d0c1b336")) { Text(MacDateDisplay.string($0.payment.date)) }.width(MacUI.space(100))
                TableColumn(L10n.text("mac.loansView.TableColumn.2fa66a53e4")) { Text(MacOverviewStyle.money($0.payment.principal)) }
                TableColumn(L10n.text("mac.loansView.TableColumn.3dd1b22caa")) { Text(MacOverviewStyle.money($0.payment.interest)) }
                TableColumn(L10n.text("mac.loansView.TableColumn.e009c148d1")) { Text(MacOverviewStyle.money($0.payment.total)) }
                TableColumn(L10n.text("mac.loansView.TableColumn.53b66f302d")) { Text(MacOverviewStyle.money($0.payment.remainingBalance)) }
                TableColumn(L10n.text("mac.loansView.TableColumn.01331db944")) { row in Text(!audit.reliable ? L10n.text("mac.loansView.TableColumn.33df16b4af") : (audit.paid.contains(row.id) ? L10n.text("mac.loansView.TableColumn.47f6879949") : row.payment.total == 0 ? L10n.text("mac.loansView.TableColumn.ef9b374f5b") : L10n.text("mac.loansView.TableColumn.c2fa39d9dd"))) }
            }.frame(height: MacUI.space(380)).accessibilityIdentifier("loanScheduleTable")
            HStack { Spacer(); Button(L10n.text("mac.loansView.body.3fd47edce4")) { dismiss() }.accessibilityIdentifier("loansCloseSchedule") }
        }.appPadding(24).appDialog(width: 850)
    }
}
