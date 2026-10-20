import Foundation

nonisolated enum MacFXDates {
    static var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    static func tag(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year,.month,.day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func day(_ tag: String, calendar: Calendar = utc) -> Date? {
        let parts = tag.split(separator: "-").compactMap { Int($0) }
        guard tag.count == 10, parts.count == 3,
              let value = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              self.tag(value, calendar: calendar) == tag else { return nil }
        return value
    }
    static func instant(_ time: MacFXQuoteTime) -> Date? {
        switch time {
        case .instant(let date, let zone): return TimeZone(identifier: zone) != nil ? date : nil
        case .day(let text, let zone):
            guard let tz = TimeZone(identifier: zone) else { return nil }
            var c = Calendar(identifier: .gregorian); c.timeZone = tz; return day(text, calendar: c)
        case .unknown: return nil
        }
    }
    static func localDay(_ time: MacFXQuoteTime, calendar: Calendar) -> String? {
        switch time {
        case .instant(let date, let zone): return TimeZone(identifier: zone) != nil ? tag(date, calendar: calendar) : nil
        case .day(let text, let zone):
            guard let tz = TimeZone(identifier: zone) else { return nil }
            var sourceCalendar = Calendar(identifier: .gregorian); sourceCalendar.timeZone = tz
            guard let date = day(text, calendar: sourceCalendar), let interval = sourceCalendar.dateInterval(of: .day, for: date),
                  let local = calendar.dateInterval(of: .day, for: date), interval == local else { return nil }
            return tag(date, calendar: calendar)
        case .unknown: return nil
        }
    }
    static func label(_ time: MacFXQuoteTime) -> String {
        switch time {
        case .instant(let date, let zone):
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f.string(from: date) + " · " + TimeZone.current.identifier + "（源 " + zone + "）"
        case .day(let day, let zone): return day + " · 日级参考 · " + (TimeZone(identifier: zone) == nil ? "时区未知" : zone)
        case .unknown: return "报价时间未知 · 参考值"
        }
    }
}

nonisolated struct MacFXComparison {
    struct Change { let difference: Double; let percent: Double; let baseline: MacFXEvidenceQuote; let caption: String }
    var change: Change?
    var reason: String
    static func sameDefinition(_ a: MacFXEvidenceQuote, _ b: MacFXEvidenceQuote) -> Bool {
        guard a.identity.pair == b.identity.pair, a.identity.sourceID == b.identity.sourceID,
              a.identity.sourceRevision == b.identity.sourceRevision else { return false }
        func path(_ q: MacFXEvidenceQuote) -> [String] { q.legs.map { $0.pair.key + ":" + $0.sourceID + ":" + $0.sourceRevision } }
        return path(a) == path(b)
    }
    static func usable(_ q: MacFXEvidenceQuote) -> Bool {
        guard [.monitorCurrent, .monitorPreviousDay].contains(q.identity.purpose), q.comparisonEligible, MacFXMath.validRate(q.unitRate), MacFXDates.instant(q.quoteTime) != nil else { return false }
        if let first = q.legs.first {
            guard first.sourceID == q.identity.sourceID, first.sourceRevision == q.identity.sourceRevision, first.quoteTime == q.quoteTime else { return false }
            return q.legs.allSatisfy { $0.sourceID == first.sourceID && $0.sourceRevision == first.sourceRevision && $0.quoteTime == first.quoteTime && MacFXDates.instant($0.quoteTime) != nil }
        }
        return true
    }
    static func newer(_ next: MacFXEvidenceQuote, than old: MacFXEvidenceQuote) -> Bool {
        guard sameDefinition(next, old), let a = MacFXDates.instant(next.quoteTime), let b = MacFXDates.instant(old.quoteTime) else { return false }
        return a > b
    }
    static func evaluate(current: MacFXEvidenceQuote?, previous: MacFXEvidenceQuote?, history: [MacFXEvidenceQuote],
                         automatic: Bool, now: Date = Date(), calendar: Calendar = .current) -> Self {
        guard let current else { return Self(reason: "暂无报价") }
        guard usable(current) else { return Self(reason: "无可比数据：报价时间、路径或修订证据不足") }
        let baseline: MacFXEvidenceQuote?, caption: String
        if automatic {
            baseline = previous; caption = "较前次有效报价"
        } else {
            guard let day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return Self(reason: "无可比数据：日期无效") }
            let today = MacFXDates.tag(now, calendar: calendar), yesterday = MacFXDates.tag(day, calendar: calendar)
            guard MacFXDates.localDay(current.quoteTime, calendar: calendar) == today else {
                return Self(reason: "无可比数据：当前报价不属于本地今日，或日级时区无法对应")
            }
            baseline = history.filter { sameDefinition(current, $0) && usable($0) && MacFXDates.localDay($0.quoteTime, calendar: calendar) == yesterday }
                .max { (MacFXDates.instant($0.quoteTime) ?? .distantPast) < (MacFXDates.instant($1.quoteTime) ?? .distantPast) }
            caption = "较前一自然日（\(yesterday) · \(calendar.timeZone.identifier)）"
        }
        guard let baseline, usable(baseline), newer(current, than: baseline) else {
            return Self(reason: automatic ? "等待可比的前次有效报价" : "无可比数据：缺少同源前一自然日报价")
        }
        let difference = current.unitRate - baseline.unitRate, percent = (current.unitRate / baseline.unitRate - 1) * 100
        guard difference.isFinite, percent.isFinite else { return Self(reason: "变化超出可表示范围") }
        return Self(change: Change(difference: difference, percent: percent, baseline: baseline, caption: caption), reason: "")
    }
}
