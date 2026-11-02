import SwiftUI

enum MacFXSourceSelection {
    static func options(current:String, includeAutomatic: Bool = false) -> [(String,String)] {
        var values = (includeAutomatic ? [(L10n.text("mac.fXSourceSelection.values.7eb336e42c"), "auto")] : []) + [(L10n.text("mac.fXSourceSelection.values.2ea759ff20"),"free")] + MacFXService.sources.filter(\.enabled).map { (L10n.text("mac.fXSourceSelection.values.ab18f1b3de") + $0.name,$0.id.uuidString) }
        if !values.contains(where:{$0.1 == current}) { values.append((L10n.text("mac.fXSourceSelection.options.5e156881ba"),current)) }
        return values
    }
}

struct MacFXScenarioSourcePicker: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    enum Scenario { case accounting, menuBar }
    let scenario: Scenario
    @ObservedObject private var service = MacFXApplication.shared.monitor
    private var key: WritableKeyPath<MacFXConfiguration,String> { scenario == .accounting ? \.accountingSourcePolicy : \.sourcePolicy }
    var body: some View {
        MacSettingsRow(label:scenario == .accounting ? L10n.text("mac.fXSourceSelection.body.4c6c9c8d37") : L10n.text("mac.fXSourceSelection.body.a7264f2850")) {
            MacSettingsMenu(selection:Binding(get:{service.configuration[keyPath:key]},set:{ value in MacFXApplication.shared.update { $0[keyPath:key] = value } }),options:MacFXSourceSelection.options(current:service.configuration[keyPath:key], includeAutomatic: scenario == .menuBar))
                .frame(width:280).accessibilityIdentifier(scenario == .accounting ? "fxAccountingSource" : "fxMenuSource")
        }
    }
}

struct MacFXSystemSourceCard: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @State private var checking = false
    @State private var result: String?
    @State private var available = false
    var body: some View {
        MacSettingsCard(title:L10n.text("mac.fXSourceSelection.body.2ea759ff20"),icon:"globe",subtitle:L10n.text("mac.fXSourceSelection.body.f834dbd5fc"),action:AnyView(Text(L10n.text("mac.fXSourceSelection.AnyView.f1839ad75a")).appFont(.caption,weight:.medium).foregroundStyle(.secondary))) {
            Text(L10n.text("mac.fXSourceSelection.body.c63d08f3a1")).appFont(.body)
            HStack {
                if let result { Label(result,systemImage:available ? "checkmark.circle" : "exclamationmark.circle").appFont(.caption).foregroundStyle(available ? Color.green : .secondary).accessibilityIdentifier("fxSystemSourceResult") }
                Spacer(minLength:12)
                Button(checking ? L10n.text("mac.fXSourceSelection.body.e8b970bc3e") : L10n.text("mac.fXSourceSelection.body.584ab75dc7")) { Task { await check() } }.disabled(checking).accessibilityIdentifier("fxSystemSourceCheck")
            }
        }.accessibilityElement(children:.contain).accessibilityIdentifier("fxSystemSourceCard")
    }
    private func check() async {
        checking = true; defer { checking = false }
        if MacFXApplication.shared.transport.mock { available = false; result = L10n.text("mac.fXSourceSelection.check.636a25539b"); return }
        do {
            let quote = try await MacFXApplication.shared.transport.systemQuote(pair:MacFXPair(base:"USD",quote:"CNY"))
            available = true; result = L10n.text("mac.fXSourceSelection.check.cde10ab9d2") + MacFXDates.label(quote.quoteTime)
        } catch { available = false; result = L10n.text("mac.fXSourceSelection.check.f4877dcf3e") }
    }
}
