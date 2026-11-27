import Foundation

struct MacReminderSettings {
    let daysBefore: Int
    let hour: Int
    let minute: Int
    func validate() throws {
        guard (0...365).contains(daysBefore), (0...23).contains(hour), (0...59).contains(minute) else {
            throw MacFinanceRecords.Failure.invalidDateRange
        }
    }
}

struct MacRecurringSettings {
    let endDate: Date?
    let isActive: Bool
}

enum MacFinanceNotes {
    private static var prefixes: [String] { [MacFinanceRecords.managedDepositTag, MacFinanceRecords.managedLoanTag, MacFinanceRecords.reviewedRecurringTag] }
    static func visible(_ note: String?) -> String {
        guard let note else { return "" }
        var value = note
        if value.hasPrefix(MacFinanceRecords.managedLoanTag) {
            value = value.replacingOccurrences(of: #"\[(?:FTLoanSchedule:|FTLoan:Schedule:)[^\]]*\]"#, with: "", options: .regularExpression)
        }
        for prefix in prefixes where value.hasPrefix(prefix) { value = String(value.dropFirst(prefix.count)); break }
        if let identity = TransactionRecognition.depositIdentity(note), let marker = value.range(of: identity.marker) {
            var description = String(value[..<marker.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if description.hasPrefix("银行利息：") {
                description = L10n.format("receipt.description.deposit", String(description.dropFirst("银行利息：".count)))
            }
            let state = value[marker.upperBound...]
            if state.contains("[FTEstimated]") { description += " · " + L10n.text("receipt.pendingReview") }
            if let regex = try? NSRegularExpression(pattern: #"核对前金额:([-+]?[0-9]+(?:\.[0-9]+)?)"#) {
                let suffix = String(state)
                if let match = regex.matches(in: suffix, range: NSRange(suffix.startIndex..., in: suffix)).last,
                   let amount = Range(match.range(at: 1), in: suffix) {
                    description += " · " + L10n.format("receipt.description.prior", MacNumberInput.presentation(String(suffix[amount])))
                }
            }
            return description
        }
        if value.hasPrefix("[Auto] "), let marker = value.range(of: #"\[FTRec:[A-Fa-f0-9-]{36}:-?[0-9]+\]$"#, options: .regularExpression) {
            return L10n.format("receipt.description.recurring", String(value[value.index(value.startIndex, offsetBy: 7)..<marker.lowerBound]).trimmingCharacters(in: .whitespaces))
        }
        if let marker = value.range(of: " [FTLoan:"), value.hasPrefix("Loan installment ") {
            let line = String(value[..<marker.lowerBound])
            let fields = line.dropFirst("Loan installment ".count).components(separatedBy: " — Principal: ")
            if fields.count == 2 {
                let amounts = fields[1].components(separatedBy: "; Interest: ")
                if amounts.count == 2 { return L10n.format("receipt.description.loan", fields[0], amounts[0], amounts[1]) }
            }
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func replacing(_ old: String?, with userNote: String) -> String? {
        let clean = userNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if let old, let prefix = prefixes.first(where: { old.hasPrefix($0) }) {
            let schedule = prefix == MacFinanceRecords.managedLoanTag ? MacLoanSchedule.metadata(old) : nil
            return prefix + (clean.isEmpty ? "" : " " + clean) + (schedule.map { "\n" + $0 } ?? "")
        }
        return clean.isEmpty ? nil : clean
    }
}
