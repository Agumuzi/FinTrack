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
    /// Day-granularity quotes retain their source publication label. They do
    /// not become an artificial local-midnight market timestamp.
    static func publicationDay(_ time: MacFXQuoteTime, calendar: Calendar) -> String? {
        if case .day(let text, let zone) = time {
            guard TimeZone(identifier: zone) != nil, day(text) != nil else { return nil }
            return text
        }
        return localDay(time, calendar: calendar)
    }
    static func label(_ time: MacFXQuoteTime) -> String {
        switch time {
        case .instant(let date, let zone):
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f.string(from: date) + " · " + TimeZone.current.identifier + L10n.text("mac.fXComparison.label.11c77c4f9b") + zone + "）"
        case .day(let day, let zone): return day + L10n.text("mac.fXComparison.label.f8180d426d") + (TimeZone(identifier: zone) == nil ? L10n.text("mac.fXComparison.label.e3879adac0") : zone)
        case .unknown: return L10n.text("mac.fXComparison.label.e30159f472")
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
        switch (a.quoteTime, b.quoteTime) {
        case (.day(_, let az), .day(_, let bz)): guard az == bz else { return false }
        case (.instant, .instant): break
        default: return false
        }
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
        guard let current else { return Self(reason: L10n.text("mac.fXComparison.Self.87fdce8be2")) }
        guard usable(current) else { return Self(reason: L10n.text("mac.fXComparison.Self.ebe35bb099")) }
        let baseline: MacFXEvidenceQuote?, caption: String
        if automatic {
            baseline = previous; caption = L10n.text("mac.fXComparison.evaluate.364ab51f8b")
        } else if case .day(let published, _) = current.quoteTime {
            baseline = history.filter { sameDefinition(current, $0) && usable($0) && newer(current, than: $0) }
                .max { (MacFXDates.instant($0.quoteTime) ?? .distantPast) < (MacFXDates.instant($1.quoteTime) ?? .distantPast) }
            let day = baseline.flatMap { MacFXDates.publicationDay($0.quoteTime, calendar: calendar) } ?? "—"
            caption = L10n.text("mac.fXComparison.evaluate.633e81d219") + day + " → " + published + "）"
        } else {
            guard let day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return Self(reason: L10n.text("mac.fXComparison.Self.5cea3d5bc9")) }
            let today = MacFXDates.tag(now, calendar: calendar), yesterday = MacFXDates.tag(day, calendar: calendar)
            guard MacFXDates.localDay(current.quoteTime, calendar: calendar) == today else {
                return Self(reason: L10n.text("mac.fXComparison.Self.fb82b5337c"))
            }
            baseline = history.filter { sameDefinition(current, $0) && usable($0) && MacFXDates.localDay($0.quoteTime, calendar: calendar) == yesterday }
                .max { (MacFXDates.instant($0.quoteTime) ?? .distantPast) < (MacFXDates.instant($1.quoteTime) ?? .distantPast) }
            caption = L10n.format("mac.fXComparison.evaluate.166b20d8e7", "\(yesterday)", "\(calendar.timeZone.identifier)")
        }
        guard let baseline, usable(baseline), newer(current, than: baseline) else {
            return Self(reason: automatic ? L10n.text("mac.fXComparison.Self.7f98bce6cd") : L10n.text("mac.fXComparison.Self.dff626e4f4"))
        }
        let difference = current.unitRate - baseline.unitRate, percent = (current.unitRate / baseline.unitRate - 1) * 100
        guard difference.isFinite, percent.isFinite else { return Self(reason: L10n.text("mac.fXComparison.Self.9a19716167")) }
        return Self(change: Change(difference: difference, percent: percent, baseline: baseline, caption: caption), reason: "")
    }
}
