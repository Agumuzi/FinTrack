import SwiftUI
import AppKit

struct MacAboutSettingsView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    var wide: Bool
    @ObservedObject private var updater = MacUpdateService.shared
    @AppStorage("v2_update_auto") private var automatic = false
    @AppStorage("v2_update_frequency") private var frequency = "weekly"
    @State private var showsLicense = false
    @State private var message: String?
    @State private var error: String?
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else { return L10n.text("mac.aboutSettingsView.licenseText.068eae3080") }
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
                        Text(L10n.text("mac.aboutSettingsView.MacSettingsColumns.7651ee21cf")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                        Text(L10n.text("mac.aboutSettingsView.MacSettingsColumns.0835795621")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.appPadding(22).frame(maxWidth: .infinity, alignment: .leading).background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 13)).accessibilityIdentifier("settingsActualVersion")
                MacSettingsCard(title: L10n.text("mac.aboutSettingsView.MacSettingsColumns.651f274470"), icon: "arrow.triangle.2.circlepath", subtitle: L10n.text("mac.aboutSettingsView.MacSettingsColumns.a738d54b0f"), headerColor: .blue) {
                    HStack(spacing: MacUI.space(14)) {
                        Image(systemName: MacSettingsVisual.preview ? "checkmark.circle.fill" : "arrow.down.circle.fill").appIconFont(43, weight: .regular, design: .default).foregroundStyle(MacSettingsVisual.preview ? .green : .blue)
                        VStack(alignment: .leading, spacing: MacUI.space(5)) {
                            Text(MacSettingsVisual.preview ? L10n.text("mac.aboutSettingsView.MacSettingsColumns.94b6b4d1a9") : MacUpdateService.configured ? updater.status : L10n.text("mac.aboutSettingsView.MacSettingsColumns.3f40aabc13")).appFont(.body, weight: .semibold, design: .default).accessibilityIdentifier("settingsUpdateStatus")
                            Text("FinTrack " + MacUpdateService.version).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                            if let date = updater.checkedAt { Text(L10n.text("mac.aboutSettingsView.MacSettingsColumns.d308a2437c") + MacDateDisplay.string(date) + " " + MacDisplayPreferences.time(date)).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }
                            else if MacSettingsVisual.preview { Text(L10n.text("mac.aboutSettingsView.MacSettingsColumns.d308a2437c") + MacDateDisplay.string(Date()) + " 14:30").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 0)
                        Button(updater.actionTitle) { updater.performPrimaryAction() }.disabled(updater.busy).accessibilityIdentifier("settingsCheckUpdates")
                    }.appPadding(14).background(.blue.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: MacUI.space(12)) {
                      HStack(alignment: .center, spacing: MacUI.space(12)) {
                        Image(systemName: "clock.arrow.circlepath").appIconFont(19, weight: .regular, design: .default).frame(width: MacUI.space(25))
                        VStack(alignment: .leading, spacing: MacUI.space(4)) { Text(L10n.text("mac.aboutSettingsView.MacSettingsColumns.c42a3dd9c2")).appFont(.body, weight: .medium, design: .default); Text(L10n.text("mac.aboutSettingsView.MacSettingsColumns.05194ffffc")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }
                      }
                      HStack {
                        Spacer(minLength: 0)
                        Toggle(L10n.text("mac.aboutSettingsView.MacSettingsColumns.c42a3dd9c2"), isOn: $automatic).labelsHidden().toggleStyle(.switch).tint(.blue).disabled(!canConfigure)
                        MacSettingsMenu(selection: $frequency, options: [(L10n.text("mac.aboutSettingsView.MacSettingsMenu.eea1694c23"),"daily"), (L10n.text("mac.aboutSettingsView.MacSettingsMenu.92845d3b53"),"weekly"), (L10n.text("mac.aboutSettingsView.MacSettingsMenu.68b21af949"),"monthly")]).frame(width: MacUI.space(150)).disabled(!canConfigure)
                      }
                    }

                    if let message { Text(message).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.green) }
                    if let error { Text(error).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.red) }
                }
                MacSettingsCard(title: L10n.text("mac.aboutSettingsView.MacSettingsColumns.2da3906a24"), icon: "doc.text", subtitle: L10n.text("mac.aboutSettingsView.MacSettingsColumns.73cb182599"), headerColor: .orange) {
                    VStack(spacing: MacUI.space(0)) {
                        info(L10n.text("mac.aboutSettingsView.info.a98030a997"), MacUpdateService.version + "（" + MacUpdateService.build + "）")
                        info(L10n.text("mac.aboutSettingsView.info.8bbdbee710"), "macOS（" + platform + "）")
                        info(L10n.text("mac.aboutSettingsView.info.c1fc397f1c"), "macOS " + (Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? L10n.text("mac.aboutSettingsView.info.524a0bd8be")) + L10n.text("mac.aboutSettingsView.info.1ec0b1e912"))
                        info(L10n.text("mac.aboutSettingsView.info.fe11acd1ca"), systemVersion)
                    }
                }
            }
        } right: {
            VStack(spacing: MacUI.space(15)) {
                MacSettingsCard(title: L10n.text("mac.aboutSettingsView.MacSettingsColumns.8bb4ed25e6"), icon: "github.mark", subtitle: L10n.text("mac.aboutSettingsView.MacSettingsColumns.2a16da1e58"), headerColor: .primary) {
                    VStack(spacing: MacUI.space(0)) {
                        projectLink(L10n.text("mac.aboutSettingsView.projectLink.e4df4c8882"), subtitle: "agumuzi.github.io/FinTrack", icon: "github.mark", url: "https://agumuzi.github.io/FinTrack/")
                        projectLink(L10n.text("mac.aboutSettingsView.projectLink.921c3b62f1"), subtitle: L10n.text("mac.aboutSettingsView.projectLink.839df0ed3a"), icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/Agumuzi/FinTrack")
                    }
                }
                MacSettingsCard(title: L10n.text("mac.aboutSettingsView.MacSettingsColumns.af8c485802"), icon: "heart", subtitle: L10n.text("mac.aboutSettingsView.MacSettingsColumns.77009e2349"), headerColor: .green) {
                    VStack(spacing: MacUI.space(0)) {
                        feedback(L10n.text("mac.aboutSettingsView.feedback.0f7d68ecdc"), subtitle: L10n.text("mac.aboutSettingsView.feedback.7d3e11990a"), icon: "bubble.left.and.bubble.right", color: .orange, suggestion: false)
                        feedback(L10n.text("mac.aboutSettingsView.feedback.118db8121c"), subtitle: L10n.text("mac.aboutSettingsView.feedback.5f3dac60d3"), icon: "lightbulb", color: .purple, suggestion: true)
                    }
                }
                MacSettingsCard(title: L10n.text("mac.aboutSettingsView.MacSettingsColumns.4c2c9531a1"), icon: "info.circle", subtitle: L10n.text("mac.aboutSettingsView.MacSettingsColumns.f9c0e12146"), headerColor: .purple) {
                    VStack(spacing: MacUI.space(0)) { info(L10n.text("mac.aboutSettingsView.info.92e98bc0f7"), "MIT"); info(L10n.text("mac.aboutSettingsView.info.7d4146ca08"), "Agumuzi") }
                    Button(L10n.text("mac.aboutSettingsView.MacSettingsColumns.138632e93b"), systemImage: "doc.text") { showsLicense = true }.accessibilityIdentifier("settingsReadLicense")
                }
            }
        }

        .onChange(of: automatic) { _, enabled in
            if enabled {
                Task {
                    do { try await MacPermissionCoordinator.shared.requestNotifications() } catch { message = error.localizedDescription }
                    await updater.check(automatic:true)
                }
            } else { MacNotifications.cancelUpdateNotices() }
        }
        .sheet(isPresented: $showsLicense) {
            MacFormShell(width: 620) { Text(L10n.text("mac.aboutSettingsView.MacFormShell.44135e9a58")).appFont(.dialogTitle, weight: .semibold) } fields: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(licenseText)
                        if let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"), let notices = try? String(contentsOf: url, encoding: .utf8) { Text(notices) }
                    }.appFont(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 340)
            } footer: { HStack { Spacer(); Button(L10n.text("mac.aboutSettingsView.MacFormShell.3fd47edce4")) { showsLicense = false }.keyboardShortcut(.cancelAction) } }
        }
    }
    private func info(_ title: String, _ value: String) -> some View { VStack(spacing: MacUI.space(0)) { HStack { Text(title).appFont(.body, weight: .regular, design: .default); Spacer(); Text(value).appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }.appPadding(.vertical, 10); Divider() } }
    private func projectLink(_ title: String, subtitle: String, icon: String, url: String) -> some View {
        Link(destination: URL(string: url)!) { HStack(spacing: MacUI.space(12)) { MacSettingsSymbol(symbol: icon, size: 22).frame(width: MacUI.space(27)); VStack(alignment: .leading, spacing: MacUI.space(5)) { Text(title).appFont(.body, weight: .semibold, design: .default); Text(subtitle).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary) }.appPadding(12).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.16))) }.buttonStyle(MacInteractiveButtonStyle()).foregroundStyle(.primary).accessibilityIdentifier(url == "https://agumuzi.github.io/FinTrack/" ? "projectHomepage" : "projectSource")
    }
    private func feedback(_ title: String, subtitle: String, icon: String, color: Color, suggestion: Bool) -> some View {
        Button {
            let text = "FinTrack " + MacUpdateService.version + "（" + MacUpdateService.build + "）\n" + ProcessInfo.processInfo.operatingSystemVersionString + (suggestion ? L10n.text("mac.aboutSettingsView.text.a7b45ef585") : L10n.text("mac.aboutSettingsView.text.8e1b4a949b"))
            var url = URLComponents(string: "https://github.com/Agumuzi/FinTrack/issues/new")!
            url.queryItems = [URLQueryItem(name:"title",value:suggestion ? L10n.text("mac.aboutSettingsView.URLQueryItem.aec4dfdef8") : L10n.text("mac.aboutSettingsView.URLQueryItem.0289546f05")),URLQueryItem(name:"body",value:text)]
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
    private var systemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
