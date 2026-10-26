import SwiftUI

struct MacMenuQuickSettings: View {
    @ObservedObject var service: MacFXMonitor
    let runtime: MacApplicationRuntime
    let canManageCategories: Bool
    var close: () -> Void
    @State private var interval = ""
    @State private var error: String?
    @AppStorage("v2_fx_sources",store:MacPreferences.defaults) private var sources = Data()
    private var app: MacFXApplication { .shared }
    var body: some View {
        VStack(spacing:12) {
            HStack {
                Text("菜单栏设置").appFont(.section,weight:.semibold)
                Spacer()
                Button(action:close) { Image(systemName:"xmark").frame(width:28,height:28) }.buttonStyle(MacInteractiveButtonStyle()).accessibilityLabel("关闭快速设置").accessibilityIdentifier("menuQuickSettingsDone")
            }
            ScrollView {
                VStack(spacing:10) {
                    row("菜单栏来源") { MacSettingsMenu(selection:binding(\.sourcePolicy),options:sourceOptions).accessibilityIdentifier("fxMonitorSource") }
                    if service.configuration.sourcePolicy == "auto" { Text("按已启用的自定义源顺序尝试，系统数据源兜底。").appFont(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                    Button("API与密钥设置…",systemImage:"key") { MacFXApplication.shared.query.settingsSectionRequest = "数据源"; openSettings("currency") }
                        .buttonStyle(MacInteractiveButtonStyle()).foregroundStyle(MacUI.accent).frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("menuAPISettings")
                    row("显示单位") { MacSettingsMenu(selection:binding(\.displayUnits),options:[("1单位",1),("100单位",100)]).accessibilityIdentifier("fxSettingsUnits") }
                    row("小数位数") { MacSettingsMenu(selection:binding(\.rateDigits),options:[2,4,6].map { ("\($0)位小数",$0) }).accessibilityIdentifier("fxRateDigits") }
                    HStack { Text("自动刷新"); Spacer(); Toggle("自动刷新",isOn:binding(\.automatic)).labelsHidden().toggleStyle(.switch).accessibilityIdentifier("fxAutomatic") }.appFont(.body,weight:.regular).frame(minHeight:40)
                    HStack { Text("打开时更新"); Spacer(); Toggle("打开时更新", isOn: binding(\.refreshOnOpen)).labelsHidden().toggleStyle(.switch).accessibilityIdentifier("fxRefreshOnOpen") }.frame(minHeight: 40)
                    if service.configuration.refreshOnOpen { Text("缓存超过 \(service.configuration.openMaxAgeMinutes) 分钟时更新").appFont(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                    HStack(spacing:8) {
                        Text("间隔").appFont(.body,weight:.regular)
                        TextField("分钟",text:$interval).textFieldStyle(MacSettingsFieldStyle()).frame(width:70).accessibilityIdentifier("fxIntervalMinutes").onSubmit(applyInterval)
                        Text("分钟").appFont(.caption,weight:.regular)
                        Spacer(minLength:0)
                        Button("应用",action:applyInterval).buttonStyle(MacSettingsButtonStyle(height:40)).accessibilityIdentifier("fxApplyInterval")
                    }
                    if let error { Text(error).appFont(.caption,weight:.regular).foregroundStyle(.red).accessibilityIdentifier("fxIntervalError") }
                    Text(service.status).appFont(.caption,weight:.regular).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("menuRefreshStatus")
                }
            }.frame(minHeight:80,maxHeight:.infinity).accessibilityIdentifier("menuQuickSettingsScroll")
            Divider()
            Grid(horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Button("管理分类", systemImage: "tag") { openSettings("categories") }.disabled(!canManageCategories).accessibilityIdentifier("menuManageCategories").frame(maxWidth: .infinity, alignment: .leading)
                    Button("全部设置", systemImage: "gearshape") { openSettings("general") }.accessibilityIdentifier("menuAllSettings").frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow {
                    Button("打开主窗口", systemImage: "macwindow") { close(); runtime.showMain() }.accessibilityIdentifier("menuOpenMain").frame(maxWidth: .infinity, alignment: .leading)
                    Button("退出 FinTrack", systemImage: "power", role: .destructive) { NSApp.terminate(nil) }.accessibilityIdentifier("menuQuit").frame(maxWidth: .infinity, alignment: .leading)
                }
            }.labelStyle(MacMenuActionLabelStyle()).frame(minHeight: 80)
        }.buttonStyle(MacInteractiveButtonStyle()).appFont(.body,weight:.regular).padding(16).frame(maxWidth:.infinity,maxHeight:.infinity)
            .onAppear { interval = String(service.configuration.intervalMinutes) }
            .onChange(of:service.configuration.intervalMinutes) { _, value in interval = String(value) }
            .onExitCommand(perform:close)
    }
    private var sourceOptions: [(String,String)] {
        let _ = sources
        return MacFXSourceSelection.options(current:service.configuration.sourcePolicy, includeAutomatic: true)
    }
    private func row<Content:View>(_ title:String,@ViewBuilder content:() -> Content) -> some View {
        HStack(spacing:10) { Text(title).appFont(.body,weight:.regular).frame(width:88,alignment:.leading); content() }
    }
    private func binding<T>(_ key:WritableKeyPath<MacFXConfiguration,T>) -> Binding<T> {
        Binding(get:{service.configuration[keyPath:key]},set:{value in app.update { $0[keyPath:key] = value }})
    }
    private func applyInterval() {
        guard let value = Int(interval), (1...1440).contains(value) else { error = "请输入1–1440分钟"; return }
        app.update { $0.intervalMinutes = value }; error = nil
    }
    private func openSettings(_ page:String) { MacPreferences.defaults.set(page,forKey:"v2_settings_page"); close(); runtime.showMain(settings:true) }
}

private struct MacMenuActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 9) { configuration.icon.frame(width: 20, alignment: .center); configuration.title }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).contentShape(Rectangle())
    }
}
