import Foundation

// FinTrack-owned contracts. No SwiftData, transactions, preferences or credentials.
// A request identity is independent of presentation units and decimal places.
nonisolated struct MacFXPair: Codable, Hashable, Sendable {
    let base: String
    let quote: String
    init(base: String, quote: String) throws {
        func code(_ input: String) throws -> String {
            let value = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard value.count == 3, value.utf8.allSatisfy({ (65...90).contains($0) }) else { throw MacFXContractFailure.invalidPair }
            return value
        }
        self.base = try code(base); self.quote = try code(quote)
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(base: c.decode(String.self, forKey: .base), quote: c.decode(String.self, forKey: .quote))
    }
    var key: String { base + "/" + quote }
}

nonisolated enum MacFXPurpose: String, Codable, Sendable { case accountingDay, monitorCurrent, monitorPreviousDay, monitorHistory }
nonisolated enum MacFXSourceScope {
    static func isSystem(_ id:String) -> Bool { id == "free" || id.hasPrefix("system.") }
}
nonisolated enum MacFXRequestDate: Hashable, Codable, Sendable { case latest; case day(String) }
nonisolated struct MacFXRequestIdentity: Hashable, Codable, Sendable {
    let purpose: MacFXPurpose
    let pair: MacFXPair
    let sourceID: String
    let sourceRevision: String
    let requested: MacFXRequestDate
}

nonisolated enum MacFXQuoteTime: Codable, Equatable, Sendable {
    case instant(Date, timeZoneID: String)
    case day(String, timeZoneID: String)
    case unknown
}
nonisolated struct MacFXQuoteLeg: Codable, Equatable, Sendable {
    let pair: MacFXPair
    let sourceID: String
    let sourceRevision: String
    let quoteTime: MacFXQuoteTime
    let batchID: String?
    var unitRate: Double? = nil
}
nonisolated struct MacFXEvidenceQuote: Codable, Sendable {
    let identity: MacFXRequestIdentity
    let unitRate: Double
    let quoteTime: MacFXQuoteTime
    let retrievedAt: Date
    let legs: [MacFXQuoteLeg]
    var comparisonEligible = true
}

nonisolated enum MacFXRefreshReason: Sendable { case manual, scheduled, pageOpen }
protocol MacFXAccountingQuotes {
    /// Exact calendar day and its own source policy. No monitor cache access.
    func accountingQuote(pair: MacFXPair, day: String) async throws -> MacFXEvidenceQuote
}
protocol MacFXMonitorQuotes {
    /// Monitoring only. Never writes a financial object or confirms a draft.
    func monitorQuote(pair: MacFXPair, reason: MacFXRefreshReason) async throws -> MacFXEvidenceQuote
}
nonisolated enum MacFXContractFailure: Error { case invalidPair, unavailable, invalidEvidence }
