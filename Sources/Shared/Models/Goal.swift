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
        syncVersion: Int = 1
    ) {
        self.id = id
        self.ownerUID = ownerUID
        self.title = title
        self.targetAmount = targetAmount
        self.startDate = startDate
        self.deadline = targetDate
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
        return min(max(raw, 1), 100)
    }

    func isCompleted(currentNetWorth: Double, baselineNetWorth: Double) -> Bool {
        clampedProgressValue(currentNetWorth: currentNetWorth, baselineNetWorth: baselineNetWorth) >= 1
    }
}
