import Foundation

/// The comparison always uses stored book amounts and half-open calendar ranges.
enum MacPeriodComparison {
    struct Totals {
        var income: Double
        var expense: Double
        var net: Double { income - expense }
    }
    struct CategoryRow: Identifiable {
        var id: String
        var current: Double
        var previous: Double
        var delta: Double { current - previous }
    }
    struct Point: Identifiable {
        var index: Int
        var label: String
        var current: Double?
        var previous: Double?
        var id: Int { index }
    }
    struct Snapshot {
        var currentRows: [Transaction]
        var previousRows: [Transaction]
        var current: Totals
        var previous: Totals
        var categories: [CategoryRow]
        var points: [Point]
    }
    static func snapshot(rows: [Transaction], currency: String, current: DateInterval, previous: DateInterval,
                         flow: TransactionType, monthly: Bool, calendar: Calendar = .current) -> Snapshot {
        let eligible = rows.filter { $0.deletedAt == nil && $0.baseCurrencyCode == currency }
        func scoped(_ interval: DateInterval) -> [Transaction] { eligible.filter { $0.date >= interval.start && $0.date < interval.end } }
        func totals(_ rows: [Transaction]) -> Totals {
            Totals(income: ComparisonAnalyticsCore.totalAmount(of: .income, in: rows), expense: ComparisonAnalyticsCore.totalAmount(of: .expense, in: rows))
        }
        let a = scoped(current), b = scoped(previous)
        func categories(_ rows: [Transaction]) -> [String: Double] {
            Dictionary(grouping: rows.filter { $0.typedType == flow }, by: \.category).mapValues { $0.reduce(0) { $0 + $1.baseAmount } }
        }
        let ca = categories(a), cb = categories(b)
        let names = Set(ca.keys).union(cb.keys)
        let categoryRows: [CategoryRow] = names.map { name in
            CategoryRow(id: name, current: ca[name] ?? 0, previous: cb[name] ?? 0)
        }
        let categories = categoryRows.sorted { left, right in
            let la = abs(left.delta), ra = abs(right.delta)
            if la == ra { return left.id < right.id }
            return la > ra
        }
        let component: Calendar.Component = monthly ? .month : .day
        func bucketStart(_ date: Date) -> Date { calendar.dateInterval(of: component, for: date)!.start }
        func count(_ interval: DateInterval) -> Int {
            let end = interval.end.addingTimeInterval(-0.001)
            return (calendar.dateComponents([component], from: bucketStart(interval.start), to: bucketStart(end)).value(for: component) ?? 0) + 1
        }
        func amounts(_ rows: [Transaction], _ interval: DateInterval) -> [Int: Double] {
            Dictionary(grouping: rows.filter { $0.typedType == flow }) {
                calendar.dateComponents([component], from: bucketStart(interval.start), to: bucketStart($0.date)).value(for: component) ?? 0
            }.mapValues { $0.reduce(0) { $0 + $1.baseAmount } }
        }
        let na = count(current), nb = count(previous), aa = amounts(a, current), ab = amounts(b, previous)
        let points = (0..<max(na, nb)).map { i in
            Point(index: i + 1, label: "\(i + 1)" + (monthly ? "月" : "日"), current: i < na ? aa[i] ?? 0 : nil, previous: i < nb ? ab[i] ?? 0 : nil)
        }
        return Snapshot(currentRows: a, previousRows: b, current: totals(a), previous: totals(b), categories: categories, points: points)
    }
}
