import Foundation
import SwiftData
import UserNotifications

enum MacNotifications {
    static func clear() {
        guard !MacPreferences.isTesting else { return }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    static func authorizeAndSchedule(in context: ModelContext) async throws {
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else { return }
        try await schedule(in: context)
    }
    static func schedule(in context: ModelContext) async throws {
        guard !MacPreferences.isTesting else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("deposit-") || $0.hasPrefix("recurring-") })
        func add(id: String, title: String, date: Date) async throws {
            guard date > Date() else { return }
            let content = UNMutableNotificationContent()
            content.title = title; content.body = MacLocalization.value("A finance entry is due"); content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            try await center.add(UNNotificationRequest(identifier: id, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
        for record in try context.fetch(FetchDescriptor<DepositRecord>()) where record.deletedAt == nil && record.isActive && record.notificationsEnabled {
            let date = Calendar.current.date(byAdding: .day, value: -record.reminderDaysBefore, to: record.maturityDate)!
            let due = Calendar.current.date(bySettingHour: record.reminderHour, minute: record.reminderMinute, second: 0, of: date)!
            try await add(id: "deposit-\(record.id)", title: record.bankName, date: due)
        }
        for rule in try context.fetch(FetchDescriptor<RecurringTransaction>()) where rule.deletedAt == nil && rule.isActive && rule.notificationsEnabled {
            let date = Calendar.current.date(byAdding: .day, value: -rule.reminderDaysBefore, to: rule.nextExecutionDate)!
            let due = Calendar.current.date(bySettingHour: rule.reminderHour, minute: rule.reminderMinute, second: 0, of: date)!
            try await add(id: "recurring-\(rule.id)", title: rule.title, date: due)
        }
    }
}
