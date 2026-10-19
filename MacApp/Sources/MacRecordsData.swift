import Foundation

/// In-memory state for returning directly to the Records sidebar page.
/// Overview drill-down routes keep their explicit scope separate.
struct MacRecordsNavigationState {
    var searchText: String
    var typeFilter: String
    var dateFilterEnabled: Bool
    var dateFrom: Date
    var dateThrough: Date
    var currencyFilter: String
    var categoryFilter: String
    var recordSort: String
    var displayLimit: Int
    var rangeTitle: String
    var expandedYears: Set<Int>
    var expandedMonths: Set<String>

    init(searchText: String = "", typeFilter: String = "All", dateFilterEnabled: Bool = false,
         dateFrom: Date = DateFilterRangeState.currentMonth().startDate, dateThrough: Date = Date(),
         currencyFilter: String = "All", categoryFilter: String = "All",
         recordSort: String = MacPreferences.defaults.string(forKey: "v2_sort") ?? "最新优先",
         displayLimit: Int = MacPreferences.defaults.object(forKey: "v2_page_size") as? Int ?? 50,
         rangeTitle: String = "全部记录", expandedYears: Set<Int>? = nil, expandedMonths: Set<String>? = nil) {
        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        let month = Calendar.current.component(.month, from: now)
        self.searchText = searchText
        self.typeFilter = typeFilter
        self.dateFilterEnabled = dateFilterEnabled
        self.dateFrom = dateFrom
        self.dateThrough = dateThrough
        self.currencyFilter = currencyFilter
        self.categoryFilter = categoryFilter
        self.recordSort = recordSort
        self.displayLimit = displayLimit
        self.rangeTitle = rangeTitle
        self.expandedYears = expandedYears ?? [year]
        self.expandedMonths = expandedMonths ?? ["\(year)-\(month)"]
    }
}

/// Calendar boundaries and filters only; all amounts retain their stored snapshots.
struct MacRecordsFilter {
    var search = ""
    var type = "All"
    var currency = "All"
    var category = "All"
    var interval: DateInterval?

    func matches(_ row: Transaction) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return row.deletedAt == nil
            && (type == "All" || row.type == type)
            && (currency == "All" || row.originalCurrency == currency)
            && (category == "All" || row.category == category)
            && (interval == nil || (row.date >= interval!.start && row.date < interval!.end))
            && (query.isEmpty || [row.category, MacOverviewStyle.category(row.category), row.note ?? "", row.originalCurrency, row.baseCurrencyCode]
                .contains { $0.localizedStandardContains(query) })
    }

    static func inclusiveDays(from: Date, through: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: min(from, through))
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(from, through)))!
        return DateInterval(start: start, end: end)
    }
}

/// Pre-groups the date browser once per ledger refresh so expanding a year/month
/// does not rescan every SwiftData row for each calendar cell.
struct MacRecordsTimelineIndex {
    private struct MonthKey: Hashable { var year: Int; var month: Int }
    private struct DayKey: Hashable { var year: Int; var month: Int; var day: Int }

    private var rowsByYear: [Int: [Transaction]] = [:]
    private var rowsByMonth: [MonthKey: [Transaction]] = [:]
    private var monthsByYear: [Int: [Int]] = [:]
    private var daysByMonth: [MonthKey: [Date]] = [:]
    private var countsByDay: [DayKey: Int] = [:]

    init(rows: [Transaction], calendar: Calendar = .current) {
        var monthSets: [Int: Set<Int>] = [:]
        var daySets: [MonthKey: Set<Date>] = [:]
        for row in rows where row.deletedAt == nil {
            let components = calendar.dateComponents([.year, .month, .day], from: row.date)
            guard let year = components.year, let month = components.month, let day = components.day else { continue }
            let monthKey = MonthKey(year: year, month: month)
            let dayKey = DayKey(year: year, month: month, day: day)
            rowsByYear[year, default: []].append(row)
            rowsByMonth[monthKey, default: []].append(row)
            monthSets[year, default: []].insert(month)
            daySets[monthKey, default: []].insert(calendar.startOfDay(for: row.date))
            countsByDay[dayKey, default: 0] += 1
        }
        monthsByYear = monthSets.mapValues { $0.sorted(by: >) }
        daysByMonth = daySets.mapValues { $0.sorted(by: >) }
    }

    var years: [Int] { rowsByYear.keys.sorted(by: >) }
    func months(in year: Int) -> [Int] { monthsByYear[year] ?? [] }
    func days(in year: Int, month: Int) -> [Date] { daysByMonth[MonthKey(year: year, month: month)] ?? [] }
    func count(year: Int, month: Int? = nil) -> Int { rows(in: year, month: month).count }
    func rows(in year: Int, month: Int? = nil) -> [Transaction] {
        if let month { return rowsByMonth[MonthKey(year: year, month: month)] ?? [] }
        return rowsByYear[year] ?? []
    }
    func count(on date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return 0 }
        return countsByDay[DayKey(year: year, month: month, day: day)] ?? 0
    }
}
