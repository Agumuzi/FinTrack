import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

enum MacWorkspaceSection: String {
    case overview = "概览", records = "账目", deposits = "存款", recurring = "周期", loans = "贷款"
    case settings = "设置", insights = "进阶统计"
    var icon: String {
        switch self {
        case .overview: "house"
        case .records: "doc.text"
        case .deposits: "building.columns"
        case .recurring: "clock.arrow.circlepath"
        case .loans: "banknote"
        case .settings: "gearshape"
        case .insights: "chart.bar.xaxis"
        }
    }
}

@MainActor
final class MacWorkspaceSession: ObservableObject {
    @Published var section: MacWorkspaceSection = .overview
    init() {
        let d = MacPreferences.defaults
        if MacSettingsVisual.preview { section = .settings; return }
        if d.object(forKey: "v2_resume_page") as? Bool != false, let name = d.string(forKey: "v2_last_page"), let saved = MacWorkspaceSection(rawValue: name) { section = saved }
    }
    @Published var recordScope: MacOverviewScope?
    @Published var recordsNavigationState = MacRecordsNavigationState()
    @Published var showsQuickRecord = false
    func showRecords(_ scope: MacOverviewScope? = nil) {
        recordScope = scope; section = .records
    }
}

struct FinTrackMacRootView: View {
    @StateObject private var operationFeedback = MacOperationFeedbackCenter()
    @FocusState private var accountPanelFocused: Bool
    @EnvironmentObject private var workspace: MacWorkspaceSession
    @State private var previewCurrency = "RUB"
    @AppStorage("app_language") private var language = "zh-Hans"
    @AppStorage("color_theme_mode") private var theme = "system"
    @AppStorage("v2_navigation_collapsed") private var navigationCollapsed = false
    @AppStorage("base_currency") private var preferredCurrency = "USD"
    @AppStorage("v2_density") private var interfaceDensity = "comfortable"
    @AppStorage("v2_accent") private var interfaceAccent = "terracotta"
    @AppStorage("v2_avatar", store: MacPreferences.defaults) private var accountAvatar = Data()
    @AppStorage(MacCustomTypography.bodyKey, store: MacPreferences.defaults) private var bodyPoints = 16
    @AppStorage(MacCustomTypography.captionKey, store: MacPreferences.defaults) private var captionPoints = 12
    @AppStorage("v2_display_name") private var displayName = "我的账本"
    @State private var showsAccount = false
    @Environment(\.modelContext) private var context
    @AppStorage("fintrack_auto_posting") private var automaticPosting = false
    @AppStorage("v13_auto_deposit_posting") private var automaticDeposits = true
    @ObservedObject private var appServices = MacAppServices.shared
    @Query private var transactions: [Transaction]
    @Query private var deposits: [DepositRecord]
    @Query private var loans: [LoanRule]
    @Query private var recurring: [RecurringTransaction]

    private var currency: String? {
        MacCurrency.resolveLedgerCurrency(transactions: transactions, deposits: deposits,
            loans: loans, recurring: recurring, preferred: preferredCurrency).displayCurrency
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = navigationCollapsed || geometry.size.width < MacUI.space(1080)
            VStack(spacing: MacUI.space(0)) {
                chromeHeader(compact: compact)
                HStack(spacing: MacUI.space(0)) {
                navigation(compact: compact)
                Group {
                    switch workspace.section {
                    case .overview:
                        MacOverviewView(bookCurrency: currency, workspace: workspace)
                    case .records:
                        MacRecordSection(scope: workspace.recordScope, navigationState: workspace.recordsNavigationState)
                            .id(String(describing: workspace.recordScope))
                    case .insights: MacInsightsView(previewCurrency: previewCurrency)
                    case .settings: MacSettingsView(previewCurrency: $previewCurrency)
                    case .deposits: MacDepositsView(bookCurrency: currency)
                    case .recurring: MacRecurringView(bookCurrency: currency)
                    case .loans: MacLoansView(bookCurrency: currency)
                    }
                }
                .id(workspace.section)
                .frame(width: max(1, geometry.size.width - MacUI.space(compact ? 68 : 184) - MacUI.space(24)), height: max(1, geometry.size.height - MacUI.space(46)))
                .background(MacOverviewStyle.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .appPadding(.trailing, 8).appPadding(.bottom, 8)
                }
            }
        }
        .background {
            #if FINTRACK_LOCAL_VALIDATION
            if MacPreferences.isTesting { MacOverviewPreviewSize().frame(width: MacUI.space(0), height: MacUI.space(0)) }
            #endif
        }
        .overlay(alignment: .bottomLeading) {
            #if FINTRACK_LOCAL_VALIDATION
            MacRecordSizingDiagnosticsView()
            #endif
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 800, minHeight: 600)
        .background(MacOverviewStyle.navigation)
        .environmentObject(operationFeedback)
        .modifier(MacOperationFeedbackPresenter(center:operationFeedback))
        .modifier(MacUpdateSheetPresenter())
        .modifier(MacPermissionSheetPresenter())
        .overlay {
            if showsAccount {
                ZStack(alignment: .bottomLeading) {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { showsAccount = false }
                        .accessibilityHidden(true)
                    accountPanel
                        .appPadding(.leading, 24).appPadding(.bottom, 76)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .focusable().focusEffectDisabled().focused($accountPanelFocused)
                    .onAppear { accountPanelFocused = true }
                    .onExitCommand { showsAccount = false }
            }
        }
        .environment(\.locale, Locale(identifier: MacPreferences.isTesting ? language : "zh-Hans"))
        .tint(MacAccent.color(interfaceAccent))
        .appFont(.body)
        .environment(\.defaultMinListRowHeight, interfaceDensity == "compact" ? 25 : interfaceDensity == "spacious" ? 40 : 32)
        .environment(\.calendar, MacDisplayPreferences.calendar)
        .onChange(of: workspace.section) { _, section in MacPreferences.defaults.set(section.rawValue, forKey: "v2_last_page") }
        .preferredColorScheme(theme == "dark" ? .dark : (theme == "light" ? .light : nil))
        .overlay(alignment: .bottom) {
            if let error = appServices.postingError { Text(error).appFont(.caption).foregroundStyle(.red).padding(10).background(.regularMaterial) }
        }
        .onExitCommand { showsAccount = false }
        .onAppear {
            if MacSettingsVisual.preview { NSApp.activate(ignoringOtherApps: true) }
        }
        .sheet(isPresented: $workspace.showsQuickRecord) {
            if let currency { MacTransactionEditor(bookCurrency: currency, existing: nil) }
            else {
                VStack(spacing: MacUI.space(18)) {
                    Text("账本包含不同本位币，请先在设置中核对。")
                    Button("关闭") { workspace.showsQuickRecord = false }
                }.appPadding(28)
            }
        }
    }

    private func chromeHeader(compact: Bool) -> some View {
        let railWidth: CGFloat = MacUI.space(compact ? 68 : 184)
        // Align the title text with the filter panel's 18pt inset.
        // Keep the compact title clear of the system window controls.
        let titleGap = max(0, railWidth - 78 - MacUI.space(72)) + (workspace.section == .insights && !compact ? 12 : 0)
        return HStack(spacing: MacUI.space(12)) {
            // The system owns the traffic lights; reserve their titlebar area.
            Color.clear.frame(width: MacUI.space(78), height: MacUI.space(1))
            Button { navigationCollapsed.toggle() } label: {
                Image(systemName: "sidebar.left").appIconFont(17, weight: .regular, design: .default)
                    .foregroundStyle(.secondary).frame(width: MacUI.space(30), height: MacUI.space(30))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(MacInteractiveButtonStyle())
                .appHelp(navigationCollapsed ? "展开导航" : "收起导航")
                .accessibilityLabel("切换导航宽度").accessibilityIdentifier("toggleNavigation")
            if workspace.section == .overview || workspace.section == .records || workspace.section == .deposits || workspace.section == .recurring || workspace.section == .loans || workspace.section == .insights || (workspace.section == .settings && !compact) {
                Color.clear.frame(width: titleGap, height: 1)
            }
            Text(workspace.section.rawValue).appFont(.body, weight: .semibold, design: .default)
                .appPadding(.horizontal, 14).appPadding(.vertical, 7)
                .background(MacOverviewStyle.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityIdentifier("chromeSectionTitle")
            Spacer()
        }.appPadding(.horizontal, 12).appMinHeight(38)
            .background(MacOverviewStyle.navigation)
    }

    private var accountPanel: some View {
                    VStack(alignment: .leading, spacing: MacUI.space(14)) {
                        Label("本地账本", systemImage: "externaldrive").appFont(.section, weight: .semibold)
                        Text("本位币：\(currency ?? "待核对")").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                        if let currency {
                            let range = Calendar.current.dateInterval(of: .month, for: Date())!
                            let rows = transactions.filter { $0.deletedAt == nil && $0.date >= range.start && $0.date < range.end }
                            let totals = MacTransactionCRUD.totals(transactions: rows, currency: currency)
                            Text("本月收入  \(MacOverviewStyle.money(totals.income)) \(currency)")
                            Text("本月支出  \(MacOverviewStyle.money(totals.expense)) \(currency)")
                        }
                        Divider()
                        Button("设置", systemImage: "gearshape") { workspace.section = .settings; showsAccount = false }
                            .accessibilityIdentifier("navSettings")
                        Button("进阶统计", systemImage: "chart.bar.xaxis") { workspace.section = .insights; showsAccount = false }
                            .accessibilityIdentifier("navInsights")
                        Text("FinTrack · 本机保存").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                    }.appPadding(16).frame(width: MacUI.space(236))
            .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 5)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture { }
    }

    private func navigation(compact: Bool) -> some View {
        VStack(alignment: compact ? .center : .leading, spacing: MacUI.space(8)) {
            HStack(spacing: MacUI.space(10)) {
                MacBrandIcon(size: 30)
                if !compact { Text("FinTrack").appFont(.section, weight: .semibold) }
            }.appMinHeight(42).appPadding(.horizontal, 14).appPadding(.bottom, 8)
            nav(.overview, id: "navOverview", compact: compact)
            nav(.records, id: "navRecords", compact: compact)
            nav(.deposits, id: "navFinance", compact: compact)
            nav(.recurring, id: "navRecurring", compact: compact)
            nav(.loans, id: "navLoans", compact: compact)
            Spacer()
            HStack { Button { showsAccount.toggle() } label: {
                HStack(spacing: MacUI.space(10)) {
                    if let image = NSImage(data: accountAvatar) {
                        Image(nsImage: image).resizable().scaledToFill().frame(width: 28, height: 28).clipShape(Circle()).accessibilityIdentifier("accountAvatarImage")
                    } else {
                        Image(systemName: "person.crop.circle").appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("accountAvatarPlaceholder")
                    }
                    if !compact {
                        VStack(alignment: .leading, spacing: MacUI.space(3)) {
                            Text(displayName).appFont(.body, weight: .medium, design: .default)
                            Text(currency ?? "需要核对币种").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "chevron.up").appFont(.caption, weight: .regular)
                    }
                }.appPadding(12).frame(maxWidth: .infinity).contentShape(Rectangle())
            }.buttonStyle(MacInteractiveButtonStyle()).appHelp("账本与设置").accessibilityLabel("账本与设置")
                .accessibilityIdentifier("accountMenu").accessibilityValue(NSImage(data: accountAvatar) == nil ? "默认头像" : "自定义头像")
            }

        }
        .appPadding(.horizontal, 8).appPadding(.top, 14).appPadding(.bottom, 12)
        .frame(width: MacUI.space(compact ? 68 : 184))
        .background(MacOverviewStyle.navigation)
    }
    private func nav(_ section: MacWorkspaceSection, id: String, compact: Bool) -> some View {
        Button {
            if section == .records { workspace.showRecords() } else { workspace.section = section }
        } label: {
            HStack(spacing: MacUI.space(12)) {
                Image(systemName: section.icon).appIconFont(18, weight: .regular, design: .default).frame(width: MacUI.space(24))
                if !compact { Text(section.rawValue).appFont(.body, weight: workspace.section == section ? .semibold : .regular); Spacer() }
            }.appPadding(.horizontal, 12).appMinHeight(43).frame(maxWidth: .infinity)
                .foregroundStyle(workspace.section == section ? (section == .settings ? MacSettingsVisual.accent : MacOverviewStyle.accent) : .primary)
                .background(workspace.section == section ? (section == .settings ? MacSettingsVisual.accent : MacOverviewStyle.accent).opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }.buttonStyle(MacInteractiveButtonStyle()).appHelp(section.rawValue).accessibilityLabel(section.rawValue).accessibilityIdentifier(id)
    }
}
