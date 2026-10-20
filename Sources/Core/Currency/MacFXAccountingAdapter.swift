import Foundation

/// Uses the accounting policy and dated financial cache, never monitor snapshots.
struct MacFXAccountingAdapter: MacFXAccountingQuotes {
    func accountingQuote(pair:MacFXPair,day:String) async throws -> MacFXEvidenceQuote {
        try await MacExchangeRates.shared.evidence(pair:pair,day:day)
    }
}
