import Foundation

nonisolated enum RecurringScheduleRule {
    static let batchLimit = 24

    struct Batch {
        let dates: [Date]
        let next: Date
    }

    static func batch(start: Date, through cutoff: Date, end: Date?, advance: (Date) throws -> Date) rethrows -> Batch {
        var dates: [Date] = []
        var cursor = start
        while dates.count < batchLimit, cursor <= cutoff, end.map({ cursor <= $0 }) ?? true {
            dates.append(cursor)
            cursor = try advance(cursor)
        }
        return Batch(dates: dates, next: cursor)
    }

    static func nextDate(after date: Date, interval: Int, component: Calendar.Component,
                         anchorDay: Int?, calendar: Calendar) -> Date? {
        guard (1...365).contains(interval),
              let advanced = calendar.date(byAdding: component, value: interval, to: date) else { return nil }
        let result: Date
        if let anchorDay, component == .month || component == .year,
           let days = calendar.range(of: .day, in: .month, for: advanced) {
            let delta = min(anchorDay, days.count) - calendar.component(.day, from: advanced)
            guard let anchored = calendar.date(byAdding: .day, value: delta, to: advanced) else { return nil }
            result = anchored
        } else {
            result = advanced
        }
        return result > date ? result : nil
    }
}
