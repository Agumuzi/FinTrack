import SwiftUI
import SwiftData
import AppKit
import ServiceManagement
import Combine

/// Application-owned work survives main-window closure. No periodic ledger polling.
@MainActor
final class MacAppServices: ObservableObject {
    static let shared = MacAppServices()
    @Published private(set) var postingError: String?
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginMessage: String?
    private var dailyTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var observers: [AnyCancellable] = []
    private var started = false
    private var signature = ""

    static func nextPostingDate(after now: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: now, matching: DateComponents(hour: 9, minute: 0, second: 0), matchingPolicy: .nextTime)!
    }
    /// The occurrence's original date remains its idempotency identity.
    static func eligibleThrough(_ now: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: now)
        let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: start)!
        let boundary = now >= nine ? calendar.date(byAdding: .day, value: 1, to: start)! : start
        return boundary.addingTimeInterval(-0.001)
    }
    func refreshLoginStatus() {
        guard !MacPreferences.isTesting else { loginEnabled = false; return }
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginMessage = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置的登录项中允许 FinTrack。" : nil
    }
    func setLoginEnabled(_ enabled: Bool) {
        guard !MacPreferences.isTesting else { loginMessage = "测试副本不修改系统登录项。"; return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
        } catch { refreshLoginStatus(); loginMessage = "登录启动设置未完成：" + error.localizedDescription }
    }
    func start() {
        guard !started, !MacPreferences.isTesting else { return }; started = true
        MacNotificationDelegate.shared.install()
        refreshLoginStatus()
        observers.append(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).debounce(for: .milliseconds(250), scheduler: RunLoop.main).sink { [weak self] _ in
            Task { @MainActor in self?.preferencesChanged() }
        })
        for name in [Notification.Name.NSSystemTimeZoneDidChange, .NSCalendarDayChanged, Notification.Name("NSSystemClockDidChangeNotification"), MacSettingsStore.restoreCompleted] {
            observers.append(NotificationCenter.default.publisher(for: name).sink { [weak self] _ in Task { @MainActor in self?.restartDaily() } })
        }
        observers.append(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in Task { @MainActor in self?.restartDaily() } })
        observers.append(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in Task { @MainActor in self?.refreshLoginStatus() } })
        observers.append(NotificationCenter.default.publisher(for: ModelContext.didSave).debounce(for: .milliseconds(400), scheduler: RunLoop.main).sink { _ in
            Task { @MainActor in
                if let context = MacLedgerAccess.shared.container?.mainContext { try? await MacNotifications.schedule(in: context) }
            }
        })
        preferencesChanged()
        updateTask = Task { await MacUpdateService.shared.runAutomaticChecks() }
    }
    private func preferencesChanged() {
        let d = MacPreferences.defaults
        let next = ["fintrack_auto_posting", "v13_auto_deposit_posting", "v141_background", "v2_remind_recurring", "v2_remind_goals", "v2_remind_budgets"].map { String(describing: d.object(forKey: $0)) }.joined(separator: ":")
        guard signature != next else { return }; signature = next
        restartDaily()
    }
    func restartDaily() {
        guard !MacPreferences.isTesting else { return }
        dailyTask?.cancel()
        dailyTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.runDue()
                do { try await Task.sleep(for: .seconds(max(1, Self.nextPostingDate(after: Date()).timeIntervalSinceNow))) }
                catch { return }
            }
        }
    }
    private func runDue() async {
        guard !Task.isCancelled else { return }
        let access = MacLedgerAccess.shared; access.load()
        guard let context = access.container?.mainContext else { return }
        let d = MacPreferences.defaults
        postingError = await MacAutomaticPosting.run(in: context, now: Self.eligibleThrough(Date()), includeRules: d.bool(forKey: "fintrack_auto_posting"), includeDeposits: d.object(forKey: "v13_auto_deposit_posting") as? Bool ?? true, estimateDeposits: true)
        do { try await MacNotifications.schedule(in: context) } catch { postingError = "通知排程未完成：" + error.localizedDescription }
    }
}
