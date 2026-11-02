import SwiftUI
import SwiftData
import AppKit

struct MacGeneralSettingsView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    var wide: Bool
    @Environment(\.modelContext) private var context
    @AppStorage("v2_week_start") private var weekStart = 2
    @AppStorage("app_date_format") private var dateFormat = "yyyy.MM.dd"
    @AppStorage("v2_month_format") private var monthFormat = "yyyy年M月"
    @AppStorage("v2_time_format") private var timeFormat = "HH:mm"
    @AppStorage("v2_decimals") private var decimals = 2
    @AppStorage("v2_grouping") private var grouping = "comma"
    @AppStorage("v2_negative") private var negative = "minus"
    @AppStorage("v2_zero") private var zero = "number"
    @AppStorage("v2_sort") private var sort = "最新优先"
    @AppStorage("v2_page_size") private var pageSize = 50
    @AppStorage("v2_chart_months") private var chartMonths = 6
    @AppStorage("v2_notes") private var notes = true
    @AppStorage("v2_resume_page") private var resume = true
    @AppStorage("v2_remind_recurring") private var remindRecurring = true
    @AppStorage("v2_remind_goals") private var remindGoals = true
    @AppStorage("v2_remind_budgets") private var remindBudgets = true
    @AppStorage("v2_confirm_records") private var confirmRecords = true
    @AppStorage("v2_confirm_categories") private var confirmCategories = true
    @AppStorage("v2_confirm_clear") private var confirmClear = true
    @State private var size = "—"
    @State private var cacheMessage: String?
    @ObservedObject private var appServices = MacAppServices.shared
    @ObservedObject private var entries = MacApplicationRuntime.shared.entries
    @AppStorage("v141_background") private var background = true
    @AppStorage("v141_show_help") private var showHelp = true
    @ObservedObject private var permissions = MacPermissionCoordinator.shared
    @State private var notificationError: String?
    var body: some View {
        MacSettingsFlowLayout(columns: wide ? 2 : 1, spacing: 14) {
            dateCard
            behaviorCard
            moneyCard
            MacAppEntrySettingsCard(showsEntry: false)
            listCard
            MacSelectionSettingsCard()
            remindersCard
            confirmationCard
            storageCard
        }
        .task { size = databaseSize(); await permissions.refresh(); appServices.refreshLoginStatus() }
        .onChange(of: remindRecurring) { _, enabled in updateNotifications(requestPermission: enabled) }
        .onChange(of: remindGoals) { _, enabled in updateNotifications(requestPermission: enabled) }
        .onChange(of: remindBudgets) { _, enabled in updateNotifications(requestPermission: enabled) }
    }
    private var dateCard: some View {
MacSettingsCard(title: L10n.text("mac.generalSettingsView.dateCard.917e4afc23"), icon: "calendar", subtitle: "", headerColor: .red) {
                    MacSettingsRow(label: L10n.text("mac.generalSettingsView.dateCard.1b8e70100e")) { MacSettingsMenu(selection: $weekStart, options: [(L10n.text("mac.generalSettingsView.MacSettingsMenu.56451fdf19"),2), (L10n.text("mac.generalSettingsView.MacSettingsMenu.7e06f3148f"),1)]).accessibilityIdentifier("generalWeekStartMenu") }
                    MacSettingsRow(label: L10n.text("mac.generalSettingsView.dateCard.7530fa1a19")) { MacSettingsMenu(selection: $dateFormat, options: [("2026-10-15","yyyy-MM-dd"), ("2026.10.15","yyyy.MM.dd"), ("15/10/2026","dd/MM/yyyy"), ("15.10.2026","dd.MM.yyyy"), ("10/15/2026","M/d/yyyy")]).accessibilityIdentifier("appDateFormatPicker") }
                    MacSettingsRow(label: L10n.text("mac.generalSettingsView.dateCard.d8b22e0433")) { MacSettingsMenu(selection: $monthFormat, options: [(L10n.text("mac.generalSettingsView.MacSettingsMenu.cdb0761e35"),"yyyy年M月"), ("2026-10","yyyy-MM")]).accessibilityIdentifier("generalMonthFormatMenu") }
                    MacSettingsRow(label: L10n.text("mac.generalSettingsView.dateCard.1a83bdb917")) { MacSettingsMenu(selection: $timeFormat, options: [(L10n.text("mac.generalSettingsView.MacSettingsMenu.933892d99c"),"HH:mm"), (L10n.text("mac.generalSettingsView.MacSettingsMenu.4650de16ac"),"a h:mm")]).accessibilityIdentifier("generalTimeFormatMenu") }
                }
    }
    private var moneyCard: some View {
MacSettingsCard(title: L10n.text("mac.generalSettingsView.moneyCard.d317abf0a9"), icon: "banknote", subtitle: L10n.text("mac.generalSettingsView.moneyCard.21f5f67457"), headerColor: .orange) {
                    MacSettingsRow(label: L10n.text("mac.generalSettingsView.moneyCard.e63f76858c")) { MacSettingsMenu(selection: $decimals, options: (0...4).map { (MacDisplayPreferences.money(12345.6789, decimals: $0, grouping: grouping, negative: negative, zero: zero), $0) }).accessibilityIdentifier("settingsDecimals") }
                    MacSettingsRow(label: L10n.text("mac.generalSettingsView.moneyCard.5c875c11c8")) { MacSettingsMenu(selection: $grouping, options: [("12,345.68","comma"), ("12 345.68","space"), ("12345.68","none")]).accessibilityIdentifier("generalGroupingMenu") }
                    MacSettingsRow(label: L10n.text("mac.generalSettingsView.moneyCard.1e280bd3a7")) { MacSettingsMenu(selection: $negative, options: [("−12,345.68","minus"), ("(12,345.68)","parentheses")]).accessibilityIdentifier("generalNegativeMenu") }
                    MacSettingsRow(label: L10n.text("mac.generalSettingsView.moneyCard.89fdfdb636")) { MacSettingsMenu(selection: $zero, options: [("0.00","number"), ("—","dash")]).accessibilityIdentifier("generalZeroDisplayMenu") }
                }
    }
    private var listCard: some View {
MacSettingsCard(title: L10n.text("mac.generalSettingsView.listCard.8c946584fd"), icon: "tablecells", subtitle: L10n.text("mac.generalSettingsView.listCard.d49479722b"), headerColor: .blue) {
                    MacSettingsRow(label: L10n.text("mac.generalSettingsView.listCard.81a2f5eea0")) { MacSettingsMenu(selection: Binding(get: { MacRecordSort.stored(sort).legacyValue }, set: { sort = $0 }), options: MacRecordSort.allCases.map { ($0.title, $0.legacyValue) }).accessibilityIdentifier("generalRecordSortMenu") }
                    MacSettingsRow(label: L10n.text("mac.generalSettingsView.listCard.1900b40fe0")) { MacSettingsMenu(selection: $pageSize, options: [25,50,100].map { (L10n.format("mac.generalSettingsView.MacSettingsMenu.08f9603e78", "\($0)"),$0) }).accessibilityIdentifier("generalPageSizeMenu") }
                    MacSettingsRow(label: L10n.text("mac.generalSettingsView.listCard.d606645c3e")) { MacSettingsMenu(selection: $chartMonths, options: [3,6,12].map { (L10n.format("mac.generalSettingsView.MacSettingsMenu.4a59d09e07", "\($0)"),$0) }).accessibilityIdentifier("generalChartMonthsMenu") }
                    MacSettingsToggleRow(title: L10n.text("mac.generalSettingsView.listCard.b5e3cefa51"), value: $notes)
                }
    }
    private var dockOnly: Bool { entries.configuration.showDock && !entries.configuration.showMenuBar }
    private var behaviorCard: some View {
MacSettingsCard(title: L10n.text("mac.generalSettingsView.behaviorCard.921bdaea10"), icon: "app.badge", subtitle: "", headerColor: .purple) {
                    MacSettingsToggleRow(title: L10n.text("mac.generalSettingsView.behaviorCard.3c1edacaeb"), value: entryBinding(\.showMenuBar)).accessibilityIdentifier("entryShowMenu")
                    MacSettingsToggleRow(title: L10n.text("mac.generalSettingsView.behaviorCard.f05e811bd3"), value: entryBinding(\.showDock)).accessibilityIdentifier("entryShowDock")
                    MacSettingsToggleRow(title: L10n.text("mac.generalSettingsView.behaviorCard.241678acd9"), value: entryBinding(\.showMainOnLaunch)).accessibilityIdentifier("entryShowMain")
                    Divider()

                    MacSettingsToggleRow(title: L10n.text("mac.generalSettingsView.behaviorCard.9021894921"), value: Binding(get: { appServices.loginEnabled }, set: { appServices.setLoginEnabled($0) })).accessibilityIdentifier("settingsLaunchAtLogin")
                    MacSettingsToggleRow(title: L10n.text("mac.generalSettingsView.behaviorCard.dc4e2b3d83"), value: Binding(get: { dockOnly || background }, set: { background = $0 })).disabled(dockOnly).accessibilityIdentifier("settingsBackground")
                    if dockOnly { Text(L10n.text("mac.generalSettingsView.behaviorCard.6138ccbf06")).appFont(.caption).foregroundStyle(.secondary) }
                    MacSettingsToggleRow(title: L10n.text("mac.generalSettingsView.behaviorCard.cfe0d7b9f9"), value: $resume).accessibilityIdentifier("settingsResumePage")
                    MacSettingsToggleRow(title: L10n.text("mac.generalSettingsView.behaviorCard.853a52e651"), value: $showHelp).accessibilityIdentifier("settingsShowHelp")
                    if let message = appServices.loginMessage { Text(message).appFont(.caption).foregroundStyle(.orange) }
                    HStack { Text(L10n.text("mac.generalSettingsView.behaviorCard.88f764cf02")); Spacer(); Button(L10n.text("mac.generalSettingsView.behaviorCard.3e43fae5bd")) { MacPermissionCoordinator.shared.open() }.accessibilityIdentifier("reopenPermissionsGuide") }
                    if let message = entries.message { Text(message).appFont(.caption).foregroundStyle(.orange) }
                }
    }
    private var confirmationCard: some View {
MacSettingsCard(title: L10n.text("mac.generalSettingsView.confirmationCard.1d836e4f54"), icon: "exclamationmark.triangle.fill", subtitle: L10n.text("mac.generalSettingsView.confirmationCard.0075a7da4a"), headerColor: .red) {
                    MacSettingsToggleRow(title: L10n.text("mac.generalSettingsView.confirmationCard.a068ba6e62"), value: $confirmRecords)
                    MacSettingsToggleRow(title: L10n.text("mac.generalSettingsView.confirmationCard.578dec455a"), value: $confirmCategories)
                    MacSettingsToggleRow(title: L10n.text("mac.generalSettingsView.confirmationCard.3baa547023"), value: $confirmClear)
                    Text(L10n.text("mac.generalSettingsView.confirmationCard.383f352395")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                }
    }
    private var remindersCard: some View {
MacSettingsCard(title: L10n.text("mac.generalSettingsView.remindersCard.89e0c11394"), icon: "bell", headerColor: .purple) {
                    HStack(spacing: 7) {
                        Circle().fill(permissions.notificationsActive ? Color.green : Color.secondary.opacity(0.4)).frame(width: 7, height: 7).accessibilityHidden(true)
                        Text(permissions.notificationsActive ? L10n.text("mac.generalSettingsView.remindersCard.654743c62a") : L10n.text("mac.generalSettingsView.remindersCard.2cba67d1b5")).appFont(.caption).foregroundStyle(.secondary).accessibilityIdentifier("systemNotificationStatus")
                        Spacer()
                        Toggle(L10n.text("mac.generalSettingsView.remindersCard.2bad76dc4a"), isOn: Binding(get: { permissions.notificationsActive }, set: { permissions.setNotificationsEnabled($0) })).labelsHidden().toggleStyle(.switch).accessibilityIdentifier("systemNotificationsToggle")
                    }
                    if let notificationError { Text(notificationError).appFont(.caption).foregroundStyle(.red) }

                    MacSettingsToggleRow(title: L10n.text("mac.generalSettingsView.remindersCard.875d3ab9c9"), subtitle: L10n.text("mac.generalSettingsView.remindersCard.71b0996e96"), icon: "calendar", color: .red, value: $remindRecurring)
                    MacSettingsToggleRow(title: L10n.text("mac.generalSettingsView.remindersCard.916762880a"), subtitle: L10n.text("mac.generalSettingsView.remindersCard.f989819143"), icon: "target", color: .orange, value: $remindGoals)
                    MacSettingsToggleRow(title: L10n.text("mac.generalSettingsView.remindersCard.865635c395"), subtitle: L10n.text("mac.generalSettingsView.remindersCard.2a0606aa11"), icon: "chart.bar", color: .green, value: $remindBudgets)
                }
    }
    private var storageCard: some View {
MacSettingsCard(title: L10n.text("mac.generalSettingsView.storageCard.900e877f10"), icon: "externaldrive", subtitle: L10n.text("mac.generalSettingsView.storageCard.6a27e3a345"), headerColor: .gray) {
                    HStack { Label(L10n.text("mac.generalSettingsView.storageCard.3e59fd1332"), systemImage: "externaldrive"); Spacer(); Text(size).foregroundStyle(.secondary) }.appFont(.body, weight: .regular, design: .default).accessibilityIdentifier("settingsDatabaseSize")
                    HStack { Label(L10n.text("mac.generalSettingsView.storageCard.fc17b14399"), systemImage: "trash"); Spacer(); Button(L10n.text("mac.generalSettingsView.storageCard.8f5ec46feb")) { cleanCache() }.accessibilityIdentifier("settingsClearCache") }.appFont(.body, weight: .regular, design: .default)
                    Text(cacheMessage ?? L10n.text("mac.generalSettingsView.storageCard.452b9861e4")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                }
    }
    private func entryBinding(_ path: WritableKeyPath<MacAppEntryConfiguration,Bool>) -> Binding<Bool> {
        Binding(get: { entries.configuration[keyPath:path] }, set: { value in
            var next = entries.configuration; next[keyPath:path] = value
            Task { await entries.apply(next,rejectAllHidden:true) }
        })
    }
    private func updateNotifications(requestPermission: Bool = false) {
        Task {
            do {
                if requestPermission { try await MacNotifications.authorizeAndSchedule(in: context) }
                else { try await MacNotifications.schedule(in: context) }
                notificationError = nil
            } catch { notificationError = error.localizedDescription }
            await permissions.refresh()
        }
    }
    private func databaseSize() -> String {
        guard let config = context.container.configurations.first else { return L10n.text("mac.generalSettingsView.databaseSize.c270415855") }
        if config.isStoredInMemoryOnly { return L10n.text("mac.generalSettingsView.databaseSize.19ad953aea") }
        let files = [config.url, URL(fileURLWithPath: config.url.path + "-wal"), URL(fileURLWithPath: config.url.path + "-shm")]
        let bytes = files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    private func cleanCache() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FinTrack-Previews", isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
            cacheMessage = L10n.text("mac.generalSettingsView.cleanCache.326007fe8f"); size = databaseSize()
        } catch { cacheMessage = L10n.format("mac.generalSettingsView.cleanCache.e1e17fa6d5", "\(error.localizedDescription)") }
    }
}

/// Shortest-column packing keeps independent cards compact without equal-height rows.
private struct MacSettingsFlowLayout: Layout {
    var columns: Int
    var spacing: CGFloat
    private func positions(width: CGFloat, subviews: Subviews) -> ([CGPoint], CGFloat, CGFloat) {
        let count = max(1, columns), columnWidth = max(1, (width-spacing*CGFloat(count-1))/CGFloat(count))
        var heights = Array(repeating:CGFloat.zero,count:count), positions: [CGPoint] = []
        for view in subviews {
            let index = heights.indices.min(by:{heights[$0]<heights[$1]}) ?? 0
            positions.append(CGPoint(x:CGFloat(index)*(columnWidth+spacing),y:heights[index]))
            heights[index] += view.sizeThatFits(ProposedViewSize(width:columnWidth,height:nil)).height+spacing
        }
        return (positions,max(0,(heights.max() ?? 0)-spacing),columnWidth)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 700
        return CGSize(width:width,height:positions(width:width,subviews:subviews).1)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (points,_,width) = positions(width:bounds.width,subviews:subviews)
        for (index,view) in subviews.enumerated() { view.place(at:CGPoint(x:bounds.minX+points[index].x,y:bounds.minY+points[index].y),anchor:.topLeading,proposal:ProposedViewSize(width:width,height:nil)) }
    }
}
