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
        if MacPreferences.isTesting {
            #if FINTRACK_LOCAL_VALIDATION
            let granted = ProcessInfo.processInfo.environment["FINTRACK_PERMISSION_FIXTURE"] == "granted"
            notificationStatus = granted ? .authorized : .notDetermined; accessibilityEnabled = granted
            #endif
            notificationText = "隔离测试：不更改系统权限"; return
        }
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch notificationStatus {
        case .authorized,.provisional,.ephemeral: notificationText = "已允许"
        case .denied: notificationText = "已关闭，可在系统设置中开启"
        case .notDetermined: notificationText = "尚未开启"
        @unknown default: notificationText = "需要检查系统设置"
        }
        if !Self.notificationsEnabled { notificationText += " · 本应用通知已关闭" }
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
                guard Self.notificationsEnabled else { return }
                if let context = MacLedgerAccess.shared.container?.mainContext { try await MacNotifications.schedule(in:context) }
                if MacPreferences.defaults.bool(forKey:"v2_update_auto"), let release=MacUpdateService.shared.release { _ = try await MacNotifications.notifyUpdate(release) }
            } catch { message = error.localizedDescription }
        }
    }
    static var notificationsEnabled: Bool { MacPreferences.defaults.object(forKey: "notifications_enabled") as? Bool ?? true }
    static var selectionEnabled: Bool { MacPreferences.defaults.object(forKey: "selection_conversion_enabled") as? Bool ?? true }
    var notificationsActive: Bool { Self.notificationsEnabled && [.authorized, .provisional].contains(notificationStatus) }
    var selectionActive: Bool { Self.selectionEnabled && accessibilityEnabled }
    func setNotificationsEnabled(_ enabled: Bool) {
        MacPreferences.defaults.set(enabled, forKey: "notifications_enabled"); objectWillChange.send()
        if !enabled { MacNotifications.disableAll(); return }
        guard !MacPreferences.isTesting else { message = "隔离测试不修改系统授权。"; return }
        Task {
            await refresh()
            guard Self.notificationsEnabled else { return }
            if notificationStatus == .notDetermined { try? await requestNotifications() }
            if notificationsActive { enableNotifications() }
            else { openNotificationSettings() }
        }
    }
    func setSelectionEnabled(_ enabled: Bool) {
        MacPreferences.defaults.set(enabled, forKey: "selection_conversion_enabled"); objectWillChange.send()
        MacSelectionConversion.shared.configure()
        if !enabled { MacSelectionConversion.shared.dismiss(); return }
        guard !MacPreferences.isTesting else { message = "隔离测试不修改系统授权。"; return }
        if !AXIsProcessTrusted() { openAccessibilitySettings() }
        Task { await refresh() }
    }
    func setLoginEnabled(_ enabled: Bool) {
        servicesLogin(enabled)
        if enabled && !MacPreferences.isTesting && MacAppServices.shared.loginMessage == nil { openLoginSettings() }
        else if enabled && !MacPreferences.isTesting && SMAppService.mainApp.status == .requiresApproval { openLoginSettings() }
    }
    private func servicesLogin(_ enabled: Bool) { MacAppServices.shared.setLoginEnabled(enabled) }
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
        MacFormShell(width: 600) {
            HStack(spacing: 12) {
                MacBrandIcon(size: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text("启动与权限设置").appFont(.dialogTitle, weight: .semibold)
                    Text("开启所需功能，授权后状态会自动更新。").appFont(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        } fields: {
            VStack(spacing: 10) {
                VStack(spacing: 0) {
                    row("系统通知", icon: "bell", detail: "账目、预算、目标和软件更新共用通知。", active: permissions.notificationsActive, status: notificationStatus, id: "guideNotifications", value: Binding(get: { permissions.notificationsActive }, set: { permissions.setNotificationsEnabled($0) }))
                    Divider()
                    row("后台运行", icon: "app.badge", detail: "关闭主窗口后继续运行，无需额外系统授权。", active: background, status: background ? "已开启" : "已关闭", id: "guideBackground", value: $background)
                    Divider()
                    row("开机登录后启动", icon: "power", detail: "登录 Mac 后自动启动 FinTrack。", active: services.loginEnabled, status: services.loginEnabled ? "已开启" : (services.loginMessage ?? "已关闭"), id: "guideLogin", value: Binding(get: { services.loginEnabled }, set: { permissions.setLoginEnabled($0) }))
                    Divider()
                    row("选区金额换算", icon: "text.cursor", detail: "读取其他应用选中的金额并快速换算。", active: permissions.selectionActive, status: selectionStatus, id: "guideAccessibility", value: Binding(get: { permissions.selectionActive }, set: { permissions.setSelectionEnabled($0) }))
                }.padding(.horizontal, 14).background(MacOverviewStyle.filters, in: RoundedRectangle(cornerRadius: 12))
                if let message = permissions.message { Text(message).appFont(.caption).foregroundStyle(.orange) }
                Text("开启需要授权的功能时会前往系统设置。关闭会立即停用本应用功能；通知和辅助功能的系统授权需在 macOS 中撤销。").appFont(.caption).foregroundStyle(.secondary)
            }
        } footer: {
            HStack {
                Button("稍后设置", role: .cancel) { permissions.finish() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("permissionsLater")
                Spacer()
                Button("完成") { permissions.finish() }.buttonStyle(MacStandardButtonStyle(primary: true)).keyboardShortcut(.defaultAction).accessibilityIdentifier("permissionsDone")
            }
        }.task {
            while !Task.isCancelled { await permissions.refresh(); do { try await Task.sleep(for: .seconds(1)) } catch { break } }
        }.accessibilityElement(children: .contain)
    }
    private var notificationStatus: String {
        if permissions.notificationsActive { return "已开启 · 系统已授权" }
        if !MacPermissionCoordinator.notificationsEnabled { return "已停用通知" + ([.authorized, .provisional].contains(permissions.notificationStatus) ? " · 系统授权仍保留" : "") }
        return "尚未获得系统授权"
    }
    private var selectionStatus: String {
        if permissions.selectionActive { return "已开启 · 辅助功能已授权" }
        if !MacPermissionCoordinator.selectionEnabled { return "已停用选区读取" + (permissions.accessibilityEnabled ? " · 系统授权仍保留" : "") }
        return "尚未获得辅助功能授权"
    }
    private func row(_ title: String, icon: String, detail: String, active: Bool, status: String, id: String, value: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            MacSettingsIcon(symbol: icon, color: MacUI.accent, size: 32)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).appFont(.body, weight: .semibold)
                Text(detail).appFont(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) { Circle().fill(active ? Color.green : Color.secondary.opacity(0.4)).frame(width: 7, height: 7).accessibilityHidden(true); Text(status).appFont(.caption, weight: .medium).foregroundStyle(active ? Color.green : Color.secondary) }.accessibilityIdentifier(id + "Status")
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).accessibilityIdentifier(id)
        }.padding(.vertical, 13)
    }
}
