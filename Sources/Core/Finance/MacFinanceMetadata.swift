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
        value = value.replacingOccurrences(of: #"\[FTLoanSchedule:[^\]]*\]"#, with: "", options: .regularExpression)
        for prefix in prefixes where value.hasPrefix(prefix) { value = String(value.dropFirst(prefix.count)); break }
        if value.hasPrefix("[Auto] ") { value = "周期：" + value.dropFirst(7) }
        if value.hasPrefix("Loan installment ") {
            value = value.replacingOccurrences(of: "Loan installment ", with: "还款期次 ").replacingOccurrences(of: "Principal:", with: "本金：").replacingOccurrences(of: "Interest:", with: "利息：")
        }
        return value.replacingOccurrences(of: #"\[FT(?:Dep|Rec|Loan):[^\]]+\]|\[FT(?:Estimated|Verified)\]"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
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
