import Foundation

/// Read-only report scope. Money always uses saved base-currency snapshots.
struct MacOverviewScope: Equatable {
    enum Period: String, CaseIterable, Identifiable {
        case month = "本月", year = "本年", all = "全部", custom = "自定义"
        var id: String { rawValue }
    }
    var period: Period = .month
    var reference = Date()
    var from = Calendar.current.dateInterval(of: .month, for: Date())!.start
    var through = Date()
    var category: String?
    var type: TransactionType?

    func interval(calendar: Calendar = .current) -> DateInterval? {
        switch period {
        case .month: return calendar.dateInterval(of: .month, for: reference)
        case .year: return calendar.dateInterval(of: .year, for: reference)
        case .all: return nil
        case .custom:
            let start = calendar.startOfDay(for: from)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: through))!
            return DateInterval(start: start, end: max(start, end))
        }
    }
    var isValid: Bool { period != .custom || from <= through }
    func previousInterval(calendar: Calendar = .current) -> DateInterval? {
        guard isValid, let current = interval(calendar: calendar) else { return nil }
        switch period {
        case .month: return calendar.dateInterval(of: .month, for: calendar.date(byAdding: .month, value: -1, to: current.start)!)
        case .year: return calendar.dateInterval(of: .year, for: calendar.date(byAdding: .year, value: -1, to: current.start)!)
        case .custom:
            let days = calendar.dateComponents([.day], from: current.start, to: current.end).day!
            return DateInterval(start: calendar.date(byAdding: .day, value: -days, to: current.start)!, end: current.start)
        case .all: return nil
        }
    }
    func matches(_ row: Transaction, currency: String, interval override: DateInterval? = nil) -> Bool {
        guard isValid, row.deletedAt == nil, row.baseCurrencyCode == currency,
              category == nil || row.category == category, type == nil || row.typedType == type else { return false }
        guard let range = override ?? interval() else { return true }
        // DateInterval.contains includes its end, whereas ledger periods do not.
        return row.date >= range.start && row.date < range.end
    }
    var title: String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_Hans_CN")
        switch period {
        case .month: return MacDisplayPreferences.month(reference)
        case .year: formatter.dateFormat = "yyyy年"; return formatter.string(from: reference)
        case .all: return "全部记录"
        case .custom:
            formatter.dateFormat = "yyyy.MM.dd"
            return "\(formatter.string(from: from)) – \(formatter.string(from: through))"
        }
    }
}

enum MacOverviewData {
    struct Bucket: Identifiable {
        let id: String
        let amount: Double
        let count: Int
    }
    struct Month: Identifiable {
        let id: Date
        let income: Double
        let expense: Double
    }
    static func categories(_ rows: [Transaction], type: TransactionType) -> [Bucket] {
        Dictionary(grouping: rows.filter { $0.deletedAt == nil && $0.typedType == type }, by: \.category)
            .map { Bucket(id: $0.key, amount: ComparisonAnalyticsCore.totalAmount(of: type, in: $0.value), count: $0.value.count) }
            .sorted { $0.amount == $1.amount ? $0.id < $1.id : $0.amount > $1.amount }
    }
    static func change(current: Double, previous: Double) -> Double? {
        guard previous != 0, current.isFinite, previous.isFinite else { return nil }
        return (current - previous) / abs(previous)
    }
    static func months(_ rows: [Transaction], scope: MacOverviewScope, currency: String,
                       count: Int, calendar: Calendar = .current) -> [Month] {
        let endMonth = calendar.dateInterval(of: .month, for: scope.reference)!.start
        return (0..<count).reversed().map { offset in
            let start = calendar.date(byAdding: .month, value: -offset, to: endMonth)!
            let range = calendar.dateInterval(of: .month, for: start)!
            let selected = rows.filter { scope.matches($0, currency: currency, interval: range) }
            let totals = MacTransactionCRUD.totals(transactions: selected, currency: currency)
            return Month(id: start, income: totals.income, expense: totals.expense)
        }
    }
}
