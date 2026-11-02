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
    @Published private(set) var notificationText = L10n.text("mac.permissionCoordinator.notificationText.cb14844ee3")
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
            notificationText = L10n.text("mac.permissionCoordinator.refresh.10aa7e5bbc"); return
        }
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch notificationStatus {
        case .authorized,.provisional,.ephemeral: notificationText = L10n.text("mac.permissionCoordinator.refresh.75d889ac43")
        case .denied: notificationText = L10n.text("mac.permissionCoordinator.refresh.70036646ae")
        case .notDetermined: notificationText = L10n.text("mac.permissionCoordinator.refresh.cb14844ee3")
        @unknown default: notificationText = L10n.text("mac.permissionCoordinator.refresh.01debe0d2d")
        }
        if !Self.notificationsEnabled { notificationText += L10n.text("mac.permissionCoordinator.refresh.f02fa8bde3") }
        accessibilityEnabled = AXIsProcessTrusted()
        MacAppServices.shared.refreshLoginStatus()
    }
    func presentIfNeeded() {
        let optedInTest = ProcessInfo.processInfo.environment["FINTRACK_PERMISSIONS_INTRO_TEST"] == "1"
        guard !MacPreferences.isTesting || optedInTest else { return }
        guard !MacPreferences.defaults.bool(forKey:Self.introKey), MacUpdatePrompt.shared.stage == nil, !MacUpdateService.shared.handlingNotification else { return }
        Task { await refresh(); if !MacPreferences.defaults.bool(forKey: Self.introKey) { presented = true } }
    }
    func open() { MacApplicationRuntime.shared.showMain(); Task { await refresh(); presented = true } }
    func finish() { MacPreferences.defaults.set(true,forKey:Self.introKey); presented = false }
    func requestNotifications() async throws {
        guard !MacPreferences.isTesting else { message = L10n.text("mac.permissionCoordinator.requestNotifications.ed82159326"); return }
        guard !requesting else { return }; requesting = true; defer { requesting = false }
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge])
            await refresh()
            guard allowed else { throw MacSettingsFailure.invalid(L10n.text("mac.permissionCoordinator.requestNotifications.12a7fc4301")) }
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
        guard !MacPreferences.isTesting else { message = L10n.text("mac.permissionCoordinator.setNotificationsEnabled.b5b79d19db"); return }
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
        guard !MacPreferences.isTesting else { message = L10n.text("mac.permissionCoordinator.setSelectionEnabled.b5b79d19db"); return }
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
    @ObservedObject private var localizationState = LocalizationController.shared
    @ObservedObject private var permissions = MacPermissionCoordinator.shared
    @ObservedObject private var services = MacAppServices.shared
    @AppStorage("v141_background") private var background = true
    var body: some View {
        MacFormShell(width: 600) {
            HStack(spacing: 12) {
                MacBrandIcon(size: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("mac.permissionCoordinator.MacFormShell.b178f5419e")).appFont(.dialogTitle, weight: .semibold)
                    Text(L10n.text("mac.permissionCoordinator.MacFormShell.8d683e96ab")).appFont(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        } fields: {
            VStack(spacing: 10) {
                VStack(spacing: 0) {
                    row(L10n.text("mac.permissionCoordinator.row.94b7513ead"), icon: "bell", detail: L10n.text("mac.permissionCoordinator.row.90d358efc9"), active: permissions.notificationsActive, status: notificationStatus, id: "guideNotifications", value: Binding(get: { permissions.notificationsActive }, set: { permissions.setNotificationsEnabled($0) }))
                    Divider()
                    row(L10n.text("mac.permissionCoordinator.row.517484e7f2"), icon: "app.badge", detail: L10n.text("mac.permissionCoordinator.row.91b6acebf8"), active: background, status: background ? L10n.text("mac.permissionCoordinator.row.8a4ef3e48e") : L10n.text("mac.permissionCoordinator.row.6744b4c6a9"), id: "guideBackground", value: $background)
                    Divider()
                    row(L10n.text("mac.permissionCoordinator.row.9021894921"), icon: "power", detail: L10n.text("mac.permissionCoordinator.row.4470027d76"), active: services.loginEnabled, status: services.loginEnabled ? L10n.text("mac.permissionCoordinator.row.8a4ef3e48e") : (services.loginMessage ?? L10n.text("mac.permissionCoordinator.row.6744b4c6a9")), id: "guideLogin", value: Binding(get: { services.loginEnabled }, set: { permissions.setLoginEnabled($0) }))
                    Divider()
                    row(L10n.text("mac.permissionCoordinator.row.03a46977ef"), icon: "text.cursor", detail: L10n.text("mac.permissionCoordinator.row.8a6a53c0fe"), active: permissions.selectionActive, status: selectionStatus, id: "guideAccessibility", value: Binding(get: { permissions.selectionActive }, set: { permissions.setSelectionEnabled($0) }))
                }.padding(.horizontal, 14).background(MacOverviewStyle.filters, in: RoundedRectangle(cornerRadius: 12))
                if let message = permissions.message { Text(message).appFont(.caption).foregroundStyle(.orange) }
                Text(L10n.text("mac.permissionCoordinator.MacFormShell.782c40df93")).appFont(.caption).foregroundStyle(.secondary)
            }
        } footer: {
            HStack {
                Button(L10n.text("mac.permissionCoordinator.MacFormShell.882574c28e"), role: .cancel) { permissions.finish() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("permissionsLater")
                Spacer()
                Button(L10n.text("mac.permissionCoordinator.MacFormShell.c0b3fbff51")) { permissions.finish() }.buttonStyle(MacStandardButtonStyle(primary: true)).keyboardShortcut(.defaultAction).accessibilityIdentifier("permissionsDone")
            }
        }.task {
            while !Task.isCancelled { await permissions.refresh(); do { try await Task.sleep(for: .seconds(1)) } catch { break } }
        }.accessibilityElement(children: .contain)
    }
    private var notificationStatus: String {
        if permissions.notificationsActive { return L10n.text("mac.permissionCoordinator.notificationStatus.a4024d23cf") }
        if !MacPermissionCoordinator.notificationsEnabled { return L10n.text("mac.permissionCoordinator.notificationStatus.8f185d03d1") + ([.authorized, .provisional].contains(permissions.notificationStatus) ? L10n.text("mac.permissionCoordinator.notificationStatus.9cee6c93b4") : "") }
        return L10n.text("mac.permissionCoordinator.notificationStatus.d7ed177c2d")
    }
    private var selectionStatus: String {
        if permissions.selectionActive { return L10n.text("mac.permissionCoordinator.selectionStatus.a560b9ff5d") }
        if !MacPermissionCoordinator.selectionEnabled { return L10n.text("mac.permissionCoordinator.selectionStatus.c1c5e533c4") + (permissions.accessibilityEnabled ? L10n.text("mac.permissionCoordinator.selectionStatus.9cee6c93b4") : "") }
        return L10n.text("mac.permissionCoordinator.selectionStatus.e5b00fa1e4")
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
