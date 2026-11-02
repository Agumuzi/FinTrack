import SwiftUI

struct MacMenuQuickSettings: View {
    @ObservedObject private var localizationState = LocalizationController.shared
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
                Text(L10n.text("mac.menuQuickSettings.body.d815db81b1")).appFont(.section,weight:.semibold)
                Spacer()
                Button(action:close) { Image(systemName:"xmark").frame(width:28,height:28) }.buttonStyle(MacInteractiveButtonStyle()).accessibilityLabel(L10n.text("mac.menuQuickSettings.body.61720bd410")).accessibilityIdentifier("menuQuickSettingsDone")
            }
            ScrollView {
                VStack(spacing:10) {
                    row(L10n.text("mac.menuQuickSettings.row.424c81e714")) { MacSettingsMenu(selection:binding(\.sourcePolicy),options:sourceOptions).accessibilityIdentifier("fxMonitorSource") }
                    if service.configuration.sourcePolicy == "auto" { Text(L10n.text("mac.menuQuickSettings.ScrollView.698fa1f6f9")).appFont(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                    Button(L10n.text("mac.menuQuickSettings.ScrollView.c23b6476d5"),systemImage:"key") { MacFXApplication.shared.query.settingsSectionRequest = L10n.text("mac.menuQuickSettings.ScrollView.186be2232e"); openSettings("currency") }
                        .buttonStyle(MacInteractiveButtonStyle()).foregroundStyle(MacUI.accent).frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("menuAPISettings")
                    row(L10n.text("mac.menuQuickSettings.row.7f92957e2e")) { MacSettingsMenu(selection:binding(\.displayUnits),options:[(L10n.text("mac.menuQuickSettings.MacSettingsMenu.741dcea7b4"),1),(L10n.text("mac.menuQuickSettings.MacSettingsMenu.b6e384046e"),100)]).accessibilityIdentifier("fxSettingsUnits") }
                    row(L10n.text("mac.menuQuickSettings.row.65b867f406")) { MacSettingsMenu(selection:binding(\.rateDigits),options:[2,4,6].map { (L10n.format("mac.menuQuickSettings.MacSettingsMenu.5949d8677d", "\($0)"),$0) }).accessibilityIdentifier("fxRateDigits") }
                    HStack { Text(L10n.text("mac.menuQuickSettings.ScrollView.98073e15fa")); Spacer(); Toggle(L10n.text("mac.menuQuickSettings.ScrollView.98073e15fa"),isOn:binding(\.automatic)).labelsHidden().toggleStyle(.switch).accessibilityIdentifier("fxAutomatic") }.appFont(.body,weight:.regular).frame(minHeight:40)
                    HStack { Text(L10n.text("mac.menuQuickSettings.ScrollView.cbea4f27c3")); Spacer(); Toggle(L10n.text("mac.menuQuickSettings.ScrollView.cbea4f27c3"), isOn: binding(\.refreshOnOpen)).labelsHidden().toggleStyle(.switch).accessibilityIdentifier("fxRefreshOnOpen") }.frame(minHeight: 40)
                    if service.configuration.refreshOnOpen { Text(L10n.format("mac.menuQuickSettings.ScrollView.a1d3840499", "\(service.configuration.openMaxAgeMinutes)")).appFont(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                    HStack(spacing:8) {
                        Text(L10n.text("mac.menuQuickSettings.ScrollView.4f5df723d9")).appFont(.body,weight:.regular)
                        TextField(L10n.text("mac.menuQuickSettings.ScrollView.bd957bc497"),text:$interval).textFieldStyle(MacSettingsFieldStyle()).frame(width:70).accessibilityIdentifier("fxIntervalMinutes").onSubmit(applyInterval)
                        Text(L10n.text("mac.menuQuickSettings.ScrollView.bd957bc497")).appFont(.caption,weight:.regular)
                        Spacer(minLength:0)
                        Button(L10n.text("mac.menuQuickSettings.ScrollView.63c73c4730"),action:applyInterval).buttonStyle(MacSettingsButtonStyle(height:40)).accessibilityIdentifier("fxApplyInterval")
                    }
                    if let error { Text(error).appFont(.caption,weight:.regular).foregroundStyle(.red).accessibilityIdentifier("fxIntervalError") }
                    Text(service.status).appFont(.caption,weight:.regular).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("menuRefreshStatus")
                }
            }.frame(minHeight:80,maxHeight:.infinity).accessibilityIdentifier("menuQuickSettingsScroll")
            Divider()
            Grid(horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Button(L10n.text("mac.menuQuickSettings.GridRow.ee46fd8708"), systemImage: "tag") { openSettings("categories") }.disabled(!canManageCategories).accessibilityIdentifier("menuManageCategories").frame(maxWidth: .infinity, alignment: .leading)
                    Button(L10n.text("mac.menuQuickSettings.GridRow.daab6a438b"), systemImage: "gearshape") { openSettings("general") }.accessibilityIdentifier("menuAllSettings").frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow {
                    Button(L10n.text("mac.menuQuickSettings.GridRow.f6b64b637b"), systemImage: "macwindow") { close(); runtime.showMain() }.accessibilityIdentifier("menuOpenMain").frame(maxWidth: .infinity, alignment: .leading)
                    Button(L10n.text("mac.menuQuickSettings.GridRow.5b1883330c"), systemImage: "power", role: .destructive) { NSApp.terminate(nil) }.accessibilityIdentifier("menuQuit").frame(maxWidth: .infinity, alignment: .leading)
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
        guard let value = Int(interval), (1...1440).contains(value) else { error = L10n.text("mac.menuQuickSettings.applyInterval.fc10ecd8eb"); return }
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
