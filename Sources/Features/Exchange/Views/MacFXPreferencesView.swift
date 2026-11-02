import SwiftUI

struct MacFXReferenceField: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @ObservedObject private var service = MacFXApplication.shared.monitor
    @State private var reference = "USD"
    @State private var custom = false
    @State private var error: String?
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Text(L10n.text("mac.fXPreferencesView.body.c46ad6bba1")).appFont(.body).foregroundStyle(.secondary)
                Spacer(minLength:12)
                MacEditableCurrencyMenu(currency:Binding(get:{reference},set:{ value in reference = value; if !custom { apply() } }),custom:$custom,codes:MacFXCatalog.codes,identifier:"fxReferenceCurrency",textIdentifier:"fxReferenceCustom")
            }
            if custom {
                HStack {
                    Text(L10n.text("mac.fXPreferencesView.body.d350106e7a")).appFont(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.text("mac.fXPreferencesView.body.63c73c4730"),action:apply).buttonStyle(MacSettingsButtonStyle(height:40))
                        .disabled((try? MacFXPair(base:reference,quote:reference)) == nil).accessibilityIdentifier("fxReferenceApply")
                }
            }
            if let error { Text(error).appFont(.caption).foregroundStyle(.red) }
        }.onAppear { reference = service.configuration.referenceCurrency }
            .onChange(of:service.configuration.referenceCurrency) { _,value in if !custom { reference = value } }
    }
    private func apply() {
        do { try MacFXApplication.shared.setReferenceCurrency(reference); reference = service.configuration.referenceCurrency; custom = false; error = nil }
        catch { self.error = L10n.text("mac.fXPreferencesView.apply.159aeeb049") }
    }
}

struct MacFXPreferencesView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    enum Section { case all, display, source }
    var section: Section = .all
    var includeDirectoryAndSources = true
    var includeDisplayLists = true
    @ObservedObject private var service = MacFXApplication.shared.monitor
    @State private var interval = "30"
    @State private var openAge = "10"
    @State private var message: String?
    @State private var newCode = ""
    @State private var availableWidth: CGFloat = 0
    private var app: MacFXApplication { .shared }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            if section != .source {
                let layout = availableWidth >= 900 ? AnyLayout(HStackLayout(alignment:.top,spacing:16)) : AnyLayout(VStackLayout(spacing:16))
                VStack(spacing:0) { layout { displayCard; refreshCard } }.frame(maxWidth:.infinity)
                    .onGeometryChange(for:CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            }
            if section != .display {
                MacSettingsCard(title:L10n.text("mac.fXPreferencesView.body.85c5887b9a"),icon:"network",subtitle:L10n.text("mac.fXPreferencesView.body.2f40e205de")) {
                    MacSettingsRow(label:L10n.text("mac.fXPreferencesView.body.036f077540")) { MacSettingsMenu(selection:binding(\.sourcePolicy),options:sourceOptions).frame(maxWidth:320).accessibilityIdentifier("fxMonitorSource") }
                }.accessibilityElement(children:.contain).accessibilityIdentifier("fxSourcePolicyCard")
            }
            if section == .all {
                if includeDisplayLists { MacFXDisplaySettings() }
                if includeDirectoryAndSources {
                    MacSettingsCard(title:L10n.text("mac.fXPreferencesView.body.441d6be316"),icon:"banknote") {
                        Text(MacFXCatalog.codes.joined(separator:"  ·  ")).appFont(.body)
                        HStack {
                            TextField(L10n.text("mac.fXPreferencesView.body.9c93a343d0"),text:$newCode).accessibilityIdentifier("fxDirectoryCode")
                            Button(L10n.text("mac.fXPreferencesView.body.7a8a11ead5")) {
                                do { let code = try MacFXPair(base:newCode,quote:newCode).base; try MacSettingsStore.save(MacFXCatalog.codes.contains(code) ? MacFXCatalog.codes : MacFXCatalog.codes + [code],key:"v2_currencies"); app.reload(); newCode = "" }
                                catch { message = L10n.text("mac.fXPreferencesView.body.24425bb427") }
                            }
                        }
                    }
                    MacFXSourceManagementCard()
                }
            }
            if let message { Text(message).appFont(.caption).foregroundStyle(.orange) }
            if let error = app.settingsError { Text(error).appFont(.caption).foregroundStyle(.red) }
        }.onAppear { interval = String(service.configuration.intervalMinutes); openAge = String(service.configuration.openMaxAgeMinutes) }
            .onChange(of:service.configuration.intervalMinutes) { _,value in interval = String(value) }
            .onChange(of:service.configuration.openMaxAgeMinutes) { _,value in openAge = String(value) }
    }
    private var displayCard: some View {
        MacSettingsCard(title:L10n.text("mac.fXPreferencesView.displayCard.51a57ea50f"),icon:"number",subtitle:L10n.text("mac.fXPreferencesView.displayCard.9d937b199d")) {
                    MacFXReferenceField()
                    Divider().padding(.vertical,3)
                    MacSettingsRow(label:L10n.text("mac.fXPreferencesView.displayCard.d3fcc30761")) { MacSettingsMenu(selection:binding(\.displayUnits),options:[(L10n.text("mac.fXPreferencesView.MacSettingsMenu.741dcea7b4"),1),(L10n.text("mac.fXPreferencesView.MacSettingsMenu.b6e384046e"),100)]).frame(width:220).accessibilityIdentifier("fxSettingsUnits") }
                    MacSettingsRow(label:L10n.text("mac.fXPreferencesView.displayCard.dfb79c3df3")) { MacSettingsMenu(selection:binding(\.rateDigits),options:[2,4,6].map { (L10n.format("mac.fXPreferencesView.MacSettingsMenu.5949d8677d", "\($0)"),$0) }).frame(width:220).accessibilityIdentifier("fxRateDigits") }
                    Text(L10n.text("mac.fXPreferencesView.displayCard.beb4d7fd6e")).appFont(.caption).foregroundStyle(.secondary)
                }.accessibilityElement(children:.contain).accessibilityIdentifier("fxDisplayPreferencesCard")
    }
    private var refreshCard: some View {
        MacSettingsCard(title:L10n.text("mac.fXPreferencesView.refreshCard.df36a521ea"),icon:"arrow.clockwise",subtitle:L10n.text("mac.fXPreferencesView.refreshCard.fbcb2a331a")) {
                    MacSettingsToggleRow(title:L10n.text("mac.fXPreferencesView.refreshCard.98073e15fa"),value:binding(\.automatic)).accessibilityIdentifier("fxAutomatic")
                    if service.configuration.automatic {
                        minutesRow(L10n.text("mac.fXPreferencesView.minutesRow.100107ffb5"),text:$interval,suffix:L10n.text("mac.fXPreferencesView.minutesRow.a9e980cc7b"),identifier:"fxIntervalMinutes",button:"fxApplyInterval",apply:{ applyMinutes(interval,key:\.intervalMinutes) })
                        Text(L10n.text("mac.fXPreferencesView.refreshCard.5228103171")).appFont(.caption).foregroundStyle(.secondary)
                    }
                    Divider().padding(.vertical,5)
                    MacSettingsToggleRow(title:L10n.text("mac.fXPreferencesView.refreshCard.5dd20feabb"),subtitle:L10n.text("mac.fXPreferencesView.refreshCard.89a41faef3"),value:binding(\.refreshOnOpen)).accessibilityIdentifier("fxRefreshOnOpen")
                    if service.configuration.refreshOnOpen {
                        minutesRow(L10n.text("mac.fXPreferencesView.minutesRow.798372e62d"),text:$openAge,suffix:L10n.text("mac.fXPreferencesView.minutesRow.a358e5b4d6"),identifier:"fxOpenAgeMinutes",button:"fxApplyOpenAge",apply:{ applyMinutes(openAge,key:\.openMaxAgeMinutes) })
                    }
                    Text(service.configuration.automatic ? L10n.text("mac.fXPreferencesView.refreshCard.a1c2988870") : L10n.text("mac.fXPreferencesView.refreshCard.40f3b45246")).appFont(.caption).foregroundStyle(.secondary)
                }.accessibilityElement(children:.contain).accessibilityIdentifier("fxRefreshPreferencesCard")
    }
    private func minutesRow(_ label:String,text:Binding<String>,suffix:String,identifier:String,button:String,apply:@escaping ()->Void) -> some View {
        HStack(spacing:10) {
            Text(label)
            TextField(L10n.text("mac.fXPreferencesView.minutesRow.bd957bc497"),text:text).frame(width:76).accessibilityIdentifier(identifier)
            Text(suffix)
            Spacer(minLength:8)
            Button(L10n.text("mac.fXPreferencesView.minutesRow.63c73c4730"),action:apply).buttonStyle(MacSettingsButtonStyle(height:40)).accessibilityIdentifier(button)
        }.appFont(.body)
    }
    private var sourceOptions: [(String,String)] {
        MacFXSourceSelection.options(current:service.configuration.sourcePolicy)
    }
    private func binding<T>(_ key:WritableKeyPath<MacFXConfiguration,T>) -> Binding<T> {
        Binding(get:{service.configuration[keyPath:key]},set:{ value in DispatchQueue.main.async { app.update { $0[keyPath:key] = value } } })
    }
    private func applyMinutes(_ text:String,key:WritableKeyPath<MacFXConfiguration,Int>) {
        guard let number = Int(text), (1...1440).contains(number) else { message = L10n.text("mac.fXPreferencesView.applyMinutes.fc10ecd8eb"); return }
        app.update { $0[keyPath:key] = number }; message = nil
    }
}

struct MacFXSourceManagementCard: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @AppStorage("v2_fx_sources", store: MacPreferences.defaults) private var bytes = Data()
    @State private var editing: MacFXSource?
    @State private var removing: MacFXSource?
    @State private var error: String?
    private var sources: [MacFXSource] { (try? JSONDecoder().decode([MacFXSource].self, from: bytes)) ?? [] }
    var body: some View {
        MacSettingsCard(title: L10n.text("mac.fXPreferencesView.body.b5c934c94d"), icon: "network", action: AnyView(Button(L10n.text("mac.fXPreferencesView.AnyView.ae3676ce6b"), systemImage: "plus") { editing = MacFXTemplate.twelveData.source() }.accessibilityIdentifier("settingsFXAdd"))) {
            Label(L10n.text("mac.fXPreferencesView.body.2bd0af2f71"), systemImage: "globe").appFont(.body, weight: .medium)
            ForEach(sources) { source in
                HStack {
                    MacFXSourceImage(source: source, size: 30)
                    Button(source.name) { editing = source }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("settingsFXSource-" + source.name)
                    Spacer()
                    Toggle(L10n.text("mac.fXPreferencesView.ForEach.f4f0ead111") + source.name, isOn: Binding(get: { source.enabled }, set: { enabled in
                        var values = sources; if let index = values.firstIndex(where: { $0.id == source.id }) { values[index].enabled = enabled }
                        do { try MacSettingsStore.save(values, key: "v2_fx_sources"); MacFXApplication.shared.reload() } catch { self.error = error.localizedDescription }
                    })).labelsHidden().toggleStyle(.switch).accessibilityIdentifier("fxEnable-" + source.name)
                    Button(L10n.text("mac.fXPreferencesView.ForEach.2f9daa8289"), role: .destructive) { removing = source }
                }.frame(minHeight: 40)
            }
            if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red) }
        }
        .sheet(item: $editing) { MacFXSourceEditor(source: $0, from: "USD", to: "CNY") }
        .alert(L10n.text("mac.fXPreferencesView.body.ce6d2a9642"), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(L10n.text("mac.fXPreferencesView.body.2cd0f3be87"), role: .cancel) { removing = nil }
            Button(L10n.text("mac.fXPreferencesView.body.2f9daa8289"), role: .destructive) { if let source = removing { Task {do{try await MacFXService.removeAsync(source);MacFXApplication.shared.reload();removing=nil}catch{self.error=error.localizedDescription}} } }
        } message: { Text(L10n.text("mac.fXPreferencesView.body.85789ca171")) }
    }
}
