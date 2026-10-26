import SwiftUI
import AppKit

struct MacMenuBarPanel: View {
    @ObservedObject var runtime: MacApplicationRuntime
    @ObservedObject var session: MacMenuBarSession
    @ObservedObject var entries: MacAppEntryController
    @State private var adding = false
    @State private var quickSettings = false
    @ObservedObject private var service = MacFXApplication.shared.monitor
    @ObservedObject private var ledger = MacLedgerAccess.shared
    @AppStorage("color_theme_mode", store: MacPreferences.defaults) private var theme = "system"
    @AppStorage("v2_font_tier", store: MacPreferences.defaults) private var tier = "standard"
    @AppStorage("v2_accent", store: MacPreferences.defaults) private var accent = "terracotta"
    @AppStorage(MacInterfaceZoom.key, store: MacPreferences.defaults) private var zoom = 100
    @AppStorage(MacCustomTypography.bodyKey, store: MacPreferences.defaults) private var bodyPoints = 16
    static func logicalSize(available: CGSize) -> CGSize {
        let factor = MacInterfaceZoom.factor
        let requested = CGFloat(ProcessInfo.processInfo.environment["FINTRACK_MENU_TEST_HEIGHT"].flatMap(Double.init) ?? 720)
        return CGSize(width: min(408 + max(0, MacUI.fontTier.bodySize - 16) * 8, max(1,(available.width - 32) / factor)),
                      height: min(requested, max(1,(available.height - 32) / factor)))
    }
    var body: some View {
        let _ = accent; let _ = zoom; let _ = bodyPoints
        let size = Self.logicalSize(available: runtime.panelWindow?.screen?.visibleFrame.size ?? NSScreen.main?.visibleFrame.size ?? CGSize(width:1280,height:800))
        VStack(spacing: 0) {
            HStack {
                Image(nsImage: FinTrackMacApp.menuIcon)
                Text("FinTrack").appFont(.section, weight: .semibold)
                Spacer()
                HStack(spacing:4) {
                    if session.page != .quickEntry {
                        tool("plus",title:session.page == .rates ? "添加货币对" : "添加换算币种",identifier:session.page == .rates ? "fxAddPair" : "fxAddCurrency") { adding = true }
                            .popover(isPresented:$adding) {
                                Group {
                                    if session.page == .rates { MacFXPairPicker { _ in adding = false } }
                                    else { MacFXCurrencyPicker(service:service) { adding = false } }
                                }.interfaceZoom()
                            }
                        tool("arrow.clockwise",title:"更新汇率",identifier:session.page == .rates ? "fxUpdateRates" : "fxConverterUpdate") { Task { await service.refresh(reason:.manual) } }
                            .disabled(service.busy).appHelp(service.busy ? "正在更新…" : service.status)
                    }
                    tool("gearshape",title:"设置",identifier:"menuSettings") { quickSettings.toggle() }
                }
            }.padding(.horizontal, 18).padding(.top, 8)
            HStack(spacing: 4) {
                ForEach(MacMenuBarPage.allCases) { page in
                    Button { session.page = page } label: {
                        Label(page.title, systemImage: page.symbol).appFont(.label, weight: .medium)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(session.page == page ? MacUI.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
                    }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("menuPage-" + page.rawValue).accessibilityValue(session.page == page ? "已选中" : "未选中")
                }
            }.padding(.horizontal, 14).padding(.bottom, 12)
            Divider()
            Group {
                if quickSettings {
                    MacMenuQuickSettings(service:service,runtime:runtime,canManageCategories:ledger.container != nil) { quickSettings = false }
                } else { switch session.page {
                case .rates: MacFXRatesView(service: MacFXApplication.shared.monitor, query: MacFXApplication.shared.query, showsTools: false)
                case .converter: MacFXConverterView(service: MacFXApplication.shared.monitor, query: MacFXApplication.shared.query, showsTools: false)
                case .quickEntry: quickEntry
                } }
            }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(session.page == .quickEntry ? MacOverviewStyle.card : .clear)

        }.frame(width: size.width, height: size.height).background(MacOverviewStyle.canvas).tint(MacUI.accent)
            .accessibilityElement(children: .contain).accessibilityIdentifier("menuPanelContent")
            .background(MacMenuBarWindowProbe { runtime.panelWindow = $0 })
            .background(MacMenuPanelKeyboard { if quickSettings { quickSettings = false } else { runtime.closePanel() } })
            .preferredColorScheme(theme == "dark" ? .dark : theme == "light" ? .light : nil)
            .defaultAppStorage(MacPreferences.defaults).interfaceZoom()
            .onAppear { if session.page == .quickEntry { ledger.load() } }
            .onChange(of: session.page) { _, page in adding = false; quickSettings = false; if page == .quickEntry { ledger.load() } }
    }
    private func tool(_ symbol:String,title:String,identifier:String,action:@escaping () -> Void) -> some View {
        Button(action:action) { Image(systemName:symbol).appIconFont(22).frame(width:40,height:40).contentShape(Rectangle()) }
            .buttonStyle(MacInteractiveButtonStyle()).accessibilityLabel(title).accessibilityIdentifier(identifier)
    }
    @ViewBuilder private var quickEntry: some View {
        if let container = ledger.container {
            MacQuickEntryView(draft: session.quickEntry, runtime: runtime).modelContainer(container)
        } else {
            VStack(spacing: 18) {
                Image(systemName: "square.and.pencil").appIconFont(40).foregroundStyle(MacUI.accent)
                Text("快速记账").appFont(.section, weight:.semibold)
                Text("尚未打开账本，请先在主窗口设置记账。").appFont(.body, weight:.regular).foregroundStyle(.secondary)
                Button("打开主窗口") { runtime.showMain() }.buttonStyle(MacSettingsButtonStyle(height:40))
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }
    }
}
