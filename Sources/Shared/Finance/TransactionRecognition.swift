import Foundation

/// Read-only compatibility adapter. User text alone is never an accounting state.
/// Keep receipt bytes intact for CSV, backups and occurrence idempotency.
enum TransactionRecognition {
    enum Status { case ordinary, posted, estimated, needsReview }
    static func depositIdentity(_ note: String?) -> (depositID: UUID, marker: String)? {
        let parts = (note ?? "").components(separatedBy: "[FTDep:")
        guard parts.count == 2, let end = parts[1].firstIndex(of: "]") else { return nil }
        let body = String(parts[1][..<end]), fields = body.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 3, let id = UUID(uuidString: String(fields[0])), Int64(fields[1]) != nil,
              fields[2] == "MP" || fields[2] == "MAT" else { return nil }
        return (id, "[FTDep:" + body + "]")
    }
    static func status(_ row: Transaction) -> Status {
        let note = row.note ?? ""
        guard note.contains("[FTDep:") else { return .ordinary }
        guard let identity = depositIdentity(note), row.typedType == .income,
              row.originalAmount.isFinite, row.originalAmount >= 0,
              row.baseAmount.isFinite, row.baseAmount >= 0,
              row.exchangeRateToBase.isFinite, row.exchangeRateToBase > 0,
              row.originalCurrency.count == 3, row.baseCurrencyCode.count == 3,
              row.originalCurrency != row.baseCurrencyCode || row.exchangeRateToBase == 1 else { return .needsReview }
        let suffix = note.range(of: identity.marker).map { String(note[$0.upperBound...]) } ?? ""
        return suffix.contains("[FTEstimated]") ? .estimated : .posted
    }
    static func depositStateContains(_ marker: String, in note: String?) -> Bool {
        guard let note, let identity = depositIdentity(note), let range = note.range(of: identity.marker) else { return false }
        return note[range.upperBound...].contains(marker)
    }
    static func replacingPendingState(_ note: String?) -> String {
        let text = note ?? ""
        guard let identity = depositIdentity(text), let range = text.range(of: identity.marker) else { return text }
        let suffix = String(text[range.upperBound...])
            .replacingOccurrences(of: " [FTEstimated]", with: "")
            .replacingOccurrences(of: "（待核对）", with: "")
            .replacingOccurrences(of: " [FTPartial]", with: "")
        return String(text[..<range.upperBound]) + suffix
    }
    static func isRealized(_ row: Transaction) -> Bool {
        switch status(row) { case .ordinary, .posted: true; case .estimated, .needsReview: false }
    }
}
