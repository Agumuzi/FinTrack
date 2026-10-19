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
        for prefix in prefixes where note.hasPrefix(prefix) { return String(note.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
        return note
    }
    static func replacing(_ old: String?, with userNote: String) -> String? {
        let clean = userNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if let old, let prefix = prefixes.first(where: { old.hasPrefix($0) }) {
            return prefix + (clean.isEmpty ? "" : " " + clean)
        }
        return clean.isEmpty ? nil : clean
    }
}
