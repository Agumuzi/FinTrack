import SwiftUI
import AppKit

struct MacAboutSettingsView: View {
    var wide: Bool
    @ObservedObject private var updater = MacUpdateService.shared
    @ObservedObject private var permissions = MacPermissionCoordinator.shared
    @AppStorage("v2_update_auto") private var automatic = false
    @AppStorage("v2_update_frequency") private var frequency = "weekly"
    @State private var showsLicense = false
    @State private var message: String?
    @State private var error: String?
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else { return "许可证文件暂时不可用，请在 GitHub 项目主页查看 MIT 许可证。" }
        return text
    }
    private var canConfigure: Bool { MacUpdateService.configured || MacSettingsVisual.preview }
    var body: some View {
        MacSettingsColumns(wide: wide) {
            VStack(spacing: MacUI.space(15)) {
                HStack(spacing: MacUI.space(19)) {
                    MacBrandIcon(size: 88)
                    VStack(alignment: .leading, spacing: MacUI.space(9)) {
                        HStack(spacing: MacUI.space(12)) { Text("FinTrack").appFont(.pageTitle, weight: .bold, design: .default); Text("v" + MacUpdateService.version).appFont(.body, weight: .semibold, design: .default).foregroundStyle(.blue).appPadding(.horizontal, 9).appPadding(.vertical, 4).background(.blue.opacity(0.07), in: Capsule()) }
                        Text("一个简洁、专注的个人财务管理应用。").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                        Text("记录生活，掌控财务，走向更好的未来。").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.appPadding(22).frame(maxWidth: .infinity, alignment: .leading).background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 13)).accessibilityIdentifier("settingsActualVersion")
                MacSettingsCard(title: "软件更新", icon: "arrow.triangle.2.circlepath", subtitle: "检查新版本，保持应用更新。", headerColor: .blue) {
                    HStack(spacing: MacUI.space(14)) {
                        Image(systemName: MacSettingsVisual.preview ? "checkmark.circle.fill" : "arrow.down.circle.fill").appIconFont(43, weight: .regular, design: .default).foregroundStyle(MacSettingsVisual.preview ? .green : .blue)
                        VStack(alignment: .leading, spacing: MacUI.space(5)) {
                            Text(MacSettingsVisual.preview ? "当前已是最新版本（演示）" : MacUpdateService.configured ? updater.status : "尚未配置更新源").appFont(.body, weight: .semibold, design: .default).accessibilityIdentifier("settingsUpdateStatus")
                            Text("FinTrack " + MacUpdateService.version).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                            if let date = updater.checkedAt { Text("上次检查：" + MacDateDisplay.string(date) + " " + MacDisplayPreferences.time(date)).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }
                            else if MacSettingsVisual.preview { Text("上次检查：" + MacDateDisplay.string(Date()) + " 14:30").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 0)
                        Button(updater.actionTitle) { updater.performPrimaryAction() }.disabled(updater.busy).accessibilityIdentifier("settingsCheckUpdates")
                    }.appPadding(14).background(.blue.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    HStack(spacing: MacUI.space(12)) {
                        Image(systemName: "clock.arrow.circlepath").appIconFont(19, weight: .regular, design: .default).frame(width: MacUI.space(25))
                        VStack(alignment: .leading, spacing: MacUI.space(4)) { Text("自动检查更新").appFont(.body, weight: .medium, design: .default); Text("发现新版本时发送系统通知，点击通知查看更新。").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }
                        Spacer(minLength: 0)
                        Toggle("自动检查更新", isOn: $automatic).labelsHidden().toggleStyle(.switch).tint(.blue).disabled(!canConfigure)
                        MacSettingsMenu(selection: $frequency, options: [("每天","daily"), ("每周","weekly"), ("每月","monthly")]).frame(width: MacUI.space(95)).disabled(!canConfigure)
                    }
                    HStack {
                        Text("更新提醒：" + permissions.notificationText).appFont(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("权限设置") { permissions.open() }.accessibilityIdentifier("updatePermissionGuide")
                    }
                    if let message { Text(message).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.green) }
                    if let error { Text(error).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.red) }
                }
                MacSettingsCard(title: "版本信息", icon: "doc.text", subtitle: "查看当前版本的详细信息。", headerColor: .orange) {
                    VStack(spacing: MacUI.space(0)) {
                        info("版本号", MacUpdateService.version + "（" + MacUpdateService.build + "）")
                        info("构建平台", "macOS（" + platform + "）")
                        info("最低系统要求", "macOS " + (Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? "未声明") + " 或更高版本")
                        info("当前系统", ProcessInfo.processInfo.operatingSystemVersionString)
                    }
                }
            }
        } right: {
            VStack(spacing: MacUI.space(15)) {
                MacSettingsCard(title: "项目链接", icon: "github.mark", subtitle: "访问项目资料，查看源码与版本信息。", headerColor: .primary) {
                    VStack(spacing: MacUI.space(0)) {
                        projectLink("GitHub 项目主页", subtitle: "agumuzi.github.io/FinTrack", icon: "github.mark", url: "https://agumuzi.github.io/FinTrack/")
                        projectLink("查看源码", subtitle: "浏览项目的源代码仓库", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/Agumuzi/FinTrack")
                    }
                }
                MacSettingsCard(title: "支持与反馈", icon: "heart", subtitle: "记录使用建议，帮助持续改进 FinTrack。", headerColor: .green) {
                    VStack(spacing: MacUI.space(0)) {
                        feedback("报告问题", subtitle: "前往 GitHub 提交问题", icon: "bubble.left.and.bubble.right", color: .orange, suggestion: false)
                        feedback("功能建议", subtitle: "前往 GitHub 提交功能建议", icon: "lightbulb", color: .purple, suggestion: true)
                    }
                }
                MacSettingsCard(title: "法律与版权", icon: "info.circle", subtitle: "项目许可与作者信息。", headerColor: .purple) {
                    VStack(spacing: MacUI.space(0)) { info("许可信息", "MIT"); info("作者", "Agumuzi") }
                    Button("阅读开源许可证", systemImage: "doc.text") { showsLicense = true }.accessibilityIdentifier("settingsReadLicense")
                }
            }
        }
        .task { await permissions.refresh() }
        .onChange(of: automatic) { _, enabled in
            if enabled {
                Task {
                    do { try await MacPermissionCoordinator.shared.requestNotifications() } catch { message = error.localizedDescription }
                    await updater.check(automatic:true)
                }
            } else { MacNotifications.cancelUpdateNotices() }
        }
        .sheet(isPresented: $showsLicense) {
            MacFormShell(width: 620) { Text("MIT 开源许可证").appFont(.dialogTitle, weight: .semibold) } fields: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(licenseText)
                        if let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"), let notices = try? String(contentsOf: url, encoding: .utf8) { Text(notices) }
                    }.appFont(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 340)
            } footer: { HStack { Spacer(); Button("关闭") { showsLicense = false }.keyboardShortcut(.cancelAction) } }
        }
    }
    private func info(_ title: String, _ value: String) -> some View { VStack(spacing: MacUI.space(0)) { HStack { Text(title).appFont(.body, weight: .regular, design: .default); Spacer(); Text(value).appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }.appPadding(.vertical, 10); Divider() } }
    private func projectLink(_ title: String, subtitle: String, icon: String, url: String) -> some View {
        Link(destination: URL(string: url)!) { HStack(spacing: MacUI.space(12)) { MacSettingsSymbol(symbol: icon, size: 22).frame(width: MacUI.space(27)); VStack(alignment: .leading, spacing: MacUI.space(5)) { Text(title).appFont(.body, weight: .semibold, design: .default); Text(subtitle).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary) }.appPadding(12).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.16))) }.buttonStyle(MacInteractiveButtonStyle()).foregroundStyle(.primary).accessibilityIdentifier(title == "GitHub 项目主页" ? "projectHomepage" : "projectSource")
    }
    private func feedback(_ title: String, subtitle: String, icon: String, color: Color, suggestion: Bool) -> some View {
        Button {
            let text = "FinTrack " + MacUpdateService.version + "（" + MacUpdateService.build + "）\n" + ProcessInfo.processInfo.operatingSystemVersionString + (suggestion ? "\n功能建议：\n使用场景：" : "\n问题描述：\n操作步骤：\n预期结果：")
            var url = URLComponents(string: "https://github.com/Agumuzi/FinTrack/issues/new")!
            url.queryItems = [URLQueryItem(name:"title",value:suggestion ? "功能建议：" : "问题反馈："),URLQueryItem(name:"body",value:text)]
            if let destination = url.url { NSWorkspace.shared.open(destination) }
        } label: { HStack(spacing: MacUI.space(12)) { MacSettingsIcon(symbol: icon, color: color, size: 35); VStack(alignment: .leading, spacing: MacUI.space(4)) { Text(title).appFont(.body, weight: .semibold, design: .default); Text(subtitle).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary) }.appPadding(10).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.15))) }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier(suggestion ? "feedbackSuggestion" : "feedbackIssue")
    }
    private var platform: String {
        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Intel"
        #endif
    }
}
