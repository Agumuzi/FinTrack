import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct MacDepositsView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @AppStorage(MacCustomTypography.bodyKey, store: MacPreferences.defaults) private var layoutBodyPoints = 16
    @AppStorage(MacCustomTypography.captionKey, store: MacPreferences.defaults) private var layoutCaptionPoints = 12
    @AppStorage("v2_font_tier", store: MacPreferences.defaults) private var layoutTier = "standard"
    let bookCurrency: String?
    @Environment(\.modelContext) private var context
    @Query private var profiles: [FinancialProfile]
    @State private var returningPrincipal = false
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
    @State private var noteExpanded = false
    @State private var cropInput: MacBankLogos.CropInput?
    @State private var now = Date()
    @AppStorage("v13_deposit_double_list_width", store: MacPreferences.defaults) private var doubleListWidth = 580.0
    @State private var transientWidth: Double?
    private var automaticListWidth: Double { MacFinanceSplitSizing.minimumListWidth(columns: listColumns, bodySize: MacUI.fontTier.bodySize, titles: active.map(\.bankName)) }
    private var listWidth: Double {
        if let transientWidth { return transientWidth }
        let key = listColumns == 2 ? "v13_deposit_double_list_width" : "v13_deposit_single_list_width"
        let deltaKey = "v144_deposit_list_delta_" + String(listColumns)
        if let delta = MacPreferences.defaults.object(forKey: deltaKey) as? NSNumber { return max(300, automaticListWidth + delta.doubleValue) }
        guard MacPreferences.defaults.object(forKey: key) != nil else { return automaticListWidth }
        let originalAutomatic = MacFinanceSplitSizing.minimumListWidth(columns: listColumns, bodySize: 16, titles: active.map(\.bankName))
        return max(300, (listColumns == 2 ? doubleListWidth : singleListWidth) + automaticListWidth - originalAutomatic)
    }
    private var widthBinding: Binding<Double> { Binding(get: { listWidth }, set: { transientWidth = $0 }) }
    private var active: [DepositRecord] { deposits.filter { $0.deletedAt == nil } }
    private var visible: [DepositRecord] {
        MacDepositsData.filtered(active, search: search, status: status, bank: bank, currency: currency, sort: sort, now: now)
    }
    private var selected: DepositRecord? { visible.first { $0.id == selectedID } }
    private var banks: [String] { Array(Set(active.map(\.bankName))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    private var currencies: [String] { Array(Set(active.map(\.originalCurrency))).sorted() }

    var body: some View {
        let _ = layoutBodyPoints; let _ = layoutCaptionPoints
        GeometryReader { geometry in
            let filterWidth = MacUI.filterColumnWidth(available: geometry.size.width, wide: geometry.size.width >= MacUI.space(950))
            let detailMinimum = MacFinanceSplitSizing.detailMinimum(bodySize: MacUI.fontTier.bodySize)
            let wide = geometry.size.width - filterWidth >= 300 + detailMinimum + 10
            HStack(spacing: MacUI.space(0)) {
                filters.frame(width: filterWidth)
                Divider()
                VStack(spacing: 0) {
                  MacDepositEarningsOverview(deposits: deposits, transactions: transactions, now: now,
                    availableWidth: max(1, geometry.size.width - filterWidth), availableHeight: geometry.size.height)
                  Divider()
                  HStack(spacing: 0) {
                let maximum = max(300, Double(geometry.size.width - filterWidth - detailMinimum - 10))
                list(wide: wide).accessibilityElement(children:.contain).accessibilityIdentifier("depositListPane").frame(width: wide ? min(max(300, listWidth), maximum) : nil).frame(maxWidth: wide ? nil : .infinity, maxHeight: .infinity)
                if wide {
                    MacFinanceListDivider(width: widthBinding, maximum: maximum) { value in
                        if listColumns == 2 { doubleListWidth = value } else { singleListWidth = value }
                        MacPreferences.defaults.set(value - automaticListWidth, forKey: "v144_deposit_list_delta_" + String(listColumns)); transientWidth = nil
                    }.accessibilityIdentifier("depositListDivider")
                    if let selected { presentedDetail(selected, compact: false).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else { ContentUnavailableView(L10n.text("mac.depositsView.ContentUnavailableView.f3fbbd9235"), systemImage: "building.columns", description: Text(L10n.text("mac.depositsView.ContentUnavailableView.ad48c73fe1"))).frame(maxWidth: .infinity) }
                }
                  }
                }
            }
            .sheet(isPresented: $showsDetails) {
                if !wide, let selected {
                    VStack(spacing: MacUI.space(0)) {
                        HStack { Text(L10n.text("mac.depositsView.GeometryReader.a0200aec72")).appFont(.section, weight: .semibold); Spacer(); Button(L10n.text("mac.depositsView.GeometryReader.3fd47edce4")) { showsDetails = false }.accessibilityIdentifier("depositCloseDetails") }.appPadding(18)
                        Divider(); presentedDetail(selected, compact: true)
                    }.appPanel(width: 560, height: 670)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button { showsNew = true } label: { Image(systemName: "plus").appIconFont(22, weight: .semibold).foregroundStyle(MacAccent.primaryForeground).frame(width: 46, height: 46).background(MacUI.accent, in: Circle()).contentShape(Circle()) }
                .buttonStyle(MacInteractiveButtonStyle()).appHelp(L10n.text("mac.depositsView.body.1725e50aba")).accessibilityLabel(L10n.text("mac.depositsView.body.1725e50aba")).accessibilityIdentifier("depositQuickAdd").disabled(bookCurrency == nil || posting).padding(22)
        }
        .onAppear { selectedID = visible.first?.id }
        .onChange(of:selectedID) {_,_ in noteExpanded=false}
        .onChange(of: listColumns) { _, _ in transientWidth = nil }
        .onChange(of: visible.map(\.id)) { _, ids in
            if !ids.contains(selectedID ?? UUID()) { selectedID = ids.first; showsDetails = false }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = Date() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in now = Date() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in now = Date() }
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
                Text(L10n.text("mac.depositsView.presentedDetail.f60a883aa1")).appFont(.dialogTitle, weight: .semibold)
                Text(deposit.bankName)
                Text(L10n.text("mac.depositsView.presentedDetail.09d949c9cc"))
                HStack { Spacer(); Button(L10n.text("mac.depositsView.presentedDetail.2cd0f3be87")) { removing = nil }.accessibilityIdentifier("depositCancelRemove")
                    Button(L10n.text("mac.depositsView.presentedDetail.ee7dea070d"), role: .destructive) {
                        do { try MacFinanceEditing.retire(.deposit(deposit), in: context); removing = nil; saved() }
                        catch { self.error = MacLocalization.error(error) }
                    }.accessibilityIdentifier("confirmRemoveFinance")
                }
            }.appPadding(24).appDialog(width: 500)
        }
        .alert(L10n.text("liquidity.return"), isPresented: $returningPrincipal) {
            Button(L10n.text("mac.insightsView.body.2cd0f3be87"), role: .cancel) { }
            Button(L10n.text("liquidity.return.confirm")) {
                do { try MacLiquidity.confirmPrincipal(deposit, in: context); saved() }
                catch { self.error = MacLocalization.error(error) }
            }
        } message: {
            Text(L10n.text("liquidity.return.help") + "\n" + MacOverviewStyle.money(deposit.originalPrincipal) + " " + deposit.originalCurrency)
        }
        .sheet(item: $confirming) { deposit in
            VStack(alignment: .leading, spacing: MacUI.space(18)) {
                Text(L10n.text("mac.depositsView.presentedDetail.43ba5d1078")).appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("confirmDepositInterestTitle")
                Text(deposit.bankName).appFont(.section, weight: .semibold)
                Text(L10n.text("mac.depositsView.presentedDetail.87d31882f5"))
                if deposit.originalCurrency != bookCurrency { Text(L10n.text("mac.depositsView.presentedDetail.60b713baaa")).appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                HStack { Spacer(); Button(L10n.text("mac.depositsView.presentedDetail.2cd0f3be87")) { confirming = nil }.accessibilityIdentifier("cancelDepositInterest")
                    Button(L10n.text("mac.depositsView.presentedDetail.2b20833e6e")) { confirming = nil; post(deposit) }.accessibilityIdentifier("confirmDepositInterest")
                }
            }.appPadding(24).appDialog(width: 500)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: MacUI.space(15)) {
            HStack {
                Text(L10n.text("mac.depositsView.filters.b5f15473fd")).appFont(.section, weight: .semibold); Spacer()
                Button { showsNew = true } label: { Image(systemName: "plus").frame(width: MacUI.space(24), height: MacUI.space(24)) }
                    .buttonStyle(MacInteractiveButtonStyle()).appHelp(L10n.text("mac.depositsView.filters.773badd32b")).accessibilityLabel(L10n.text("mac.depositsView.filters.773badd32b")).accessibilityIdentifier("financeAdd").disabled(bookCurrency == nil || posting)
            }
            TextField(L10n.text("mac.depositsView.filters.873f743d47"), text: $search).textFieldStyle(.roundedBorder).accessibilityIdentifier("depositSearch")
            ScrollView {
                VStack(alignment: .leading, spacing: MacUI.space(7)) {
                    filterButton(L10n.text("mac.depositsView.filterButton.6b5a8e8b5b"), count: active.count, selected: status == nil, icon: "tray", id: "depositAll") { status = nil }
                    ForEach([MacDepositsData.Status.active, .soon, .matured]) { item in
                        filterButton(L10n.builtIn(item.rawValue),
                            count: active.filter { MacDepositsData.matches(MacDepositsData.status($0, now: now), filter: item) }.count,
                            selected: status == item, icon: item == .matured ? "calendar.badge.exclamationmark" : "clock", id: "depositStatus-\(item.rawValue)") { status = item }
                    }
                    Divider().appPadding(.vertical, 8)
                    Text(L10n.text("mac.depositsView.ScrollView.8a08964d02")).appFont(.caption, weight: .semibold).foregroundStyle(.secondary).appPadding(.leading, 8)
                    filterButton(L10n.text("mac.depositsView.filterButton.d7904daa2b"), selected: bank == nil, id: "depositBankAll") { bank = nil }
                    ForEach(banks, id: \.self) { name in
                        filterButton(name, count: active.filter { $0.bankName == name }.count, selected: bank == name, id: "depositBank-\(name)") { bank = name }
                    }
                    Divider().appPadding(.vertical, 8)
                    Text(L10n.text("mac.depositsView.ScrollView.21c7006514")).appFont(.caption, weight: .semibold).foregroundStyle(.secondary).appPadding(.leading, 8)
                    filterButton(L10n.text("mac.depositsView.filterButton.efeb7909d4"), selected: currency == nil, id: "depositCurrencyAll") { currency = nil }
                    ForEach(currencies, id: \.self) { code in
                        filterButton(code, count: active.filter { $0.originalCurrency == code }.count, selected: currency == code, id: "depositCurrency-\(code)") { currency = code }
                    }
                }
            }
            Button(L10n.text("mac.depositsView.filters.13a431e59b")) { search = ""; status = nil; bank = nil; currency = nil }.buttonStyle(MacInteractiveButtonStyle())
                .foregroundStyle(.secondary).accessibilityIdentifier("depositReset")
        }.appPadding(18).background(MacOverviewStyle.filters)
    }
    private func filterButton(_ title: String, count: Int? = nil, selected: Bool, icon: String? = nil, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: MacUI.space(7)) {
                if let icon { Image(systemName: icon).frame(width: max(16, MacUI.fontTier.captionSize + 5)) }
                Text(title).lineLimit(2); Spacer(minLength: 2)
                if let count { Text("\(count)").monospacedDigit().foregroundStyle(.secondary) }
            }.appFont(.caption, weight: .regular, design: .default).appPadding(.horizontal, 9).appPadding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .macFinanceFilterRow(selected: selected)
        }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier(id)
    }
    private func list(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(14)) {
            HStack { Text(L10n.format("mac.depositsView.list.0ed352d826", Int64(visible.count))).appFont(.section, weight: .semibold).accessibilityIdentifier("depositCount"); Spacer()
                if !wide, selected != nil { Button { showsDetails = true } label: { Image(systemName: "sidebar.right") }.appHelp(L10n.text("mac.depositsView.list.a748cc074f")).accessibilityLabel(L10n.text("mac.depositsView.list.a748cc074f")).accessibilityIdentifier("depositOpenDetails") }
            }
            MacFinanceListToolbar(columns: $listColumns, sort: $sort, options: MacDepositsData.Sort.allCases.map { (L10n.builtIn($0.rawValue), $0) }, prefix: "deposit")
            if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red).accessibilityIdentifier("financeActionError") }
            if let message { Text(message).appFont(.caption, weight: .regular).foregroundStyle(MacOverviewStyle.income).accessibilityIdentifier("financeActionMessage") }
            if bookCurrency == nil { Text(L10n.text("mac.depositsView.list.33e3d7368a")).appFont(.caption, weight: .regular).foregroundStyle(.orange) }
            if visible.isEmpty {
                ContentUnavailableView(active.isEmpty ? L10n.text("mac.depositsView.ContentUnavailableView.87258f9be8") : L10n.text("mac.depositsView.ContentUnavailableView.a762435c56"), systemImage: "building.columns", description: Text(active.isEmpty ? L10n.text("mac.depositsView.ContentUnavailableView.7213976126") : L10n.text("mac.depositsView.ContentUnavailableView.a66a4eba48")))
                    .accessibilityIdentifier("depositsEmptyState").frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: listColumns == 2 ? 2 : 1), spacing: 10) {
                        ForEach(visible, id: \.id) { deposit in
                            Button { selectedID = deposit.id; if !wide { showsDetails = true } } label: { row(deposit) }
                                .buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("depositRow-\(deposit.bankName)")
                        }
                    }.appPadding(1)
                }
            }
        }.appPadding(18).background(MacOverviewStyle.canvas)
    }
    private func row(_ deposit: DepositRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                MacBankIcon(bank: deposit.bankName, size: 32, revision: logoRevision)
                VStack(alignment: .leading, spacing: 3) { Text(deposit.bankName).appFont(.body, weight: .semibold).fixedSize(horizontal: false, vertical: true); Text(MacDepositsData.mode(deposit)).appFont(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                Spacer(minLength: 0)
            }
            Text("\(MacOverviewStyle.money(deposit.originalPrincipal)) \(deposit.originalCurrency)").appFont(.section, weight: .semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "%.2f%%", deposit.annualInterestRate))
                if !MacFinanceNotes.visible(deposit.note).isEmpty { Text(MacFinanceNotes.visible(deposit.note)).fixedSize(horizontal: false, vertical: true) }
                Text(MacDateDisplay.string(deposit.maturityDate))
                badge(deposit)
            }.appFont(.caption).foregroundStyle(.secondary)

        }.padding(12).frame(maxWidth: .infinity, minHeight: 104, alignment: .leading).contentShape(Rectangle()).macFinanceSelectableRow(selected: selectedID == deposit.id)
    }
    private func badge(_ deposit: DepositRecord) -> some View {
        let status = MacDepositsData.status(deposit, now: now)
        let color: Color = status == .soon ? .orange : (status == .active ? MacOverviewStyle.income : .secondary)
        return Text(L10n.builtIn(status.rawValue)).appFont(.caption, weight: .regular).foregroundStyle(color).appPadding(.horizontal, 8).appPadding(.vertical, 4)
            .background(color.opacity(0.1), in: Capsule())
    }
    private func detail(_ deposit: DepositRecord, compact: Bool) -> some View {
        GeometryReader { geometry in
            let audit = MacDepositsData.audit(deposit, transactions: transactions)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    detailHeader(deposit)
                    summaryCard(deposit)
                    timingCard(deposit)
                    MacFinanceCardRow(minimumWidth: 560) {
                        settlementCard(deposit, audit: audit)
                        scheduleCard(deposit)
                    }
                    if !MacFinanceNotes.visible(deposit.note).isEmpty {notesCard(deposit)}
                    if deposit.typedInterestSettlementMode == .monthly || !audit.receipts.isEmpty || audit.unverifiedCount > 0 {
                        receiptsCard(deposit, audit: audit)
                    }
                    if deposit.originalCurrency != deposit.baseCurrencyCode {
                        card { Text(L10n.text("mac.depositsView.card.30136c573e")).appFont(.section, weight: .semibold); Text("\(MacOverviewStyle.money(deposit.basePrincipal)) \(deposit.baseCurrencyCode)").accessibilityIdentifier("depositBookPrincipal"); Text(L10n.text("mac.depositsView.card.c4ee50bccc") + String(deposit.principalExchangeRateToBase)).appFont(.caption).foregroundStyle(.secondary) }
                    }
                }.padding(compact ? 18 : 22).padding(.bottom, 52)
            }.background(MacOverviewStyle.canvas).accessibilityIdentifier("depositDetailScroll").id(deposit.id)
        }
    }
    private func detailHeader(_ deposit: DepositRecord) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                detailIdentity(deposit).fixedSize(horizontal: true, vertical: true)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 8) { badge(deposit); detailActions(deposit) }
            }
            VStack(alignment: .leading, spacing: 10) {
                detailIdentity(deposit)
                ViewThatFits(in: .horizontal) {
                    HStack { badge(deposit); Spacer(minLength: 8); detailActions(deposit) }
                    VStack(alignment: .leading, spacing: 8) { badge(deposit); detailActions(deposit) }
                }
            }
        }
    }
    private func detailIdentity(_ deposit: DepositRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            MacBankIcon(bank: deposit.bankName, size: 46, revision: logoRevision)
            VStack(alignment: .leading, spacing: 5) {
                Text(deposit.bankName).appFont(.dialogTitle, weight: .semibold).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("depositDetailTitle")
                Text(MacDepositsData.mode(deposit)).appFont(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func detailActions(_ deposit: DepositRecord) -> some View {
                HStack(spacing: 8) {
                    Button(L10n.text("mac.depositsView.detailActions.0518365699"), systemImage: "pencil") { editing = .deposit(deposit) }.accessibilityIdentifier("editFinance-" + deposit.id.uuidString).disabled(bookCurrency == nil || posting)
                    Menu {
                        if MacLiquidity.pending(deposit, profile: (profiles.first { $0.deletedAt == nil && $0.liquidityData != nil } ?? profiles.first { $0.deletedAt == nil })), Calendar.current.startOfDay(for: deposit.maturityDate) <= Calendar.current.startOfDay(for: now) {
                            Button(L10n.text("liquidity.return")) { returningPrincipal = true }
                        }
                        Button(L10n.text("mac.depositsView.Menu.4fec38cbe7"), systemImage: "doc.on.doc") { copying = deposit }.accessibilityIdentifier("depositCopy").disabled(bookCurrency == nil)
                        Button(L10n.text("mac.depositsView.Menu.0481d5ba76")) { chooseLogo(deposit.bankName) }.accessibilityIdentifier("depositChooseLogo")
                        Button(L10n.text("mac.depositsView.Menu.0ed90379cb")) { do { try MacBankLogos.reset(deposit.bankName); logoRevision += 1 } catch { self.error = MacLocalization.error(error) } }
                        Divider(); Button(L10n.text("mac.depositsView.Menu.be47f441b1"), role: .destructive) { removing = deposit }.accessibilityIdentifier("depositRemove")
                    } label: { Image(systemName: "ellipsis").frame(width: 28, height: 30).contentShape(Rectangle()) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityIdentifier("depositMore").disabled(posting)
                }

    }
    private func summaryCard(_ deposit: DepositRecord) -> some View {
        card {
            Text("\(MacOverviewStyle.money(deposit.originalPrincipal)) \(deposit.originalCurrency)").appFont(.amount, weight: .semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65).accessibilityIdentifier("depositPrincipal")
            Text(L10n.text("mac.depositsView.card.a5b2fc24c7")).appFont(.caption).foregroundStyle(.secondary); Divider()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top) { metric(L10n.text("mac.depositsView.metric.7f32635153"), String(format: "%.2f%%", deposit.annualInterestRate)); Spacer(); metric(L10n.text("mac.depositsView.metric.cfcbdb18dd"), L10n.format("mac.depositsView.metric.ce36b03d26", "\(MacDepositsData.timing(deposit, now: now).total)")); Spacer(); metric(L10n.text("mac.depositsView.metric.cf22e3b05c"), "\(MacOverviewStyle.money(MacDepositTerms.projectedInterest(deposit))) \(deposit.originalCurrency)", id: "depositExpectedInterest") }
                VStack(alignment: .leading, spacing: 10) { metric(L10n.text("mac.depositsView.metric.7f32635153"), String(format: "%.2f%%", deposit.annualInterestRate)); metric(L10n.text("mac.depositsView.metric.cfcbdb18dd"), L10n.format("mac.depositsView.metric.ce36b03d26", "\(MacDepositsData.timing(deposit, now: now).total)")); metric(L10n.text("mac.depositsView.metric.cf22e3b05c"), "\(MacOverviewStyle.money(MacDepositTerms.projectedInterest(deposit))) \(deposit.originalCurrency)", id: "depositExpectedInterest") }
            }
            if deposit.isInterestManuallyEdited { Text(L10n.text("mac.depositsView.card.8b0e533e0e")).appFont(.caption).foregroundStyle(.secondary) }
        }
    }
    private func notesCard(_ deposit: DepositRecord) -> some View {
        let text=MacFinanceNotes.visible(deposit.note)
        return card {
            Text(L10n.text("mac.depositsView.card.daede98817")).appFont(.section,weight:.semibold)
            Text(text).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(noteExpanded ? nil:3).fixedSize(horizontal:false,vertical:true)
            if text.count>28 || text.contains("\n") {Button(noteExpanded ? L10n.text("mac.depositsView.card.2cd9fd3460"):L10n.text("mac.depositsView.card.13ef1dc30a")) {noteExpanded.toggle()}.appFont(.caption)}
        }
    }
    private func timingCard(_ deposit: DepositRecord) -> some View {
        let timing = MacDepositsData.timing(deposit, now: now)
        return card {
            ViewThatFits(in: .horizontal) {
                HStack(spacing:0) {metric(L10n.text("mac.depositsView.metric.760506491e"),MacDateDisplay.string(deposit.startDate)).fixedSize(horizontal:true,vertical:false);Spacer(minLength:24);metric(L10n.text("mac.depositsView.metric.7589d263a3"),MacDateDisplay.string(deposit.maturityDate)).fixedSize(horizontal:true,vertical:false)}
                VStack(alignment: .leading, spacing: 10) { metric(L10n.text("mac.depositsView.metric.760506491e"), MacDateDisplay.string(deposit.startDate)); metric(L10n.text("mac.depositsView.metric.7589d263a3"), MacDateDisplay.string(deposit.maturityDate)) }
            }
            ProgressView(value: timing.progress).tint(MacUI.accent)
            HStack { Text(now < deposit.startDate ? L10n.text("mac.depositsView.card.5be128c8a5") : L10n.format("mac.depositsView.card.69756c3e4c", "\(timing.elapsed)")); Spacer(); Text(timing.remaining > 0 ? L10n.format("mac.depositsView.card.862742e212", "\(timing.remaining)") : L10n.text("mac.depositsView.card.b9d8853e0c")) }.appFont(.caption).foregroundStyle(.secondary)
        }
    }
    private func settlementCard(_ deposit: DepositRecord, audit: MacDepositsData.ReceiptAudit) -> some View {
        card {
            Text(L10n.text("mac.depositsView.card.be81ae31e4")).appFont(.section, weight: .semibold)
            metric(L10n.text("mac.depositsView.metric.c54a33a610"), "\(MacOverviewStyle.money(audit.total)) \(deposit.originalCurrency)", id: "depositPostedInterest")
            Text(audit.pendingCount > 0 ? L10n.format("mac.depositsView.card.3dbd6331d8", "\(audit.pendingCount)") : audit.partialCount > 0 ? L10n.text("deposit.earnings.partial.status") : deposit.hasCreditedInterest ? L10n.text("mac.depositsView.card.078989f6d9") : L10n.text("mac.depositsView.card.0428113787")).appFont(.caption).foregroundStyle(audit.pendingCount > 0 || audit.partialCount > 0 ? .orange : .secondary).accessibilityIdentifier("depositSettlementStatus")
            if audit.unverifiedCount > 0 { Label(L10n.format("mac.depositsView.card.10828b3a8f", "\(audit.unverifiedCount)"), systemImage: "exclamationmark.triangle").appFont(.caption).foregroundStyle(.orange).accessibilityIdentifier("depositReceiptWarning") }
            if !MacDepositSettlement.isManaged(deposit) {
                Text(L10n.text("mac.depositsView.card.e2539a4a59")).appFont(.caption).foregroundStyle(.secondary)
                Button(L10n.text("mac.depositsView.card.33bd6f76cb")) { reviewing = .deposit(deposit) }.accessibilityIdentifier("reviewFinance-" + deposit.id.uuidString).disabled(bookCurrency == nil || posting)
            } else if !deposit.hasCreditedInterest {
                Text(L10n.text("mac.depositsView.card.ad87906358")).appFont(.caption).foregroundStyle(.secondary)
                Button(posting ? L10n.text("mac.depositsView.card.c31167bc2b") : L10n.text("mac.depositsView.card.9c5e17428b"), systemImage: "checkmark.circle") { confirming = deposit }.accessibilityIdentifier("postDepositInterest-" + deposit.id.uuidString).disabled(posting || bookCurrency == nil || !MacDepositSettlement.isEligible(deposit, now: now))
            }
        }
    }
    private func receiptsCard(_ deposit: DepositRecord, audit: MacDepositsData.ReceiptAudit) -> some View {
        card {
            Text(L10n.text("mac.depositsView.card.6f95204a86")).appFont(.section, weight: .semibold)
            if audit.receipts.isEmpty { Text(L10n.text("mac.depositsView.card.2fc76c9845")).foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(audit.receipts, id: \.id) { receipt in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(MacDateDisplay.string(receipt.date)).appFont(.caption).foregroundStyle(.secondary)
                            Text("+\(MacOverviewStyle.money(receipt.originalAmount)) \(receipt.originalCurrency)").appFont(.body, weight: .semibold).foregroundStyle(MacOverviewStyle.income)
                            Button((receipt.note ?? "").contains("[FTEstimated]") ? L10n.text("mac.depositsView.ForEach.9e7050cbb4") : L10n.text("mac.depositsView.ForEach.29565a9dcf")) { reconciling = receipt }.appFont(.caption).disabled(bookCurrency == nil || posting)
                        }
                        Divider()
                    }
                }
            }.frame(minHeight: audit.receipts.isEmpty ? 1 : 80, maxHeight: 210)
        }
    }
    private func scheduleCard(_ deposit: DepositRecord) -> some View {
        card {
            Text(L10n.text("mac.depositsView.card.1813dfd5d5")).appFont(.section, weight: .semibold)
            Text(L10n.text("mac.depositsView.card.55e3e1f0ce")).appFont(.caption).foregroundStyle(.secondary)
            ForEach(Array(MacDepositScheduleView.rows(for: deposit).prefix(3))) { row in
                VStack(alignment: .leading, spacing: 4) { Text(MacDateDisplay.string(row.date)).appFont(.caption).foregroundStyle(.secondary); Text("\(MacOverviewStyle.money(row.interest)) \(deposit.originalCurrency)").appFont(.body, weight: .medium).monospacedDigit() }
            }
            Button(L10n.text("mac.depositsView.card.edb77300e6")) { schedule = deposit }.appFont(.caption).accessibilityIdentifier("depositFullSchedule")
        }
    }
    private func metric(_ title: String, _ value: String, id: String = "") -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(7)) {
            Text(value).appFont(.body, weight: .semibold, design: .default).monospacedDigit().textSelection(.enabled).accessibilityIdentifier(id).id(value)
            Text(title).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
        }
    }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(12), content: content).appPadding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .macFinanceDetailCard()
    }
    private func saved() {
        error = nil; message = L10n.text("mac.depositsView.saved.1bd91a7d0c"); now = Date()
        Task { try? await MacNotifications.schedule(in: context) }
    }
    private func post(_ deposit: DepositRecord) {
        guard let bookCurrency, !posting else { return }
        posting = true; error = nil; message = nil
        Task { @MainActor in
            defer { posting = false }
            do {
                let result = try await MacAutomaticPosting.post(deposit, now: Date(), book: bookCurrency, in: context)
                message = L10n.format("mac.depositsView.Task.feda291839", "\(result.receipts)", "\(MacOverviewStyle.money(result.totalInterest))", "\(deposit.originalCurrency)")
                now = Date(); try? await MacNotifications.schedule(in: context)
            } catch { self.error = MacLocalization.error(error) }
        }
    }
    private func chooseLogo(_ bank: String) {
        do { cropInput = try MacBankLogos.select(for: bank); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
