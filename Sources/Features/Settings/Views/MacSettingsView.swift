import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

enum MacSettingsPage: String, CaseIterable, Identifiable {
    case account = "账户与偏好", currency = "货币与汇率", categories = "分类管理", budgets = "预算设置", goals = "目标管理"
    case backup = "数据备份与导出", appearance = "外观与语言", general = "通用设置", about = "关于 FinTrack"
    var id: String { String(describing: self) }
    var title: String { L10n.text("settings.\(id).title") }
    var icon: String {
        switch self {
        case .account: "person.crop.circle"
        case .currency: "globe"
        case .categories: "tag"
        case .budgets: "chart.xyaxis.line"
        case .goals: "target"
        case .backup: "externaldrive"
        case .appearance: "paintpalette"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }
    var subtitle: String {
        switch self {
        case .account: L10n.text("mac.settingsView.subtitle.212832719e")
        case .currency: L10n.text("mac.settingsView.subtitle.c83f955b44")
        case .categories: L10n.text("mac.settingsView.subtitle.f130dbff2f")
        case .budgets: L10n.text("mac.settingsView.subtitle.2f6a2057fd")
        case .goals: L10n.text("mac.settingsView.subtitle.8dffcbaba3")
        case .backup: L10n.text("mac.settingsView.subtitle.4007b279a0")
        case .appearance: L10n.text("mac.settingsView.subtitle.0fc175ac28")
        case .general: L10n.text("mac.settingsView.subtitle.894ac59479")
        case .about: L10n.text("mac.settingsView.subtitle.765ab3c019")
        }
    }
}

struct MacSettingsView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @AppStorage(MacCustomTypography.bodyKey, store: MacPreferences.defaults) private var layoutBodyPoints = 16
    @AppStorage(MacCustomTypography.captionKey, store: MacPreferences.defaults) private var layoutCaptionPoints = 12
    @Binding var previewCurrency: String
    @AppStorage("v2_font_tier", store: MacPreferences.defaults) private var fontTierValue = MacFontSizeTier.standard.rawValue
    @Environment(\.modelContext) private var context
    @AppStorage("v2_settings_page") private var pageName = "account"
    @AppStorage("base_currency") private var baseCurrency = "USD"
    @AppStorage("v2_display_name") private var displayName = ""
    @AppStorage("color_theme_mode") private var theme = "system"
    @AppStorage("v2_week_start") private var weekStart = 2
    @AppStorage("v2_avatar") private var avatar = Data()
    @State private var showsSelectiveClear = false
    @State private var selectedClearKind = MacClearKind.records
    @AppStorage("v13_auto_deposit_posting") private var automaticDeposits = true
    @AppStorage("fintrack_auto_posting") private var automaticPosting = false
    @Query private var transactions: [Transaction]
    @Query private var profiles: [FinancialProfile]
    @ObservedObject private var monitor = MacFXApplication.shared.monitor
    @AppStorage("v2_fx_sources") private var sourceBytes = Data()
    @AppStorage("v2_fx_quotes") private var quoteBytes = Data()
    @AppStorage("v2_confirm_clear") private var multipleClear = true
    @State private var refreshing = false
    @State private var showProfile = false
    @State private var showRebase = false
    @State private var pendingCurrency = ""
    @State private var showClear = false
    @State private var clearText = ""
    @State private var clearStage = 0
    @State private var message: String?
    @State private var error: String?
    private var page: MacSettingsPage { MacSettingsPage.allCases.first { $0.id == pageName } ?? .account }
    private var currency: String? { try? MacCurrency.ledgerCurrency(in: context, preferred: baseCurrency) }
    private var fontTierBinding: Binding<String> {
        Binding(
            get: { fontTierValue },
            set: { value in
                MacPreferences.defaults.set(value, forKey: MacFontSizeTier.preferenceKey)
                fontTierValue = value
            }
        )
    }

    var body: some View {
        let _ = layoutBodyPoints; let _ = layoutCaptionPoints
        GeometryReader { geometry in
            let compactMenu = geometry.size.width < MacUI.space(900)
            let menuWidth: CGFloat = max(230, 24 + MacUI.fontTier.bodySize * 8)
            HStack(spacing: MacUI.space(0)) {
                if !compactMenu { navigation.frame(width: menuWidth); Divider() }
                let contentWidth = geometry.size.width - (compactMenu ? 0 : menuWidth) - 44
                let minimumColumn: CGFloat = max(420, 230 + MacUI.fontTier.bodySize * 12)
                let wide = contentWidth >= 2 * minimumColumn + 16
                if page == .currency {
                    VStack(alignment:.leading,spacing:0) {
                        pageHeader(compactMenu:compactMenu)
                            .appPadding(.horizontal,22).appPadding(.top,22).appPadding(.bottom,14)
                            .frame(maxWidth:MacUI.space(1320),alignment:.leading).frame(maxWidth:.infinity,alignment:.leading)
                        MacCurrencySettingsView(wide:wide)
                    }.id(page.id)
                } else {
                    ScrollView {
                        VStack(alignment:.leading,spacing:MacUI.space(20)) {
                            pageHeader(compactMenu:compactMenu)
                            // Compact settings navigation also needs a stacked
                            // account page: its preview and source controls have
                            // larger natural widths than the small editor cards.
                            content(wide: wide && (page != .account || !compactMenu))
                        }.appPadding(22).frame(maxWidth:MacUI.space(1320),alignment:.topLeading).frame(maxWidth:.infinity,alignment:.topLeading)
                    }.accessibilityIdentifier("settingsScroll").id(page.id)
                }
            }
        }
        .buttonStyle(MacSettingsButtonStyle())
        .textFieldStyle(MacSettingsFieldStyle())
        .toggleStyle(.switch)
        .tint(MacSettingsVisual.accent)
        .sheet(isPresented: $showProfile) {
            MacFinancialProfileEditor(currency: currency ?? baseCurrency, profile: profiles.first { $0.deletedAt == nil })
        }
        .sheet(isPresented: $showRebase) { MacCurrencyRebaseView(initialCurrency: pendingCurrency) }
        .onAppear { pendingCurrency = baseCurrency }
        .onChange(of: baseCurrency) { _, value in pendingCurrency = value }
        .sheet(isPresented: $showClear) {
            VStack(alignment: .leading, spacing: MacUI.space(18)) {
                Label(L10n.text("mac.settingsView.body.4ba3447ef1"), systemImage: "exclamationmark.triangle.fill").appFont(.dialogTitle, weight: .semibold).foregroundStyle(.red)
                Text(L10n.text("mac.settingsView.body.30f30e8ece"))
                if clearStage == 0 {
                    HStack { Button(L10n.text("mac.settingsView.body.2cd0f3be87")) { showClear = false }; Spacer(); Button(L10n.text("mac.settingsView.body.9907489e09"), role: .destructive) { clearStage = 1 }.accessibilityIdentifier("clearContinue") }
                } else {
                    Text(L10n.text("ledger.clear.confirmation.prompt"))
                    TextField("DELETE", text: $clearText).accessibilityIdentifier("clearConfirmationText")
                    HStack {
                        Button(L10n.text("mac.settingsView.body.2cd0f3be87")) { showClear = false }
                        Spacer()
                        Button(L10n.text("mac.settingsView.body.7809fe40f7"), role: .destructive) {
                            perform {
                                try MacDataManagement.clearLedger(in: context)
                                try MacSettingsStore.save([MacBudget](), key: "v2_budgets")
                                MacNotifications.clear(); MacSettingsStore.defaults.set(false, forKey: "fintrack_auto_posting")
                                showClear = false; message = L10n.text("mac.settingsView.perform.703662a17a")
                            }
                        }.disabled(!MacClearConfirmation.accepts(clearText)).accessibilityIdentifier("clearFinalConfirm")
                    }
                }
            }.appPadding(28).appDialog(width: 500)
        }
        .sheet(isPresented: $showsSelectiveClear) { MacSelectiveDataClearView(initialKind: selectedClearKind) }
        .onChange(of: pageName) { message = nil; error = nil }
    }
    private func pageHeader(compactMenu:Bool) -> some View {
        VStack(alignment:.leading,spacing:MacUI.space(20)) {
            if compactMenu {
                Menu {
                    ForEach(MacSettingsPage.allCases) { item in
                        Button(item.title, systemImage: item.icon) { pageName = item.id }.accessibilityIdentifier("settingsNav-" + item.id)
                    }
                } label: { HStack { Text(L10n.text("mac.settingsView.Menu.832741195f")).foregroundStyle(.secondary); Text(page.title); Spacer(); Image(systemName: "chevron.down") } }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).appFormControl().accessibilityIdentifier("settingsPageMenu")
            }
            VStack(alignment: .leading, spacing: MacUI.space(7)) {
                HStack { Text(page.title).appFont(.pageTitle, weight: .bold, design: .default).accessibilityIdentifier("settingsPageTitle"); if MacSettingsVisual.preview { Text(L10n.text("mac.settingsView.pageHeader.193538685f")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).appPadding(.horizontal, 7).appPadding(.vertical, 3).background(.gray.opacity(0.06), in: Capsule()) }; Spacer() }
                if page != .account { Text(page.subtitle).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }
            }
            if let message { Label(message, systemImage: "checkmark.circle").foregroundStyle(.green).accessibilityIdentifier("settingsMessage") }
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled).accessibilityIdentifier("settingsError") }
        }
    }
    private var navigation: some View {
        VStack(alignment: .leading, spacing: MacUI.space(7)) {
            ForEach(MacSettingsPage.allCases) { item in
                if item == .backup { Divider().appPadding(.vertical, 12) }
                Button { pageName = item.id } label: {
                    HStack(spacing: MacUI.space(11)) {
                        Image(systemName: item.icon).appIconFont(20, weight: .regular, design: .default).frame(width: MacUI.space(25))
                        Text(item.title).appFont(.body, weight: item == page ? .semibold : .regular, design: .default).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }.appPadding(.horizontal, 12).appPadding(.vertical, 8).appMinHeight(47)
                        .foregroundStyle(item == page ? MacSettingsVisual.accent : .primary)
                        .background(item == page ? MacSettingsVisual.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("settingsNav-" + item.id)
            }
            Spacer()
        }.appPadding(12).appPadding(.top, 10).background(MacOverviewStyle.filters)
    }
    @ViewBuilder private func content(wide: Bool) -> some View {
        switch page {
        case .account: account(wide: wide)
        case .currency: MacCurrencySettingsView(wide: wide)
        case .categories: MacCategoriesSettingsView(wide: wide)
        case .budgets: MacBudgetSettingsView(wide: wide)
        case .goals: MacGoalSettingsView(wide: wide)
        case .backup: MacBackupSettingsView(wide: wide)
        case .appearance: MacAppearanceSettingsView(wide: wide, fontTierValue: fontTierBinding)
        case .general: MacGeneralSettingsView(wide: wide)
        case .about: MacAboutSettingsView(wide: wide)
        }
    }
    private var accountLanguageCard: some View {
        MacSettingsCard(title: L10n.text("mac.settingsView.accountLanguageCard.15d9b0f12d"), icon: "globe", headerColor: .blue, compactHeader: true, fillsHeight: true) {
            MacSettingsRow(label: L10n.text("mac.settingsView.accountLanguageCard.3d13868593"), labelWidth: 100) { MacLanguageChoice() }
            MacSettingsRow(label: L10n.text("mac.settingsView.accountLanguageCard.94513edaf6"), labelWidth: 100) {
                MacSettingsMenu(selection: $weekStart, options: [(L10n.text("mac.settingsView.MacSettingsMenu.56451fdf19"),2), (L10n.text("mac.settingsView.MacSettingsMenu.7e06f3148f"),1)]).accessibilityIdentifier("accountWeekStartMenu")
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("accountLanguageCard")
    }
    private var accountAppearanceCard: some View {
        MacSettingsCard(title: L10n.text("mac.settingsView.accountAppearanceCard.86a63f23a0"), icon: "paintpalette", headerColor: .blue, compactHeader: true, fillsHeight: true) {
            MacThemeChoices(theme: $theme)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("accountAppearanceCard")
    }
    private func account(wide: Bool) -> some View {
        VStack(spacing: MacUI.space(15)) {
            HStack(spacing: MacUI.space(18)) {
                Group {
                    if let image = NSImage(data: avatar) { Image(nsImage: image).resizable().scaledToFill() }
                    else { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary) }
                }.frame(width: MacUI.space(74), height: MacUI.space(74)).clipShape(Circle())
                VStack(alignment: .leading, spacing: MacUI.space(7)) {
                    TextField(L10n.text("mac.settingsView.account.ffa778f78d"), text: $displayName).appFont(.dialogTitle, weight: .bold, design: .default).textFieldStyle(.plain).accessibilityIdentifier("settingsDisplayName")
                    Text(L10n.text("mac.settingsView.account.4666bca0fd")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                }
                Spacer()
                MacImageImportControl(data: $avatar, title: L10n.text("mac.settingsView.MacImageImportControl.42ece89848"), cropTitle: L10n.text("mac.settingsView.MacImageImportControl.e251ac5147"), label: L10n.text("mac.settingsView.MacImageImportControl.3ea2d23c90"), circularPreview: true, identifier: "settingsAvatar")
            }.appPadding(22).background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 13))
            if wide {
                MacFinanceCardRow(minimumWidth: 0) { accountLanguageCard; accountAppearanceCard }
            } else {
                VStack(spacing: MacUI.space(16)) { accountLanguageCard; accountAppearanceCard }
            }
            if wide {
                HStack(alignment: .top, spacing: MacUI.space(16)) {
                    accountCurrencyCard
                    accountPostingCard
                }
            } else {
                accountCurrencyCard
                accountPostingCard
            }
            MacSettingsCard(title: L10n.text("mac.settingsView.account.adc826dfd9"), icon: "externaldrive", headerColor: .blue, compactHeader: true) {
                LazyVGrid(columns: wide ? Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 4) : [GridItem(.adaptive(minimum: 230), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                    dataAction(L10n.text("mac.settingsView.dataAction.7e9e370323"), detail: L10n.text("mac.settingsView.dataAction.cdab0ce22e"), icon: "square.and.arrow.down", dangerous: false, button: L10n.text("mac.settingsView.dataAction.6b08cd4a38")) { pageName = MacSettingsPage.backup.id }
                    dataAction(L10n.text("mac.settingsView.dataAction.e86dd4d004"), detail: L10n.text("mac.settingsView.dataAction.2ba394114d"), icon: "square.and.arrow.up", dangerous: false, button: L10n.text("mac.settingsView.dataAction.7cdbe873bb")) { pageName = MacSettingsPage.backup.id }
                    selectiveClearCard
                    dataAction(L10n.text("mac.settingsView.dataAction.b1e4cb77c8"), detail: L10n.text("mac.settingsView.dataAction.98a832c8bc"), icon: "trash", dangerous: true, button: L10n.text("mac.settingsView.dataAction.fa650a299a")) { beginClear() }
                }
            }
        }
    }
    private var accountCurrencyCard: some View {
        MacSettingsCard(title: L10n.text("mac.settingsView.account.5c3b324f5b"), icon: "banknote", headerColor: .blue, compactHeader: true) {
            bookCurrencyRow(wide: false)
            quickSourceRow
            HStack { Spacer(); quickRefreshButton }
            ViewThatFits(in: .horizontal) {
                HStack { manageCurrencyButton; Spacer(); editProfileButton }
                VStack(alignment: .leading, spacing: MacUI.space(10)) { manageCurrencyButton; editProfileButton }
            }.appFont(.caption)
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
    private var accountPostingCard: some View {
            MacSettingsCard(title: L10n.text("mac.settingsView.account.68562b217e"), icon: "calendar.badge.clock", compactHeader: true) {
                MacSettingsToggleRow(title: L10n.text("mac.settingsView.account.608607a7e4"), subtitle: L10n.text("mac.settingsView.account.58c1a52beb"), value: $automaticDeposits)
                MacSettingsToggleRow(title: L10n.text("mac.settingsView.account.ffc8e17b68"), subtitle: L10n.text("mac.settingsView.account.79a0f4bfb4"), value: $automaticPosting).accessibilityIdentifier("automaticPostingToggle")
                Text(L10n.text("mac.settingsView.account.0bda56a369")).appFont(.caption).foregroundStyle(.secondary)
            }
    }
    private func bookCurrencyRow(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(8)) {
            Text(L10n.text("mac.settingsView.bookCurrencyRow.4c99d6925c")).appFont(.body).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 8) {
                MacBookCurrencyChoice(currency: $pendingCurrency)
                if pendingCurrency.uppercased() != baseCurrency && !pendingCurrency.isEmpty {
                    Button(L10n.text("mac.settingsView.bookCurrencyRow.d9c792dfca"), systemImage: "arrow.left.arrow.right") { showRebase = true }
                        .buttonStyle(MacSettingsButtonStyle(height: 44)).accessibilityIdentifier("changeBookCurrency")
                        .disabled((try? MacCurrency.code(pendingCurrency)) == nil)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var quickSourceRow: some View {
        return VStack(alignment: .leading, spacing: MacUI.space(8)) {
            Text(L10n.text("mac.settingsView.quickSourceRow.4c6c9c8d37")).appFont(.body).foregroundStyle(.secondary)
            MacSettingsMenu(selection: Binding(get: { monitor.configuration.accountingSourcePolicy }, set: { value in MacFXApplication.shared.update { $0.accountingSourcePolicy = value } }), options: MacFXSourceSelection.options(current:monitor.configuration.accountingSourcePolicy)).accessibilityIdentifier("accountRateSourceMenu")
            Text(L10n.text("mac.settingsView.quickSourceRow.bc72617429")).appFont(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var manageCurrencyButton: some View {
        Button(L10n.text("mac.settingsView.account.383f58f1e0")) { pageName = MacSettingsPage.currency.id }.accessibilityIdentifier("manageCurrencies")
    }
    private var editProfileButton: some View {
        Button(L10n.text("mac.settingsView.account.2109f74eb1")) { showProfile = true }.accessibilityIdentifier("settingsEditProfile").disabled(currency == nil)
    }
    private var quickRefreshButton: some View {
        Button(refreshing ? L10n.text("mac.settingsView.quickRefreshButton.a0bacec44f") : L10n.text("mac.settingsView.quickRefreshButton.3055a035f0"), systemImage: "arrow.clockwise") { Task { await refreshQuickRate() } }
            .buttonStyle(MacSettingsButtonStyle(height: 40)).disabled(refreshing).accessibilityIdentifier("accountRefreshRates")
    }
    private var selectiveClearCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "trash.square").appIconFont(23).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("mac.settingsView.selectiveClearCard.37ffe16c5b")).appFont(.body, weight: .semibold)
                    Text(L10n.text("mac.settingsView.selectiveClearCard.bab0265e6d")).appFont(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            MacSettingsMenu(selection: $selectedClearKind, options: MacClearKind.allCases.map { (L10n.builtIn($0.rawValue), $0) }).accessibilityIdentifier("selectiveClearKind")
            Spacer(minLength: 0)
            Button { showsSelectiveClear = true } label: { Text(L10n.text("mac.settingsView.selectiveClearCard.5f72fa013e")).frame(maxWidth: .infinity) }.accessibilityIdentifier("selectiveClearOpen")
        }.appPadding(15).frame(maxWidth: .infinity, minHeight: MacUI.space(180), alignment: .topLeading).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.gray.opacity(0.15)))
    }
    private func dataAction(_ title: String, detail: String, icon: String, dangerous: Bool, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(16)) {
            HStack(alignment: .center, spacing: MacUI.space(10)) { Image(systemName: icon).appIconFont(23, weight: .regular, design: .default).foregroundStyle(dangerous ? .red : .primary); VStack(alignment: .leading, spacing: MacUI.space(6)) { Text(title).appFont(.body, weight: .semibold, design: .default); Text(detail).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) } }
            Spacer(minLength: 0)
            Button(role: dangerous ? .destructive : nil, action: action) { Text(button).frame(maxWidth: .infinity) }.accessibilityIdentifier(dangerous ? "clearLocalLedger" : title)
        }.appPadding(15).frame(maxWidth: .infinity, minHeight: MacUI.space(180), alignment: .topLeading).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.gray.opacity(0.15)))
    }
    private func beginClear() { clearStage = multipleClear ? 0 : 1; clearText = ""; showClear = true }
    private func refreshQuickRate() async {
        refreshing = true; defer { refreshing = false }
        let codes: [String] = MacSettingsStore.load("v2_currencies", fallback: [])
        let result = await MacFXService.refreshAll(from:baseCurrency,codes:codes)
        message = result.message; error = result.failureMessage
    }

    private func perform(_ operation: () throws -> Void) { do { try operation(); error = nil } catch { self.error = MacLocalization.error(error) } }

}
