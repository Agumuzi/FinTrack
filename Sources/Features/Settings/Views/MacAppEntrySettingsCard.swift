import SwiftUI

struct MacAppEntrySettingsCard: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    var showsEntry = true
    var showsMenu = true
    @ObservedObject private var entries = MacApplicationRuntime.shared.entries
    @ObservedObject private var service = MacFXApplication.shared.monitor
    var body: some View {
        VStack(spacing: 14) {
            if showsEntry { MacSettingsCard(title: L10n.text("mac.appEntrySettingsCard.body.2cc8576c40"), icon: "app.badge", subtitle: L10n.text("mac.appEntrySettingsCard.body.09fb58c9e8")) {
                MacSettingsToggleRow(title: L10n.text("mac.appEntrySettingsCard.body.3c1edacaeb"), value: binding(\.showMenuBar)).accessibilityIdentifier("entryShowMenu")
                MacSettingsToggleRow(title: L10n.text("mac.appEntrySettingsCard.body.f05e811bd3"), value: binding(\.showDock)).accessibilityIdentifier("entryShowDock")
                MacSettingsToggleRow(title: L10n.text("mac.appEntrySettingsCard.body.241678acd9"), value: binding(\.showMainOnLaunch)).accessibilityIdentifier("entryShowMain")
                if !entries.configuration.showMenuBar { Text(L10n.text("mac.appEntrySettingsCard.body.8d92acc53f")).appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                if let message = entries.message { Text(message).appFont(.caption, weight: .regular).foregroundStyle(.orange).accessibilityIdentifier("entryMessage") }
            }
            }
            if showsMenu { MacSettingsCard(title: L10n.text("mac.appEntrySettingsCard.body.a304cb9cd6"), icon: "menubar.rectangle", subtitle: L10n.text("mac.appEntrySettingsCard.body.b762fdd83d")) {
                HStack {
                    if entries.configuration.information != .rate { Image(nsImage: MacMenuBarLabel.image(entries.configuration.iconStyle)) }
                    if entries.configuration.information != .icon { Text(MacMenuBarLabel.text(configuration: entries.configuration, monitor: service)).appFont(.body, weight: .medium, design: .monospaced) }
                    Spacer()
                }.padding(14).background(.gray.opacity(0.07), in: RoundedRectangle(cornerRadius: 10)).accessibilityIdentifier("entryLabelPreview")
                MacSettingsRow(label: L10n.text("mac.appEntrySettingsCard.body.2bccb49f29")) { MacSettingsMenu(selection: binding(\.iconStyle), options: MacMenuIconStyle.allCases.map { ($0.title,$0) }).accessibilityIdentifier("entryIconStyle") }
                MacSettingsRow(label: L10n.text("mac.appEntrySettingsCard.body.04a02ee30d")) { MacSettingsMenu(selection: binding(\.information), options: MacMenuInformation.allCases.map { ($0.title,$0) }).accessibilityIdentifier("entryInformation") }
                MacSettingsRow(label: L10n.text("mac.appEntrySettingsCard.body.8c4005b325")) {
                    MacCurrencyMenu(selection: Binding(get: { entries.configuration.displayPair?.key ?? "" }, set: { key in
                        var value = entries.configuration; value.displayPair = service.configuration.watchedPairs.first { $0.key == key }; Task { await entries.apply(value) }
                    }), codes:service.configuration.watchedPairs.map(\.key),identifier:"entryPair",prefixOptions:[(L10n.text("mac.appEntrySettingsCard.MacCurrencyMenu.1182c5454f"), "")],fillsAvailableWidth:true)
                }
                MacSettingsRow(label: L10n.text("mac.appEntrySettingsCard.body.e197df324e")) { MacSettingsMenu(selection: binding(\.defaultPage), options: MacMenuBarPage.allCases.map { ($0.title,$0) }).accessibilityIdentifier("entryDefaultPage") }
                MacSettingsRow(label: L10n.text("mac.appEntrySettingsCard.body.63b682f149")) { MacSettingsMenu(selection: binding(\.pageMemory), options: MacMenuBarPageMemory.allCases.map { ($0.title,$0) }).accessibilityIdentifier("entryPageMemory") }
                Text(L10n.text("mac.appEntrySettingsCard.body.dd18e669b9")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            }
            }
        }.disabled(entries.isTransitioning)
    }
    private func binding<T>(_ key: WritableKeyPath<MacAppEntryConfiguration,T>) -> Binding<T> {
        Binding(get: { entries.configuration[keyPath: key] }, set: { value in
            var candidate = entries.configuration; candidate[keyPath: key] = value
            Task { await entries.apply(candidate, rejectAllHidden: true) }
        })
    }
}
