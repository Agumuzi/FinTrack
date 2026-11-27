import Foundation

nonisolated struct GoalProgressRule {
    let target: Double
    let current: Double

    init(target: Double, netWorth: Double, creationNetWorth: Double, includesCurrentAssets: Bool) {
        self.target = target
        current = includesCurrentAssets ? netWorth : netWorth - creationNetWorth
    }

    var completed: Bool { current.isFinite && target.isFinite && current >= target }
    var remaining: Double { max(0, target - current) }
    var fraction: Double {
        if completed { return 1 }
        guard current.isFinite, target.isFinite, target > 0 else { return 0 }
        return max(0, current / target)
    }
    var percent: Int { completed ? 100 : min(99, Int((fraction * 100).rounded())) }
}
