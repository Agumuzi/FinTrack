import Foundation
import SwiftData
import UserNotifications
import AppKit

@MainActor
final class MacNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MacNotificationDelegate()
    func install() { if !MacPreferences.isTesting { UNUserNotificationCenter.current().delegate = self } }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { await MainActor.run { MacPermissionCoordinator.notificationsEnabled ? [.banner, .sound, .list] : [] } }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let route = response.notification.request.content.userInfo["route"] as? String ?? "recurring"
        await MainActor.run {
            if route == "updates" { MacUpdateService.shared.openFromNotification(); return }
            MacApplicationRuntime.shared.showMain(settings: route == "goals" || route == "budgets")
            if route == "goals" || route == "budgets" { MacPreferences.defaults.set(route, forKey: "v2_settings_page") }
            else { FinTrackMacApp.workspace.section = route == "deposits" ? .deposits : .recurring }
        }
    }
}

enum MacNotifications {
    struct Plan {
        var id: String; var title: String; var body: String; var date: Date; var route: String
    }
    private static var scheduling = false
    private static var reschedule = false
    static func clear() {
        guard !MacPreferences.isTesting else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { owned($0) })
        }
    }
    private nonisolated static func owned(_ id: String) -> Bool {
        ["deposit-", "recurring-", "goal-", "budget-"].contains { id.hasPrefix($0) }
    }
    static func disableAll() {
        guard !MacPreferences.isTesting else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            let ids = pending.map(\.identifier).filter { owned($0) || $0.hasPrefix("update-") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            // Cancelled future occurrences must be eligible when reminders are re-enabled.
            var history = Set(MacPreferences.defaults.stringArray(forKey: "v141_notification_history") ?? [])
            history.subtract(ids); MacPreferences.defaults.set(Array(history).sorted(), forKey: "v141_notification_history")
        }
    }
    static func authorizationLabel() async -> String {
        await MacPermissionCoordinator.shared.refresh()
        return MacPermissionCoordinator.shared.notificationText
    }
    static func authorizeAndSchedule(in context: ModelContext) async throws {
        try await MacPermissionCoordinator.shared.requestNotifications()
        try await schedule(in:context)
    }
    static func updateRequest(_ release: MacUpdateRelease) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "FinTrack 有新版本"
        content.body = "v\(release.version) 已可下载，点击查看更新。"
        content.sound = .default; content.userInfo = ["route":"updates","build":release.build]
        return UNNotificationRequest(identifier:"update-\(release.build)",content:content,trigger:UNTimeIntervalNotificationTrigger(timeInterval:1,repeats:false))
    }
    @discardableResult static func notifyUpdate(_ release: MacUpdateRelease) async throws -> Bool {
        guard !MacPreferences.isTesting, MacPermissionCoordinator.notificationsEnabled else { return false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return false }
        let key = "v142_update_notice_build"
        guard MacPreferences.defaults.integer(forKey:key) < release.build else { return true }
        guard MacPermissionCoordinator.notificationsEnabled else { return false }
        try await center.add(updateRequest(release))
        guard MacPermissionCoordinator.notificationsEnabled else { center.removePendingNotificationRequests(withIdentifiers: ["update-\(release.build)"]); return false }
        MacPreferences.defaults.set(release.build,forKey:key)
        return true
    }
    static func cancelUpdateNotices() {
        guard !MacPreferences.isTesting else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in center.removePendingNotificationRequests(withIdentifiers:requests.map(\.identifier).filter{$0.hasPrefix("update-")}) }
        center.getDeliveredNotifications { notices in center.removeDeliveredNotifications(withIdentifiers:notices.map{$0.request.identifier}.filter{$0.hasPrefix("update-")}) }
    }
    static func plans(in context: ModelContext, now: Date = Date(), calendar: Calendar = .current) throws -> [Plan] {
        let d = MacPreferences.defaults
        func enabled(_ key: String) -> Bool { d.object(forKey: key) as? Bool ?? true }
        func reminder(_ date: Date, days: Int, hour: Int, minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -days, to: date) ?? date
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        var result: [Plan] = []
        let deposits = try context.fetch(FetchDescriptor<DepositRecord>())
        let rules = try context.fetch(FetchDescriptor<RecurringTransaction>())
        for record in deposits where record.deletedAt == nil && record.isActive && record.notificationsEnabled {
            result.append(Plan(id: "deposit-\(record.id)-\(Int64(record.maturityDate.timeIntervalSince1970))", title: record.bankName,
                body: "存款即将到期，请核对到账与结息。", date: reminder(record.maturityDate, days: record.reminderDaysBefore, hour: record.reminderHour, minute: record.reminderMinute), route: "deposits"))
        }
        for rule in rules where enabled("v2_remind_recurring") && rule.deletedAt == nil && rule.isActive && rule.notificationsEnabled && (rule.endDate == nil || rule.nextExecutionDate <= rule.endDate!) {
            result.append(Plan(id: "recurring-\(rule.id)-\(Int64(rule.nextExecutionDate.timeIntervalSince1970))", title: rule.title,
                body: "周期收支计划即将发生，请核对账目。", date: reminder(rule.nextExecutionDate, days: rule.reminderDaysBefore, hour: rule.reminderHour, minute: rule.reminderMinute), route: "recurring"))
        }
        let rows = try context.fetch(FetchDescriptor<Transaction>())
        let loans = try context.fetch(FetchDescriptor<LoanRule>())
        let currency = d.string(forKey: "base_currency") ?? "USD"
        let codes = Set(rows.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode) + deposits.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode) + loans.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode) + rules.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        guard codes.isEmpty || codes == [currency] else { return result }
        if enabled("v2_remind_goals") {
            let profile = try context.fetch(FetchDescriptor<FinancialProfile>()).first { $0.deletedAt == nil }
            let net = MacFinancialSettings.snapshot(profile: profile, transactions: rows, loans: loans, deposits: deposits, currency: currency, asOf: now).netWorth
            let goals = try context.fetch(FetchDescriptor<Goal>())
            for goal in goals where goal.deletedAt == nil && !goal.isPaused && !goal.isAccomplished && !goal.isCompleted(currentNetWorth: net, baselineNetWorth: Goal.baselineNetWorth(from: profile)) {
                if let target = goal.targetTime.planningBoundary() {
                    result.append(Plan(id: "goal-\(goal.id)-\(Int64(target.timeIntervalSince1970))", title: goal.title, body: "目标临近期望时间，请查看进度。", date: reminder(target, days: 30, hour: 9, minute: 0), route: "goals"))
                }
            }
        }
        if enabled("v2_remind_budgets") {
            let budgets: [MacBudget] = MacSettingsStore.load("v2_budgets", fallback: [])
            let categories = try context.fetch(FetchDescriptor<Category>())
            let snapshot = MacBudgetSpendingSnapshot(rows: rows, categories: categories)
            for budget in budgets where budget.enabled && budget.currency == currency && budget.month == MacBudgetData.month(now) && budget.amount > 0 {
                let ratio = snapshot.spent(budget) / budget.amount
                if ratio >= 0.8 {
                    let level = ratio >= 1 ? 100 : 80
                    result.append(Plan(id: "budget-\(budget.id)-\(budget.month)-\(level)", title: "预算提醒", body: "本月一项预算已使用 \(level)% 或以上。", date: now, route: "budgets"))
                }
            }
        }
        return result.sorted { $0.date < $1.date }
    }
    static func schedule(in context: ModelContext) async throws {
        guard !MacPreferences.isTesting else { return }
        guard MacPermissionCoordinator.notificationsEnabled else { disableAll(); return }
        if scheduling { reschedule = true; return }
        scheduling = true
        defer {
            scheduling = false
            if reschedule { reschedule = false; Task { try? await schedule(in: context) } }
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let plans = try plans(in: context)
        let desired = Set(plans.map(\.id))
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { owned($0) && !desired.contains($0) })
        let pendingIDs = Set(pending.map(\.identifier))
        let delivered = Set(await center.deliveredNotifications().map { $0.request.identifier })
        var notified = Set(MacPreferences.defaults.stringArray(forKey: "v141_notification_history") ?? [])
        // Historical versions recorded scheduled requests as delivered. Pending
        // requests may still be updated, cancelled, or enabled again.
        notified.subtract(pendingIDs); notified.formUnion(delivered)
        var count = pending.filter { desired.contains($0.identifier) }.count
        for plan in plans where !notified.contains(plan.id) && (pendingIDs.contains(plan.id) || count < 60) {
            let content = UNMutableNotificationContent()
            content.title = plan.title; content.body = plan.body; content.sound = .default; content.userInfo = ["route": plan.route]
            let trigger: UNNotificationTrigger = plan.date <= Date() ? UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false) : UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.date), repeats: false)
            guard MacPermissionCoordinator.notificationsEnabled else { disableAll(); return }
            try await center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger))
            guard MacPermissionCoordinator.notificationsEnabled else { disableAll(); return }
            if !pendingIDs.contains(plan.id) { count += 1 }
        }
        // Keep bounded occurrence identifiers only; clearing a delivered banner must not resend it.
        MacPreferences.defaults.set(Array(notified).sorted().suffix(2000).map { $0 }, forKey: "v141_notification_history")
    }
}
