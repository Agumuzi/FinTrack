import Foundation

nonisolated struct MacFXQuoteCache: Codable {
    struct Snapshot: Codable { var pair: MacFXPair; var current: MacFXEvidenceQuote; var previous: MacFXEvidenceQuote? }
    var version = 1
    var snapshots: [Snapshot] = []
    var observations: [MacFXEvidenceQuote] = []
    static let maximumObservations = 2000

    static func valid(_ quote: MacFXEvidenceQuote, now: Date = Date()) -> Bool {
        guard [.monitorCurrent, .monitorPreviousDay].contains(quote.identity.purpose), MacFXMath.validRate(quote.unitRate), !quote.identity.sourceID.isEmpty,
              !quote.identity.sourceRevision.isEmpty, quote.legs.count <= 16,
              quote.retrievedAt.timeIntervalSince1970.isFinite, quote.retrievedAt <= now.addingTimeInterval(300) else { return false }
        if case .day(let tag) = quote.identity.requested { guard MacFXDates.day(tag) != nil else { return false } }
        if quote.identity.purpose == .monitorPreviousDay { guard case .day = quote.identity.requested else { return false } }
        if case .instant(let date, let zone) = quote.quoteTime {
            guard TimeZone(identifier: zone) != nil, date.timeIntervalSince1970.isFinite, date <= now.addingTimeInterval(300) else { return false }
        }
        if case .day(let text, _) = quote.quoteTime { guard MacFXDates.day(text) != nil else { return false } }
        var end = quote.identity.pair.base
        for leg in quote.legs {
            guard leg.pair.base == end, !leg.sourceID.isEmpty, !leg.sourceRevision.isEmpty,
                  leg.unitRate == nil || MacFXMath.validRate(leg.unitRate!) else { return false }
            end = leg.pair.quote
        }
        return quote.legs.isEmpty || end == quote.identity.pair.quote
    }
    func validated(now: Date = Date()) throws -> Self {
        guard version == 1, snapshots.count <= 1000, observations.count <= Self.maximumObservations,
              Set(snapshots.map(\.pair)).count == snapshots.count,
              snapshots.allSatisfy({ $0.pair == $0.current.identity.pair && $0.current.identity.purpose == .monitorCurrent && Self.valid($0.current, now: now) && ($0.previous == nil || Self.valid($0.previous!, now: now)) }),
              observations.allSatisfy({ $0.identity.purpose != .accountingDay && Self.valid($0, now: now) }) else { throw MacFXContractFailure.invalidEvidence }
        return self
    }
    func snapshot(_ pair: MacFXPair) -> Snapshot? { snapshots.first { $0.pair == pair } }

    @discardableResult mutating func accept(_ input: MacFXEvidenceQuote, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard input.identity.purpose != .accountingDay, Self.valid(input, now: now) else { return false }
        var quote = input
        if quote.identity.purpose == .monitorCurrent {
            let index = snapshots.firstIndex { $0.pair == quote.identity.pair }
            var previous: MacFXEvidenceQuote?
            if let index {
                let old = snapshots[index]
                if MacFXComparison.sameDefinition(quote, old.current) {
                    let nextTime = MacFXDates.instant(quote.quoteTime), oldTime = MacFXDates.instant(old.current.quoteTime)
                    if let nextTime, let oldTime {
                        guard nextTime >= oldTime else { return false }
                        if nextTime == oldTime {
                            quote.comparisonEligible = old.current.comparisonEligible && quote.unitRate == old.current.unitRate
                            previous = old.previous
                        } else { previous = old.current }
                    } else { quote.comparisonEligible = false }
                }
                snapshots[index] = Snapshot(pair: quote.identity.pair, current: quote, previous: previous)
            } else { snapshots.append(Snapshot(pair: quote.identity.pair, current: quote, previous: nil)) }
            if snapshots.count > 1000 { snapshots.removeFirst(snapshots.count - 1000) }
        }
        observations.removeAll { $0.identity == quote.identity && $0.quoteTime == quote.quoteTime }
        observations.append(quote)
        if observations.count > Self.maximumObservations {
            // Retain current/previous plus the necessary local D-1 reference;
            // eviction never manufactures a replacement comparison point.
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now).map { MacFXDates.tag($0, calendar: calendar) }
            var protected = snapshots.flatMap { [$0.current] + ($0.previous.map { [$0] } ?? []) }
            for snapshot in snapshots {
                if let latest = observations.filter({ MacFXComparison.sameDefinition($0, snapshot.current) && MacFXDates.localDay($0.quoteTime, calendar: calendar) == yesterday })
                    .max(by: { (MacFXDates.instant($0.quoteTime) ?? .distantPast) < (MacFXDates.instant($1.quoteTime) ?? .distantPast) }) { protected.append(latest) }
            }
            func same(_ a: MacFXEvidenceQuote, _ b: MacFXEvidenceQuote) -> Bool { a.identity == b.identity && a.quoteTime == b.quoteTime }
            var retained: [MacFXEvidenceQuote] = []
            for row in protected + observations.reversed() where !retained.contains(where: { same($0, row) }) {
                if retained.count == Self.maximumObservations { break }; retained.append(row)
            }
            observations = retained.sorted { $0.retrievedAt < $1.retrievedAt }
        }
        return true
    }
}
