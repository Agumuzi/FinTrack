import SwiftUI

struct MacAppEntrySettingsCard: View {
    var showsEntry = true
    var showsMenu = true
    @ObservedObject private var entries = MacApplicationRuntime.shared.entries
    @ObservedObject private var service = MacFXApplication.shared.monitor
    var body: some View {
        VStack(spacing: 14) {
            if showsEntry { MacSettingsCard(title: "应用入口", icon: "app.badge", subtitle: "菜单栏与 Dock 独立设置，至少保留一个入口。") {
                MacSettingsToggleRow(title: "显示菜单栏入口", value: binding(\.showMenuBar)).accessibilityIdentifier("entryShowMenu")
                MacSettingsToggleRow(title: "显示 Dock 图标", value: binding(\.showDock)).accessibilityIdentifier("entryShowDock")
                MacSettingsToggleRow(title: "启动时显示主窗口", value: binding(\.showMainOnLaunch)).accessibilityIdentifier("entryShowMain")
                if !entries.configuration.showMenuBar { Text("仅使用 Dock 时，启动始终显示主窗口。").appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                if let message = entries.message { Text(message).appFont(.caption, weight: .regular).foregroundStyle(.orange).accessibilityIdentifier("entryMessage") }
            }
            }
            if showsMenu { MacSettingsCard(title: "菜单栏", icon: "menubar.rectangle", subtitle: "上方预览当前显示，按组选取图标与信息。") {
                HStack {
                    if entries.configuration.information != .rate { Image(nsImage: MacMenuBarLabel.image(entries.configuration.iconStyle)) }
                    if entries.configuration.information != .icon { Text(MacMenuBarLabel.text(configuration: entries.configuration, monitor: service)).appFont(.body, weight: .medium, design: .monospaced) }
                    Spacer()
                }.padding(14).background(.gray.opacity(0.07), in: RoundedRectangle(cornerRadius: 10)).accessibilityIdentifier("entryLabelPreview")
                MacSettingsRow(label: "图标样式") { MacSettingsMenu(selection: binding(\.iconStyle), options: MacMenuIconStyle.allCases.map { ($0.title,$0) }).accessibilityIdentifier("entryIconStyle") }
                MacSettingsRow(label: "显示信息") { MacSettingsMenu(selection: binding(\.information), options: MacMenuInformation.allCases.map { ($0.title,$0) }).accessibilityIdentifier("entryInformation") }
                MacSettingsRow(label: "显示货币对") {
                    MacCurrencyMenu(selection: Binding(get: { entries.configuration.displayPair?.key ?? "" }, set: { key in
                        var value = entries.configuration; value.displayPair = service.configuration.watchedPairs.first { $0.key == key }; Task { await entries.apply(value) }
                    }), codes:service.configuration.watchedPairs.map(\.key),identifier:"entryPair",prefixOptions:[("未选择", "")])
                }
                MacSettingsRow(label: "默认页面") { MacSettingsMenu(selection: binding(\.defaultPage), options: MacMenuBarPage.allCases.map { ($0.title,$0) }).accessibilityIdentifier("entryDefaultPage") }
                MacSettingsRow(label: "页面记忆") { MacSettingsMenu(selection: binding(\.pageMemory), options: MacMenuBarPageMemory.allCases.map { ($0.title,$0) }).accessibilityIdentifier("entryPageMemory") }
                Text("跨重启只记住页面；未保存的记账草稿不写入磁盘。").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
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
