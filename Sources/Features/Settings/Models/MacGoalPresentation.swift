import Foundation

struct MacGoalPresentation: Codable, Equatable {
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
        guard let date = time.resolvedDate() else { return L10n.text("mac.goalPresentation.label.55c3304e24") }
        switch time.precision {
        case .year: return date.formatted(.dateTime.year().locale(L10n.locale))
        case .month: return date.formatted(.dateTime.year().month(.wide).locale(L10n.locale))
        case .day: return MacDateDisplay.string(date)
        }
    }
}
