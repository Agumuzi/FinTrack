//
//  Goal.swift
//  FinTrack
//
//  Created by Thomas Tao on 2026/3/6.
//

import Foundation
import SwiftData

@Model
final class Goal {
    var id: UUID
    var ownerUID: String?
    var title: String
    var targetAmount: Double
    var startDate: Date
    var deadline: Date?
    /// Optional metadata: old nonempty deadlines retain their original exact-day meaning.
    var targetDatePrecisionRaw: String? = nil
    var targetDateValueRaw: String? = nil
    var includesCurrentAssets: Bool
    var creationNetWorth: Double
    var isAccomplished: Bool
    var isPaused: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var lastModifiedDeviceID: String
    var syncVersion: Int

    init(
        id: UUID = UUID(),
        ownerUID: String? = nil,
        title: String,
        targetAmount: Double,
        startDate: Date = Date(),
        targetDate: Date? = nil,
        includesCurrentAssets: Bool = true,
        creationNetWorth: Double = 0,
        isAccomplished: Bool = false,
        isPaused: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        lastModifiedDeviceID: String = SyncMetadataDefaults.currentDeviceID,
        syncVersion: Int = 1,
        targetDatePrecisionRaw: String? = nil,
        targetDateValueRaw: String? = nil
    ) {
        self.id = id
        self.ownerUID = ownerUID
        self.title = title
        self.targetAmount = targetAmount
        self.startDate = startDate
        self.deadline = targetDate
        self.targetDatePrecisionRaw = targetDatePrecisionRaw
        self.targetDateValueRaw = targetDateValueRaw
        self.includesCurrentAssets = includesCurrentAssets
        self.creationNetWorth = creationNetWorth
        self.isAccomplished = isAccomplished
        self.isPaused = isPaused
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastModifiedDeviceID = lastModifiedDeviceID
        self.syncVersion = syncVersion
    }
}

extension Goal {
    static func baselineNetWorth(from profile: FinancialProfile?) -> Double {
        guard let profile else { return 0 }
        return profile.initialAssets + normalizedDebt(profile.initialDebt)
    }

    static func normalizedDebt(_ debt: Double) -> Double {
        debt <= 0 ? debt : -debt
    }

    private func effectiveBaselineNetWorth(profileBaselineNetWorth: Double) -> Double {
        includesCurrentAssets ? profileBaselineNetWorth : creationNetWorth
    }

    private func effectiveTargetAmount(profileBaselineNetWorth: Double) -> Double {
        includesCurrentAssets ? targetAmount : creationNetWorth + targetAmount
    }

    func progressValue(currentNetWorth: Double, baselineNetWorth: Double) -> Double {
        let effectiveBaseline = effectiveBaselineNetWorth(profileBaselineNetWorth: baselineNetWorth)
        let effectiveTarget = effectiveTargetAmount(profileBaselineNetWorth: baselineNetWorth)
        let distance = effectiveTarget - effectiveBaseline

        if distance == 0 {
            return currentNetWorth == effectiveTarget ? 1 : 0
        }

        return (currentNetWorth - effectiveBaseline) / distance
    }

    func clampedProgressValue(currentNetWorth: Double, baselineNetWorth: Double) -> Double {
        min(max(progressValue(currentNetWorth: currentNetWorth, baselineNetWorth: baselineNetWorth), 0), 1)
    }

    func displayPercent(currentNetWorth: Double, baselineNetWorth: Double) -> Int {
        let raw = Int(round(clampedProgressValue(currentNetWorth: currentNetWorth, baselineNetWorth: baselineNetWorth) * 100))
        return min(max(raw, 0), 100)
    }

    func isCompleted(currentNetWorth: Double, baselineNetWorth: Double) -> Bool {
        clampedProgressValue(currentNetWorth: currentNetWorth, baselineNetWorth: baselineNetWorth) >= 1
    }
}


/// Input precision is distinct from a planning boundary and never changes accomplishment.
enum TargetDatePrecision: String, Codable, CaseIterable {
    case year, month, day
    var title: String { switch self { case .year: "年"; case .month: "年月"; case .day: "年月日" } }
}

struct GoalTargetTime {
    var date: Date?
    var precision: TargetDatePrecision = .day
    var valueRaw: String? = nil

    static func capturedValue(_ date: Date, precision: TargetDatePrecision, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1, precision == .year ? 1 : parts.month ?? 1, precision == .day ? parts.day ?? 1 : 1)
    }
    static func components(_ raw: String, precision: TargetDatePrecision) -> DateComponents? {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard parts.count == 3, (1...9999).contains(parts[0]), (1...12).contains(parts[1]), (1...31).contains(parts[2]),
              String(format: "%04d-%02d-%02d", parts[0], parts[1], parts[2]) == raw,
              precision != .year || (parts[1] == 1 && parts[2] == 1), precision != .month || parts[2] == 1 else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let value = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        guard let date = calendar.date(from: value), calendar.component(.year, from: date) == parts[0],
              calendar.component(.month, from: date) == parts[1], calendar.component(.day, from: date) == parts[2] else { return nil }
        return value
    }
    func resolvedDate(calendar: Calendar = .current) -> Date? {
        guard date != nil, let valueRaw, let parts = Self.components(valueRaw, precision: precision) else { return date }
        return calendar.date(from: parts) ?? date
    }

    func planningBoundary(calendar: Calendar = .current) -> Date? {
        guard let date = resolvedDate(calendar: calendar) else { return nil }
        let component: Calendar.Component
        switch precision { case .year: component = .year; case .month: component = .month; case .day:
            return valueRaw == nil ? date : calendar.dateInterval(of: .day, for: date)?.end.addingTimeInterval(-1)
        }
        return calendar.dateInterval(of: component, for: date)?.end.addingTimeInterval(-1)
    }
    func remainingMonths(from now: Date, calendar: Calendar = .current) -> Int? {
        guard let boundary = planningBoundary(calendar: calendar) else { return nil }
        return max(0, calendar.dateComponents([.month], from: now, to: boundary).month ?? 0)
    }
}

extension Goal {
    var targetTime: GoalTargetTime {
        GoalTargetTime(date: deadline, precision: targetDatePrecisionRaw.flatMap(TargetDatePrecision.init(rawValue:)) ?? .day, valueRaw: targetDateValueRaw)
    }
}
