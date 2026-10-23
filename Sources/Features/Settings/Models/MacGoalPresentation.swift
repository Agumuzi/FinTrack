import Foundation

struct MacGoalPresentation: Codable {
    var icon = "target"
    var color = "blue"
    var priority = "普通"
    var note = ""
}


@MainActor
enum MacGoalTargetDate {
    static func label(_ goal: Goal) -> String {
        label(goal.targetTime)
    }
    static func label(_ time: GoalTargetTime) -> String {
        guard let date = time.resolvedDate() else { return "未设期望时间" }
        switch time.precision {
        case .year: return "\(Calendar.current.component(.year, from: date)) 年"
        case .month: return "\(Calendar.current.component(.year, from: date)) 年 \(Calendar.current.component(.month, from: date)) 月"
        case .day: return MacDateDisplay.string(date)
        }
    }
}
