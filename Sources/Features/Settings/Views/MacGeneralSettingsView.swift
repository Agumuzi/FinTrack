import SwiftUI
import SwiftData
import AppKit

struct MacGeneralSettingsView: View {
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
    @State private var notificationStatus = ""
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
        .task { size = databaseSize(); notificationStatus = await MacNotifications.authorizationLabel(); appServices.refreshLoginStatus() }
        .onChange(of: remindRecurring) { _, enabled in updateNotifications(requestPermission: enabled) }
        .onChange(of: remindGoals) { _, enabled in updateNotifications(requestPermission: enabled) }
        .onChange(of: remindBudgets) { _, enabled in updateNotifications(requestPermission: enabled) }
    }
    private var dateCard: some View {
MacSettingsCard(title: "日期与时间", icon: "calendar", subtitle: "设置日期范围、周起始日和显示格式。", headerColor: .red) {
                    MacSettingsRow(label: "周起始日") { MacSettingsMenu(selection: $weekStart, options: [("星期一",2), ("星期日",1)]).accessibilityIdentifier("generalWeekStartMenu") }
                    MacSettingsRow(label: "日期格式") { MacSettingsMenu(selection: $dateFormat, options: [("2026-10-15","yyyy-MM-dd"), ("2026.10.15","yyyy.MM.dd"), ("15/10/2026","dd/MM/yyyy"), ("15.10.2026","dd.MM.yyyy"), ("10/15/2026","M/d/yyyy")]).accessibilityIdentifier("appDateFormatPicker") }
                    MacSettingsRow(label: "月份显示格式") { MacSettingsMenu(selection: $monthFormat, options: [("2026年10月","yyyy年M月"), ("2026-10","yyyy-MM")]).accessibilityIdentifier("generalMonthFormatMenu") }
                    MacSettingsRow(label: "时间格式") { MacSettingsMenu(selection: $timeFormat, options: [("24 小时制","HH:mm"), ("12 小时制","a h:mm")]).accessibilityIdentifier("generalTimeFormatMenu") }
                }
    }
    private var moneyCard: some View {
MacSettingsCard(title: "金额与货币显示", icon: "banknote", subtitle: "设置金额的显示格式和精度，不改变保存值。", headerColor: .orange) {
                    MacSettingsRow(label: "默认货币精度") { MacSettingsMenu(selection: $decimals, options: (0...4).map { ("\($0) 位小数", $0) }).accessibilityIdentifier("settingsDecimals") }
                    MacSettingsRow(label: "千位分隔符") { MacSettingsMenu(selection: $grouping, options: [("逗号","comma"), ("空格","space"), ("不分隔","none")]).accessibilityIdentifier("generalGroupingMenu") }
                    MacSettingsRow(label: "负数显示方式") { MacSettingsMenu(selection: $negative, options: [("减号前缀","minus"), ("括号","parentheses")]).accessibilityIdentifier("generalNegativeMenu") }
                    MacSettingsRow(label: "零值显示") { MacSettingsMenu(selection: $zero, options: [("数字","number"), ("短横线","dash")]).accessibilityIdentifier("generalZeroDisplayMenu") }
                    Text("预览：" + MacDisplayPreferences.money(-12345.6789, decimals: decimals, grouping: grouping, negative: negative, zero: zero)).appFont(.caption, weight: .regular, design: .monospaced).foregroundStyle(.secondary).accessibilityIdentifier("settingsMoneyPreview")
                }
    }
    private var listCard: some View {
MacSettingsCard(title: "列表与数据展示", icon: "tablecells", subtitle: "设置列表页面的默认排序和显示选项。", headerColor: .blue) {
                    MacSettingsRow(label: "账目默认排序") { MacSettingsMenu(selection: $sort, options: [("按日期（新→旧）","最新优先"), ("按日期（旧→新）","最早优先"), ("金额从高到低","金额从高到低")]).accessibilityIdentifier("generalRecordSortMenu") }
                    MacSettingsRow(label: "默认显示数量") { MacSettingsMenu(selection: $pageSize, options: [25,50,100].map { ("\($0) 条",$0) }).accessibilityIdentifier("generalPageSizeMenu") }
                    MacSettingsRow(label: "图表时间范围") { MacSettingsMenu(selection: $chartMonths, options: [3,6,12].map { ("最近 \($0) 个月",$0) }).accessibilityIdentifier("generalChartMonthsMenu") }
                    MacSettingsToggleRow(title: "在列表中显示备注预览", value: $notes)
                }
    }
    private var behaviorCard: some View {
MacSettingsCard(title: "应用与交互", icon: "app.badge", subtitle: "设置启动、后台运行和常用入口。", headerColor: .purple) {
                    MacSettingsToggleRow(title: "显示菜单栏入口", value: entryBinding(\.showMenuBar)).accessibilityIdentifier("entryShowMenu")
                    MacSettingsToggleRow(title: "显示 Dock 图标", value: entryBinding(\.showDock)).accessibilityIdentifier("entryShowDock")
                    MacSettingsToggleRow(title: "启动时显示主窗口", value: entryBinding(\.showMainOnLaunch)).accessibilityIdentifier("entryShowMain")
                    Divider()

                    MacSettingsToggleRow(title: "开机登录后启动", value: Binding(get: { appServices.loginEnabled }, set: { appServices.setLoginEnabled($0) })).accessibilityIdentifier("settingsLaunchAtLogin")
                    MacSettingsToggleRow(title: "关闭窗口后继续后台运行", value: $background).accessibilityIdentifier("settingsBackground")
                    MacSettingsToggleRow(title: "启动时打开上次访问的页面", value: $resume).accessibilityIdentifier("settingsResumePage")
                    MacSettingsToggleRow(title: "显示悬停说明", value: $showHelp).accessibilityIdentifier("settingsShowHelp")
                    if let message = appServices.loginMessage { Text(message).appFont(.caption).foregroundStyle(.orange) }
                    if let message = entries.message { Text(message).appFont(.caption).foregroundStyle(.orange) }
                }
    }
    private var confirmationCard: some View {
MacSettingsCard(title: "危险操作确认", icon: "exclamationmark.triangle.fill", subtitle: "对可能影响数据安全的操作进行二次确认。", headerColor: .red) {
                    MacSettingsToggleRow(title: "删除账目时需要确认", value: $confirmRecords)
                    MacSettingsToggleRow(title: "删除分类时需要确认", value: $confirmCategories)
                    MacSettingsToggleRow(title: "清空数据时需要多次确认", value: $confirmClear)
                    Text("引用、受保护收据与清空最终确认始终有效。").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                }
    }
    private var remindersCard: some View {
MacSettingsCard(title: "提醒与通知", icon: "bell", headerColor: .purple) {
                    Text(notificationStatus).appFont(.caption).foregroundStyle(.secondary).accessibilityIdentifier("systemNotificationStatus")
                    HStack {
                        Button("允许系统通知…") { updateNotifications(requestPermission: true) }.accessibilityIdentifier("authorizeSystemNotifications")
                        Spacer()
                        Button("系统通知设置") { if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) } }
                    }
                    if let notificationError { Text(notificationError).appFont(.caption).foregroundStyle(.red) }

                    MacSettingsToggleRow(title: "定期交易提醒", subtitle: "应用内及系统通知，仍遵循单项提醒设置", icon: "calendar", color: .red, value: $remindRecurring)
                    MacSettingsToggleRow(title: "目标提醒", subtitle: "当目标接近或已逾期时显示提醒", icon: "target", color: .orange, value: $remindGoals)
                    MacSettingsToggleRow(title: "预算提醒", subtitle: "当分类支出接近或超过预算时显示提醒", icon: "chart.bar", color: .green, value: $remindBudgets)
                }
    }
    private var storageCard: some View {
MacSettingsCard(title: "存储与性能", icon: "externaldrive", subtitle: "管理本地存储和临时文件。", headerColor: .gray) {
                    HStack { Label("数据库大小", systemImage: "externaldrive"); Spacer(); Text(size).foregroundStyle(.secondary) }.appFont(.body, weight: .regular, design: .default).accessibilityIdentifier("settingsDatabaseSize")
                    HStack { Label("清理缓存数据", systemImage: "trash"); Spacer(); Button("清理…") { cleanCache() }.accessibilityIdentifier("settingsClearCache") }.appFont(.body, weight: .regular, design: .default)
                    Text(cacheMessage ?? "清理临时缓存文件不会影响您的账本数据。").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
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
            notificationStatus = await MacNotifications.authorizationLabel()
        }
    }
    private func databaseSize() -> String {
        guard let config = context.container.configurations.first else { return "无法读取" }
        if config.isStoredInMemoryOnly { return "内存演示账本" }
        let files = [config.url, URL(fileURLWithPath: config.url.path + "-wal"), URL(fileURLWithPath: config.url.path + "-shm")]
        let bytes = files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    private func cleanCache() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FinTrack-Previews", isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
            cacheMessage = "临时缓存已清理"; size = databaseSize()
        } catch { cacheMessage = "清理失败：\(error.localizedDescription)" }
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
