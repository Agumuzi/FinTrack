import Foundation

/// Selectively adapted from the reference graph's unit normalization, reciprocal
/// edges and breadth-first traversal. FinTrack keeps each leg's evidence.
nonisolated enum MacFXMath {
    struct Conversion {
        let unitRate: Double
        let legs: [MacFXQuoteLeg]
        var isEstimate: Bool {
            guard let first = legs.first else { return false }
            return MacFXDates.instant(first.quoteTime) == nil || legs.contains {
                $0.sourceID != first.sourceID || $0.sourceRevision != first.sourceRevision || $0.quoteTime != first.quoteTime
            }
        }
        func amount(_ value: Double) throws -> Double {
            let result = value * unitRate
            guard value.isFinite, value >= 0, result.isFinite, result >= 0 else { throw MacFXContractFailure.invalidEvidence }
            return result
        }
    }
    static func validRate(_ value: Double) -> Bool { value.isFinite && value > 0 }
    static func amount(_ text: String, emptyDefault: Double) throws -> Double {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        if raw.isEmpty { return emptyDefault }
        guard raw.allSatisfy({ "0123456789.".contains($0) }), raw.filter({ $0 == "." }).count <= 1,
              let value = Double(raw), value.isFinite, value >= 0 else { throw MacFXContractFailure.invalidEvidence }
        return value
    }
    static func formatted(_ value: Double, digits: Int = 4, compact: Bool = false, grouping: Bool = false, groupingSeparator: String = ",") -> String {
        guard value.isFinite else { return "超出范围" }
        let digits = (0...12).contains(digits) ? digits : 4
        if compact && abs(value) >= 1e9 { return String(format: "%.4g", value) }
        var places = digits
        if value != 0 {
            while places < 12 && abs(value) < 0.5 * pow(10, -Double(places)) { places += 1 }
            if abs(value) < 0.5e-12 { return String(format: "%.6g", value) }
        }
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal; formatter.usesGroupingSeparator = grouping
        formatter.groupingSeparator = groupingSeparator
        formatter.minimumFractionDigits = places; formatter.maximumFractionDigits = places
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
    static func resolve(from: String, to: String, quotes: [MacFXEvidenceQuote], allowEstimates: Bool = true) -> Conversion? {
        if from == to { return Conversion(unitRate: 1, legs: []) }
        var edges: [String: [(String, Conversion)]] = [:]
        for quote in quotes where validRate(quote.unitRate) && [.monitorCurrent, .monitorPreviousDay].contains(quote.identity.purpose) {
            let pair = quote.identity.pair
            let legs = quote.legs.isEmpty ? [MacFXQuoteLeg(pair: pair, sourceID: quote.identity.sourceID,
                sourceRevision: quote.identity.sourceRevision, quoteTime: quote.quoteTime, batchID: nil, unitRate: quote.unitRate)] : quote.legs
            edges[pair.base, default: []].append((pair.quote, Conversion(unitRate: quote.unitRate, legs: legs)))
            let inverse = 1 / quote.unitRate
            if validRate(inverse) {
                let reversed = legs.reversed().compactMap { leg -> MacFXQuoteLeg? in
                    guard let pair = try? MacFXPair(base: leg.pair.quote, quote: leg.pair.base) else { return nil }
                    return MacFXQuoteLeg(pair: pair, sourceID: leg.sourceID, sourceRevision: leg.sourceRevision,
                        quoteTime: leg.quoteTime, batchID: leg.batchID, unitRate: leg.unitRate.map { 1 / $0 })
                }
                edges[pair.quote, default: []].append((pair.base, Conversion(unitRate: inverse, legs: reversed)))
            }
        }
        var queue: [(String, Conversion)] = [(from, Conversion(unitRate: 1, legs: []))]
        var seen: Set<String> = [from], index = 0
        while index < queue.count {
            let (code, route) = queue[index]; index += 1
            for (next, edge) in (edges[code] ?? []).sorted(by: { $0.0 < $1.0 }) where !seen.contains(next) {
                let rate = route.unitRate * edge.unitRate
                guard validRate(rate) else { continue }
                let joined = Conversion(unitRate: rate, legs: route.legs + edge.legs)
                guard allowEstimates || !joined.isEstimate else { continue }
                if next == to { return joined }
                seen.insert(next); queue.append((next, joined))
            }
        }
        return nil
    }
}
