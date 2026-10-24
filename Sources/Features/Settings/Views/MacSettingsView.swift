import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

enum MacSettingsPage: String, CaseIterable, Identifiable {
    case account = "账户与偏好", currency = "货币与汇率", categories = "分类管理", budgets = "预算设置", goals = "目标管理"
    case backup = "数据备份与导出", appearance = "外观与语言", general = "通用设置", about = "关于 FinTrack"
    var id: String { String(describing: self) }
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
        case .account: "管理个人资料、账本与常用偏好。"
        case .currency: "通用货币、记账汇率与菜单栏汇率分别管理。"
        case .categories: "统一管理记账、周期规则和统计使用的收支分类。"
        case .budgets: "按月设置总预算与分类预算，跟踪实际支出。"
        case .goals: "基于净资产追踪财务目标，集中管理进度与状态。"
        case .backup: "手动创建完整备份、恢复账本及导入导出 CSV。"
        case .appearance: "调整主题、强调色与界面显示偏好。"
        case .general: "管理日期、金额、列表及应用行为。"
        case .about: "应用信息、版本更新与项目链接。"
        }
    }
}

struct MacSettingsView: View {
    @Binding var previewCurrency: String
    @AppStorage("v2_font_tier", store: MacPreferences.defaults) private var fontTierValue = MacFontSizeTier.standard.rawValue
    @Environment(\.modelContext) private var context
    @AppStorage("v2_settings_page") private var pageName = "account"
    @AppStorage("base_currency") private var baseCurrency = "USD"
    @AppStorage("v2_display_name") private var displayName = "我的账本"
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
        GeometryReader { geometry in
            let compactMenu = geometry.size.width < MacUI.space(900)
            let menuWidth: CGFloat = geometry.size.width < MacUI.space(850) ? MacUI.space(190) : MacUI.space(230)
            HStack(spacing: MacUI.space(0)) {
                if !compactMenu { navigation.frame(width: menuWidth); Divider() }
                let contentWidth = geometry.size.width - (compactMenu ? 0 : menuWidth) - 44
                let minimumColumn: CGFloat = fontTierValue == "large" ? 460 : 420
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
                Label("清空全部账本数据", systemImage: "exclamationmark.triangle.fill").appFont(.dialogTitle, weight: .semibold).foregroundStyle(.red)
                Text("将删除所有账目、存款、贷款、周期规则、分类、目标与预算。请先手动创建完整备份。")
                if clearStage == 0 {
                    HStack { Button("取消") { showClear = false }; Spacer(); Button("继续确认", role: .destructive) { clearStage = 1 }.accessibilityIdentifier("clearContinue") }
                } else {
                    Text("输入“清空账本”完成最终确认。此操作无法撤销。")
                    TextField("清空账本", text: $clearText).accessibilityIdentifier("clearConfirmationText")
                    HStack {
                        Button("取消") { showClear = false }
                        Spacer()
                        Button("永久清空", role: .destructive) {
                            perform {
                                try MacDataManagement.clearLedger(in: context)
                                try MacSettingsStore.save([MacBudget](), key: "v2_budgets")
                                MacNotifications.clear(); MacSettingsStore.defaults.set(false, forKey: "fintrack_auto_posting")
                                showClear = false; message = "账本数据已清空"
                            }
                        }.disabled(clearText != "清空账本").accessibilityIdentifier("clearFinalConfirm")
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
                        Button(item.rawValue, systemImage: item.icon) { pageName = item.id }.accessibilityIdentifier("settingsNav-" + item.id)
                    }
                } label: { HStack { Text("设置页面").foregroundStyle(.secondary); Text(page.rawValue); Spacer(); Image(systemName: "chevron.down") } }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).appFormControl().accessibilityIdentifier("settingsPageMenu")
            }
            VStack(alignment: .leading, spacing: MacUI.space(7)) {
                HStack { Text(page.rawValue).appFont(.pageTitle, weight: .bold, design: .default).accessibilityIdentifier("settingsPageTitle"); if MacSettingsVisual.preview { Text("演示").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).appPadding(.horizontal, 7).appPadding(.vertical, 3).background(.gray.opacity(0.06), in: Capsule()) }; Spacer() }
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
                        Text(item.rawValue).appFont(.body, weight: item == page ? .semibold : .regular, design: .default)
                        Spacer(minLength: 0)
                    }.appPadding(.horizontal, 12).appMinHeight(47)
                        .foregroundStyle(item == page ? MacSettingsVisual.accent : .primary)
                        .background(item == page ? MacSettingsVisual.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("settingsNav-" + item.id)
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
        MacSettingsCard(title: "语言与日期", icon: "globe", headerColor: .blue, compactHeader: true) {
            MacSettingsRow(label: "界面语言", labelWidth: 100) { MacLanguageChoice() }
            MacSettingsRow(label: "一周开始于", labelWidth: 100) {
                MacSettingsMenu(selection: $weekStart, options: [("星期一",2), ("星期日",1)]).accessibilityIdentifier("accountWeekStartMenu")
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("accountLanguageCard")
    }
    private var accountAppearanceCard: some View {
        MacSettingsCard(title: "外观", icon: "paintpalette", headerColor: .blue, compactHeader: true) {
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
                    TextField("账本名称", text: $displayName).appFont(.dialogTitle, weight: .bold, design: .default).textFieldStyle(.plain).accessibilityIdentifier("settingsDisplayName")
                    Text("个人财务管理").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                }
                Spacer()
                MacImageImportControl(data: $avatar, title: "更换头像", cropTitle: "裁切头像", label: "头像", circularPreview: true, identifier: "settingsAvatar")
            }.appPadding(22).background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 13))
            MacSettingsColumns(wide: wide) {
                accountLanguageCard
            } right: {
                accountAppearanceCard
            }
            MacSettingsCard(title: "货币与汇率", icon: "banknote", headerColor: .blue, compactHeader: true) {
                if wide {
                    HStack(alignment: .top, spacing: MacUI.space(20)) {
                        bookCurrencyRow(wide: true).frame(maxWidth: .infinity)
                        quickSourceRow.frame(maxWidth: .infinity)
                        quickRefreshButton
                    }
                } else {
                    VStack(alignment: .leading, spacing: MacUI.space(12)) { bookCurrencyRow(wide: false); quickSourceRow; HStack { Spacer(); quickRefreshButton } }
                }
                HStack { Button("管理货币与汇率") { pageName = MacSettingsPage.currency.id }.accessibilityIdentifier("manageCurrencies"); Spacer(); Button("编辑初始资产与负债") { showProfile = true }.accessibilityIdentifier("settingsEditProfile").disabled(currency == nil) }.appFont(.caption, weight: .regular, design: .default)
            }
            MacSettingsCard(title: "数据备份与导出", icon: "externaldrive", headerColor: .blue, compactHeader: true) {
                LazyVGrid(columns: wide ? Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 4) : [GridItem(.adaptive(minimum: 230), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                    dataAction("创建完整备份", detail: "将所有应用数据保存为单个文件\n（可用于恢复）", icon: "square.and.arrow.down", dangerous: false, button: "选择备份位置…") { pageName = MacSettingsPage.backup.id }
                    dataAction("导出数据", detail: "导出为 CSV 格式\n（用于查看和交换数据）", icon: "square.and.arrow.up", dangerous: false, button: "选择导出内容…") { pageName = MacSettingsPage.backup.id }
                    selectiveClearCard
                    dataAction("清空所有数据", detail: "此操作不可恢复\n请提前备份并谨慎操作", icon: "trash", dangerous: true, button: "清空数据") { beginClear() }
                }
            }
            MacSettingsCard(title: "计划入账", icon: "calendar.badge.clock", compactHeader: true) {
                MacSettingsToggleRow(title: "存款到期自动记账", subtitle: "按计划金额记为待核对收入，可在存款详情确认实际到账。", value: $automaticDeposits)
                MacSettingsToggleRow(title: "周期与贷款自动记账", subtitle: "仅处理已启用且已核对的规则。", value: $automaticPosting).accessibilityIdentifier("automaticPostingToggle")
                Text("应用运行时每 5 分钟检查；关闭期间的到期计划在下次打开主窗口后补记，不会连接银行核实到账。").appFont(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func bookCurrencyRow(wide: Bool) -> some View {
        MacSettingsRow(label: "默认货币", labelWidth: 80) {
            HStack(alignment: .top, spacing: 8) {
                MacBookCurrencyChoice(currency: $pendingCurrency)
                if pendingCurrency.uppercased() != baseCurrency && !pendingCurrency.isEmpty {
                    Button("换算", systemImage: "arrow.left.arrow.right") { showRebase = true }
                        .buttonStyle(MacSettingsButtonStyle(height: 44)).accessibilityIdentifier("changeBookCurrency")
                        .disabled((try? MacCurrency.code(pendingCurrency)) == nil)
                }
            }
        }
    }
    private var quickSourceRow: some View {
        return VStack(alignment: .leading, spacing: MacUI.space(8)) {
            MacSettingsRow(label: "记账汇率来源", labelWidth: 110) { MacSettingsMenu(selection: Binding(get: { monitor.configuration.accountingSourcePolicy }, set: { value in MacFXApplication.shared.update { $0.accountingSourcePolicy = value } }), options: MacFXSourceSelection.options(current:monitor.configuration.accountingSourcePolicy), minimumWidth: 260).accessibilityIdentifier("accountRateSourceMenu") }
            Text("获取交易日期的参考汇率").appFont(.caption).foregroundStyle(.secondary).appPadding(.leading,124)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var quickRefreshButton: some View {
        Button(refreshing ? "更新中…" : "更新", systemImage: "arrow.clockwise") { Task { await refreshQuickRate() } }
            .buttonStyle(MacSettingsButtonStyle(height: 40)).disabled(refreshing).accessibilityIdentifier("accountRefreshRates")
    }
    private var selectiveClearCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "trash.square").appIconFont(23).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text("按类别删除").appFont(.body, weight: .semibold)
                    Text("预览范围后确认，其他数据保留").appFont(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            MacSettingsMenu(selection: $selectedClearKind, options: MacClearKind.allCases.map { ($0.rawValue, $0) }).accessibilityIdentifier("selectiveClearKind")
            Spacer(minLength: 0)
            Button { showsSelectiveClear = true } label: { Text("预览删除范围…").frame(maxWidth: .infinity) }.accessibilityIdentifier("selectiveClearOpen")
        }.appPadding(15).frame(maxWidth: .infinity, minHeight: MacUI.space(180), alignment: .topLeading).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.gray.opacity(0.15)))
    }
    private func dataAction(_ title: String, detail: String, icon: String, dangerous: Bool, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: MacUI.space(16)) {
            HStack(alignment: .top, spacing: MacUI.space(10)) { Image(systemName: icon).appIconFont(23, weight: .regular, design: .default).foregroundStyle(dangerous ? .red : .primary); VStack(alignment: .leading, spacing: MacUI.space(6)) { Text(title).appFont(.body, weight: .semibold, design: .default); Text(detail).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) } }
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
