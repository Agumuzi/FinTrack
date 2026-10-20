import SwiftUI
import AppKit

struct MacAboutSettingsView: View {
    var wide: Bool
    @ObservedObject private var updater = MacUpdateService.shared
    @AppStorage("v2_update_auto") private var automatic = false
    @AppStorage("v2_update_frequency") private var frequency = "weekly"
    @AppStorage("v2_update_download") private var autoDownload = false
    @AppStorage("v2_update_url") private var feedURL = ""
    @AppStorage("v2_update_public_key") private var publicKey = ""
    @State private var confirmInstall = false
    @State private var message: String?
    @State private var error: String?
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
                        Button(updater.busy ? "检查中…" : "立即检查") { if MacSettingsVisual.preview { message = "演示界面：已刷新更新状态" } else { Task { await updater.check() } } }.disabled(updater.busy).accessibilityIdentifier("settingsCheckUpdates")
                    }.appPadding(14).background(.blue.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    HStack(spacing: MacUI.space(12)) {
                        Image(systemName: "clock.arrow.circlepath").appIconFont(19, weight: .regular, design: .default).frame(width: MacUI.space(25))
                        VStack(alignment: .leading, spacing: MacUI.space(4)) { Text("自动检查更新").appFont(.body, weight: .medium, design: .default); Text("选择检查新版本的频率。").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }
                        Spacer(minLength: 0)
                        Toggle("自动检查更新", isOn: $automatic).labelsHidden().toggleStyle(.switch).tint(.blue).disabled(!canConfigure)
                        MacSettingsMenu(selection: $frequency, options: [("每天","daily"), ("每周","weekly"), ("每月","monthly")]).frame(width: MacUI.space(95)).disabled(!canConfigure)
                    }
                    MacSettingsToggleRow(title: "发现新版本时", subtitle: "自动下载安装包，下载后仍需确认安装。", icon: "arrow.down", color: .gray, value: $autoDownload).disabled(!canConfigure)
                    if let release = updater.release {
                        Text(release.notes).appFont(.caption, weight: .regular, design: .default).textSelection(.enabled)
                        if updater.archive != nil { Button("安装并重新启动…") { confirmInstall = true }.disabled(updater.busy) }
                        else { Button("下载并验证更新") { Task { await updater.downloadRelease() } }.disabled(updater.busy) }
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
                if !MacSettingsVisual.preview {
                    DisclosureGroup("配置更新源") { VStack(spacing: MacUI.space(12)) { TextField("HTTPS 更新清单 URL", text: $feedURL); TextField("Ed25519 公钥（Base64）", text: $publicKey) }.appPadding(.top, 12) }.appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                }
            }
        } right: {
            VStack(spacing: MacUI.space(15)) {
                MacSettingsCard(title: "项目链接", icon: "github.mark", subtitle: "访问项目资料，查看源码与版本信息。", headerColor: .primary) {
                    VStack(spacing: MacUI.space(0)) {
                        projectLink("GitHub 项目主页", subtitle: "github.com/Agumuzi/FinTrack", icon: "github.mark", url: "https://github.com/Agumuzi/FinTrack")
                        projectLink("查看源码", subtitle: "浏览项目的源代码仓库", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/Agumuzi/FinTrack")
                    }
                }
                MacSettingsCard(title: "支持与反馈", icon: "heart", subtitle: "记录使用建议，帮助持续改进 FinTrack。", headerColor: .green) {
                    VStack(spacing: MacUI.space(0)) {
                        feedback("复制反馈信息", subtitle: "包含当前版本和系统信息", icon: "bubble.left.and.bubble.right", color: .orange, suggestion: false)
                        feedback("功能建议", subtitle: "复制建议模板并填写想法", icon: "lightbulb", color: .purple, suggestion: true)
                    }
                }
                MacSettingsCard(title: "法律与版权", icon: "info.circle", subtitle: "项目许可与作者信息。", headerColor: .purple) {
                    VStack(spacing: MacUI.space(0)) { info("许可信息", "尚未指定"); info("作者", "Agumuzi") }
                }
            }
        }
        .onChange(of: feedURL) { updater.reset() }.onChange(of: publicKey) { updater.reset() }
        .alert("安装更新并重新启动？", isPresented: $confirmInstall) {
            Button("取消", role: .cancel) {}
            Button("安装并重新启动") { do { try updater.installAndRelaunch() } catch { self.error = error.localizedDescription } }
        } message: { Text("校验安装包与应用身份后替换程序，保留旧应用副本；账本不会移动。") }
    }
    private func info(_ title: String, _ value: String) -> some View { VStack(spacing: MacUI.space(0)) { HStack { Text(title).appFont(.body, weight: .regular, design: .default); Spacer(); Text(value).appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }.appPadding(.vertical, 10); Divider() } }
    private func projectLink(_ title: String, subtitle: String, icon: String, url: String) -> some View {
        Link(destination: URL(string: url)!) { HStack(spacing: MacUI.space(12)) { MacSettingsSymbol(symbol: icon, size: 22).frame(width: MacUI.space(27)); VStack(alignment: .leading, spacing: MacUI.space(5)) { Text(title).appFont(.body, weight: .semibold, design: .default); Text(subtitle).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary) }.appPadding(12).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.16))) }.buttonStyle(.plain).foregroundStyle(.primary)
    }
    private func feedback(_ title: String, subtitle: String, icon: String, color: Color, suggestion: Bool) -> some View {
        Button {
            let text = "FinTrack " + MacUpdateService.version + "（" + MacUpdateService.build + "）\n" + ProcessInfo.processInfo.operatingSystemVersionString + (suggestion ? "\n功能建议：\n使用场景：" : "\n问题描述：\n操作步骤：\n预期结果：")
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); message = "反馈信息已复制"
        } label: { HStack(spacing: MacUI.space(12)) { MacSettingsIcon(symbol: icon, color: color, size: 35); VStack(alignment: .leading, spacing: MacUI.space(4)) { Text(title).appFont(.body, weight: .semibold, design: .default); Text(subtitle).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "doc.on.doc").foregroundStyle(.secondary) }.appPadding(10).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.15))) }.buttonStyle(.plain)
    }
    private var platform: String {
        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Intel"
        #endif
    }
}
