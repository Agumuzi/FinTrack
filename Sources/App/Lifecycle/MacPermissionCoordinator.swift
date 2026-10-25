import SwiftUI
import UserNotifications
import ApplicationServices
import ServiceManagement
import AppKit
import Combine

@MainActor
final class MacPermissionCoordinator: ObservableObject {
    static let shared = MacPermissionCoordinator()
    static let introKey = "v142_permission_intro_seen"
    @Published var presented = false
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var notificationText = "尚未开启"
    @Published private(set) var accessibilityEnabled = false
    @Published private(set) var message: String?
    @Published private(set) var requesting = false
    private var activationObserver: AnyCancellable?
    private init() {
        activationObserver = NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification).sink { [weak self] _ in Task { @MainActor in await self?.refresh() } }
    }
    func refresh() async {
        if MacPreferences.isTesting { notificationText = "隔离测试：不更改系统权限"; accessibilityEnabled = false; return }
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch notificationStatus {
        case .authorized,.provisional,.ephemeral: notificationText = "已允许"
        case .denied: notificationText = "已关闭，可在系统设置中开启"
        case .notDetermined: notificationText = "尚未开启"
        @unknown default: notificationText = "需要检查系统设置"
        }
        accessibilityEnabled = AXIsProcessTrusted()
        MacAppServices.shared.refreshLoginStatus()
    }
    func presentIfNeeded() {
        let optedInTest = ProcessInfo.processInfo.environment["FINTRACK_PERMISSIONS_INTRO_TEST"] == "1"
        guard !MacPreferences.isTesting || optedInTest else { return }
        guard !MacPreferences.defaults.bool(forKey:Self.introKey), MacUpdatePrompt.shared.stage == nil, !MacUpdateService.shared.handlingNotification else { return }
        presented = true
    }
    func open() { MacApplicationRuntime.shared.showMain(); presented = true; Task { await refresh() } }
    func finish() { MacPreferences.defaults.set(true,forKey:Self.introKey); presented = false }
    func requestNotifications() async throws {
        guard !MacPreferences.isTesting else { message = "测试副本不修改系统通知权限。"; return }
        guard !requesting else { return }; requesting = true; defer { requesting = false }
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge])
            await refresh()
            guard allowed else { throw MacSettingsFailure.invalid("系统通知未获允许，您可以稍后在系统设置中开启。") }
            message = nil
        } catch { message = error.localizedDescription; throw error }
    }
    func enableNotifications() {
        Task {
            do {
                try await requestNotifications()
                if let context = MacLedgerAccess.shared.container?.mainContext { try await MacNotifications.schedule(in:context) }
                if MacPreferences.defaults.bool(forKey:"v2_update_auto"), let release=MacUpdateService.shared.release { _ = try await MacNotifications.notifyUpdate(release) }
            } catch { message = error.localizedDescription }
        }
    }
    func openNotificationSettings() {
        if let url = URL(string:"x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    func openAccessibilitySettings() {
        if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    func openLoginSettings() { if !MacPreferences.isTesting { SMAppService.openSystemSettingsLoginItems() } }
    func requestAccessibility() { MacSelectionConversion.shared.requestAccessibility(); Task { await refresh() } }
}

struct MacPermissionSheetPresenter: ViewModifier {
    @ObservedObject private var permissions = MacPermissionCoordinator.shared
    func body(content: Content) -> some View {
        content.sheet(isPresented:$permissions.presented,onDismiss:{ permissions.finish() }) {
            MacPermissionsGuide().interactiveDismissDisabled()
        }
        .task { permissions.presentIfNeeded() }
    }
}

struct MacPermissionsGuide: View {
    @ObservedObject private var permissions = MacPermissionCoordinator.shared
    @ObservedObject private var services = MacAppServices.shared
    @AppStorage("v141_background") private var background = true
    var body: some View {
        MacFormShell(width:650) {
            HStack(spacing:12) {
                MacBrandIcon(size:44)
                VStack(alignment:.leading,spacing:5) {
                    Text("启动与权限设置").appFont(.dialogTitle,weight:.semibold)
                    Text("按需开启功能，您也可以稍后在设置中调整。").appFont(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        } fields: {
            VStack(spacing:12) {
                permissionRow("系统通知",icon:"bell",detail:"账目、预算、目标和软件更新共用通知授权。",status:permissions.notificationText) {
                    HStack {
                        Button("系统设置") { permissions.openNotificationSettings() }.accessibilityIdentifier("guideNotificationSettings")
                        Button("允许通知") { permissions.enableNotifications() }.disabled(permissions.requesting || permissions.notificationStatus == .authorized).accessibilityIdentifier("guideNotifications")
                    }
                }
                permissionRow("后台运行",icon:"app.badge",detail:"关闭主窗口后继续运行，无需额外系统授权。",status:background ? "已开启" : "未开启") {
                    Toggle("后台运行",isOn:$background).labelsHidden().toggleStyle(.switch).accessibilityIdentifier("guideBackground")
                }
                permissionRow("开机登录后启动",icon:"power",detail:"登录 Mac 后自动启动 FinTrack，可随时关闭。",status:services.loginEnabled ? "已开启" : (services.loginMessage ?? "未开启")) {
                    HStack {
                        Button("系统设置") { permissions.openLoginSettings() }.accessibilityIdentifier("guideLoginSettings")
                        Toggle("登录启动",isOn:Binding(get:{services.loginEnabled},set:{services.setLoginEnabled($0)})).labelsHidden().toggleStyle(.switch).accessibilityIdentifier("guideLogin")
                    }
                }
                permissionRow("选区金额换算",icon:"text.cursor",detail:"允许辅助功能后，可读取其他应用选中的金额。",status:permissions.accessibilityEnabled ? "已允许" : "尚未允许") {
                    HStack {
                        Button("系统设置") { permissions.openAccessibilitySettings() }.accessibilityIdentifier("guideAccessibilitySettings")
                        Button("请求授权") { permissions.requestAccessibility() }.accessibilityIdentifier("guideAccessibility")
                    }
                }
                if let message = permissions.message { Text(message).appFont(.caption).foregroundStyle(.orange) }
                Text("可以暂不开启。稍后可从设置中重新打开此引导，所有状态以系统当前设置为准。").appFont(.caption).foregroundStyle(.secondary)
            }
        } footer: {
            HStack {
                Button("稍后设置",role:.cancel) { permissions.finish() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("permissionsLater")
                Spacer()
                Button("完成") { permissions.finish() }.buttonStyle(MacStandardButtonStyle(primary:true)).keyboardShortcut(.defaultAction).accessibilityIdentifier("permissionsDone")
            }
        }.task { await permissions.refresh() }.accessibilityElement(children:.contain)
    }
    private func permissionRow<Action:View>(_ title:String,icon:String,detail:String,status:String,@ViewBuilder action:()->Action) -> some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:10) {
                MacSettingsIcon(symbol:icon,color:MacUI.accent,size:32)
                Text(title).appFont(.body,weight:.semibold)
                Spacer(minLength:8)
                action()
            }
            Text(detail).appFont(.caption).foregroundStyle(.secondary)
            Text(status).appFont(.caption,weight:.medium).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(MacOverviewStyle.filters,in:RoundedRectangle(cornerRadius:10))
    }
}
