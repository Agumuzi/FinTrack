import Foundation

enum ComparisonPeriod: CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: Self { self }

    func localizedTitle(using languageManager: LanguageManager) -> String {
        switch self {
        case .day:
            return languageManager.ui(UIStringKey.Common.day)
        case .week:
            return languageManager.ui(UIStringKey.Common.week)
        case .month:
            return languageManager.ui(UIStringKey.Common.month)
        case .year:
            return languageManager.ui(UIStringKey.Common.year)
        }
    }
}

enum ComparisonAnalyticsCore {
    static func totalAmount(of type: TransactionType, in transactions: [Transaction]) -> Double {
        transactions
            .filter { $0.typedType == type }
            .reduce(0) { $0 + $1.baseAmount }
    }

    static func netAmount(in transactions: [Transaction]) -> Double {
        totalAmount(of: .income, in: transactions) - totalAmount(of: .expense, in: transactions)
    }

    static func comparisonSummary(current: Double, previous: Double) -> YearComparisonAnalyticsService.ComparisonSummary {
        let deltaAmount = current - previous
        let deltaPercent: Double?

        if abs(previous) >= 0.01 {
            deltaPercent = deltaAmount / previous
        } else {
            deltaPercent = nil
        }

        return YearComparisonAnalyticsService.ComparisonSummary(
            currentAmount: current,
            previousAmount: previous,
            deltaAmount: deltaAmount,
            deltaPercent: deltaPercent
        )
    }

    static func expenseCategoryDeltas(
        currentTransactions: [Transaction],
        previousTransactions: [Transaction]
    ) -> [YearComparisonAnalyticsService.CategoryDelta] {
        let currentByCategory = Dictionary(grouping: currentTransactions.filter { $0.typedType == .expense }, by: \.category)
            .mapValues { $0.reduce(0) { $0 + $1.baseAmount } }
        let previousByCategory = Dictionary(grouping: previousTransactions.filter { $0.typedType == .expense }, by: \.category)
            .mapValues { $0.reduce(0) { $0 + $1.baseAmount } }
        let allCategories = Set(currentByCategory.keys).union(previousByCategory.keys)

        return allCategories.map { category in
            let currentAmount = currentByCategory[category] ?? 0
            let previousAmount = previousByCategory[category] ?? 0
            return YearComparisonAnalyticsService.CategoryDelta(
                id: category,
                category: category,
                currentAmount: currentAmount,
                previousAmount: previousAmount,
                deltaAmount: currentAmount - previousAmount,
                deltaPercent: safeDeltaPercent(current: currentAmount, previous: previousAmount)
            )
        }
        .sorted { abs($0.deltaAmount) > abs($1.deltaAmount) }
    }

    static func trendPoints(
        of type: TransactionType,
        period: ComparisonPeriod,
        currentReferenceDate: Date,
        previousReferenceDate: Date,
        currentTransactions: [Transaction],
        previousTransactions: [Transaction],
        locale: Locale,
        calendar: Calendar
    ) -> [YearComparisonAnalyticsService.TrendPoint] {
        switch period {
        case .day:
            return [YearComparisonAnalyticsService.TrendPoint(
                index: 0,
                label: ComparePeriodFormatter.label(
                    for: currentReferenceDate,
                    period: .day,
                    locale: locale,
                    calendar: calendar
                ),
                currentAmount: totalAmount(of: type, in: currentTransactions),
                previousAmount: totalAmount(of: type, in: previousTransactions),
                isCurrentIncluded: true,
                isPreviousIncluded: true,
                isComparable: true
            )]
        case .week:
            return weekTrendPoints(
                type: type,
                currentReferenceDate: currentReferenceDate,
                previousReferenceDate: previousReferenceDate,
                currentTransactions: currentTransactions,
                previousTransactions: previousTransactions,
                calendar: calendar
            )
        case .month:
            return monthTrendPoints(
                type: type,
                currentReferenceDate: currentReferenceDate,
                previousReferenceDate: previousReferenceDate,
                currentTransactions: currentTransactions,
                previousTransactions: previousTransactions,
                locale: locale,
                calendar: calendar
            )
        case .year:
            return yearTrendPoints(
                type: type,
                currentTransactions: currentTransactions,
                previousTransactions: previousTransactions,
                locale: locale,
                calendar: calendar
            )
        }
    }

    static func selectedPeriodSnapshot(
        period: ComparisonPeriod,
        currentReferenceDate: Date,
        previousReferenceDate: Date,
        currentTransactions: [Transaction],
        previousTransactions: [Transaction]
    ) -> YearComparisonAnalyticsService.SelectedPeriodSnapshot {
        let categoryDeltas = expenseCategoryDeltas(
            currentTransactions: currentTransactions,
            previousTransactions: previousTransactions
        )

        return YearComparisonAnalyticsService.SelectedPeriodSnapshot(
            expense: comparisonSummary(
                current: totalAmount(of: .expense, in: currentTransactions),
                previous: totalAmount(of: .expense, in: previousTransactions)
            ),
            leadingCategory: categoryDeltas.first(where: { abs($0.deltaAmount) >= 0.01 }),
            period: period,
            currentReferenceDate: currentReferenceDate,
            previousReferenceDate: previousReferenceDate
        )
    }

    private static func weekTrendPoints(
        type: TransactionType,
        currentReferenceDate: Date,
        previousReferenceDate: Date,
        currentTransactions: [Transaction],
        previousTransactions: [Transaction],
        calendar: Calendar
    ) -> [YearComparisonAnalyticsService.TrendPoint] {
        let currentWeekDates = DateHelper.weekDates(containing: currentReferenceDate)
        let previousWeekDates = DateHelper.weekDates(containing: previousReferenceDate)
        let currentAmountsByDay = aggregateAmountsByDay(
            currentTransactions,
            type: type,
            calendar: calendar
        )
        let previousAmountsByDay = aggregateAmountsByDay(
            previousTransactions,
            type: type,
            calendar: calendar
        )
        let currentFormatter = DateFormatter()
        currentFormatter.locale = LanguageManager.shared.currentLocale
        currentFormatter.setLocalizedDateFormatFromTemplate("EEE")

        return (0..<7).map { index in
            let currentDate = currentWeekDates[safe: index]
            let previousDate = previousWeekDates[safe: index]
            return YearComparisonAnalyticsService.TrendPoint(
                index: index,
                label: currentDate.map { currentFormatter.string(from: $0) } ?? "\(index + 1)",
                currentAmount: currentDate.map { currentAmountsByDay[calendar.startOfDay(for: $0)] ?? 0 } ?? 0,
                previousAmount: previousDate.map { previousAmountsByDay[calendar.startOfDay(for: $0)] ?? 0 } ?? 0,
                isCurrentIncluded: currentDate != nil,
                isPreviousIncluded: previousDate != nil,
                isComparable: currentDate != nil && previousDate != nil
            )
        }
    }

    private static func monthTrendPoints(
        type: TransactionType,
        currentReferenceDate: Date,
        previousReferenceDate: Date,
        currentTransactions: [Transaction],
        previousTransactions: [Transaction],
        locale: Locale,
        calendar: Calendar
    ) -> [YearComparisonAnalyticsService.TrendPoint] {
        let currentDayCount = calendar.range(of: .day, in: .month, for: currentReferenceDate)?.count ?? 0
        let previousDayCount = calendar.range(of: .day, in: .month, for: previousReferenceDate)?.count ?? 0
        let maxDayCount = max(currentDayCount, previousDayCount)
        let currentAmountsByDay = aggregateAmountsByDayComponent(currentTransactions, type: type, calendar: calendar)
        let previousAmountsByDay = aggregateAmountsByDayComponent(previousTransactions, type: type, calendar: calendar)

        return (1...maxDayCount).map { day in
            let hasCurrentDay = day <= currentDayCount
            let hasPreviousDay = day <= previousDayCount

            return YearComparisonAnalyticsService.TrendPoint(
                index: day,
                label: dayLabel(day, locale: locale),
                currentAmount: hasCurrentDay ? (currentAmountsByDay[day] ?? 0) : 0,
                previousAmount: hasPreviousDay ? (previousAmountsByDay[day] ?? 0) : 0,
                isCurrentIncluded: hasCurrentDay,
                isPreviousIncluded: hasPreviousDay,
                isComparable: hasCurrentDay && hasPreviousDay
            )
        }
    }

    private static func yearTrendPoints(
        type: TransactionType,
        currentTransactions: [Transaction],
        previousTransactions: [Transaction],
        locale: Locale,
        calendar: Calendar
    ) -> [YearComparisonAnalyticsService.TrendPoint] {
        let monthSymbols = DateHelper.shortMonthSymbols(locale: locale)
        let currentAmountsByMonth = aggregateAmountsByMonth(currentTransactions, type: type, calendar: calendar)
        let previousAmountsByMonth = aggregateAmountsByMonth(previousTransactions, type: type, calendar: calendar)
        return (1...12).map { month in
            YearComparisonAnalyticsService.TrendPoint(
                index: month,
                label: monthSymbols[month - 1],
                currentAmount: currentAmountsByMonth[month] ?? 0,
                previousAmount: previousAmountsByMonth[month] ?? 0,
                isCurrentIncluded: true,
                isPreviousIncluded: true,
                isComparable: true
            )
        }
    }

    private static func safeDeltaPercent(current: Double, previous: Double) -> Double? {
        guard abs(previous) >= 0.01 else { return nil }
        return (current - previous) / previous
    }

    private static func dayLabel(_ day: Int, locale: Locale) -> String {
        if locale.identifier.hasPrefix("zh") {
            return "\(day)日"
        }
        return String(day)
    }

    private static func aggregateAmountsByDay(
        _ transactions: [Transaction],
        type: TransactionType,
        calendar: Calendar
    ) -> [Date: Double] {
        transactions.reduce(into: [:]) { result, transaction in
            guard transaction.typedType == type else { return }
            result[calendar.startOfDay(for: transaction.date), default: 0] += transaction.baseAmount
        }
    }

    private static func aggregateAmountsByDayComponent(
        _ transactions: [Transaction],
        type: TransactionType,
        calendar: Calendar
    ) -> [Int: Double] {
        transactions.reduce(into: [:]) { result, transaction in
            guard transaction.typedType == type else { return }
            result[calendar.component(.day, from: transaction.date), default: 0] += transaction.baseAmount
        }
    }

    private static func aggregateAmountsByMonth(
        _ transactions: [Transaction],
        type: TransactionType,
        calendar: Calendar
    ) -> [Int: Double] {
        transactions.reduce(into: [:]) { result, transaction in
            guard transaction.typedType == type else { return }
            result[calendar.component(.month, from: transaction.date), default: 0] += transaction.baseAmount
        }
    }
}

enum YearComparisonAnalyticsService {
    struct SelectedPeriodSnapshot {
        let expense: ComparisonSummary
        let leadingCategory: CategoryDelta?
        let period: ComparisonPeriod
        let currentReferenceDate: Date
        let previousReferenceDate: Date
    }

    struct ComparisonSummary {
        let currentAmount: Double
        let previousAmount: Double
        let deltaAmount: Double
        let deltaPercent: Double?
    }

    struct SummaryTotals {
        let net: ComparisonSummary
        let expense: ComparisonSummary
        let income: ComparisonSummary
    }

    struct CategoryDelta: Identifiable {
        let id: String
        let category: String
        let currentAmount: Double
        let previousAmount: Double
        let deltaAmount: Double
        let deltaPercent: Double?
    }

    struct TrendPoint: Identifiable {
        let id = UUID()
        let index: Int
        let label: String
        let currentAmount: Double
        let previousAmount: Double
        let isCurrentIncluded: Bool
        let isPreviousIncluded: Bool
        let isComparable: Bool
    }

    struct Snapshot {
        let period: ComparisonPeriod
        let currentReferenceDate: Date
        let previousReferenceDate: Date
        let currentPeriodLabel: String
        let previousPeriodLabel: String
        let selectedPeriod: SelectedPeriodSnapshot
        let summaryTotals: SummaryTotals
        let largestGapLabel: String
        let largestGapAmount: Double
        let expenseTrendPoints: [TrendPoint]
        let incomeTrendPoints: [TrendPoint]
        let topGrowthCategories: [CategoryDelta]
        let topDeclineCategories: [CategoryDelta]
        let patternMessage: ComparisonPatternRule.PatternMessage
    }

    static func snapshot(
        transactions: [Transaction],
        period: ComparisonPeriod,
        currentReferenceDate: Date,
        previousReferenceDate: Date,
        locale: Locale
    ) -> Snapshot? {
        let calendar = Calendar.current
        guard
            let currentInterval = dateInterval(containing: currentReferenceDate, period: period, calendar: calendar),
            let previousInterval = dateInterval(containing: previousReferenceDate, period: period, calendar: calendar)
        else {
            return nil
        }

        let currentTransactions = transactions.filter { currentInterval.contains($0.date) }
        let previousTransactions = transactions.filter { previousInterval.contains($0.date) }

        guard !currentTransactions.isEmpty || !previousTransactions.isEmpty else {
            return nil
        }

        let summaryTotals = SummaryTotals(
            net: ComparisonAnalyticsCore.comparisonSummary(
                current: ComparisonAnalyticsCore.netAmount(in: currentTransactions),
                previous: ComparisonAnalyticsCore.netAmount(in: previousTransactions)
            ),
            expense: ComparisonAnalyticsCore.comparisonSummary(
                current: ComparisonAnalyticsCore.totalAmount(of: .expense, in: currentTransactions),
                previous: ComparisonAnalyticsCore.totalAmount(of: .expense, in: previousTransactions)
            ),
            income: ComparisonAnalyticsCore.comparisonSummary(
                current: ComparisonAnalyticsCore.totalAmount(of: .income, in: currentTransactions),
                previous: ComparisonAnalyticsCore.totalAmount(of: .income, in: previousTransactions)
            )
        )

        let selectedPeriod = ComparisonAnalyticsCore.selectedPeriodSnapshot(
            period: period,
            currentReferenceDate: currentReferenceDate,
            previousReferenceDate: previousReferenceDate,
            currentTransactions: currentTransactions,
            previousTransactions: previousTransactions
        )

        let expenseTrendPoints = ComparisonAnalyticsCore.trendPoints(
            of: .expense,
            period: period,
            currentReferenceDate: currentReferenceDate,
            previousReferenceDate: previousReferenceDate,
            currentTransactions: currentTransactions,
            previousTransactions: previousTransactions,
            locale: locale,
            calendar: calendar
        )
        let incomeTrendPoints = ComparisonAnalyticsCore.trendPoints(
            of: .income,
            period: period,
            currentReferenceDate: currentReferenceDate,
            previousReferenceDate: previousReferenceDate,
            currentTransactions: currentTransactions,
            previousTransactions: previousTransactions,
            locale: locale,
            calendar: calendar
        )

        let comparablePoints = expenseTrendPoints.filter(\.isComparable)
        let largestGapPoint = comparablePoints.max { lhs, rhs in
            abs(lhs.currentAmount - lhs.previousAmount) < abs(rhs.currentAmount - rhs.previousAmount)
        }

        let categoryDeltas = ComparisonAnalyticsCore.expenseCategoryDeltas(
            currentTransactions: currentTransactions,
            previousTransactions: previousTransactions
        )
        let topGrowthCategories = categoryDeltas.filter { $0.deltaAmount > 0 }.prefix(3).map { $0 }
        let topDeclineCategories = categoryDeltas.filter { $0.deltaAmount < 0 }.prefix(3).map { $0 }

        return Snapshot(
            period: period,
            currentReferenceDate: currentReferenceDate,
            previousReferenceDate: previousReferenceDate,
            currentPeriodLabel: periodLabel(for: currentReferenceDate, period: period, locale: locale),
            previousPeriodLabel: periodLabel(for: previousReferenceDate, period: period, locale: locale),
            selectedPeriod: selectedPeriod,
            summaryTotals: summaryTotals,
            largestGapLabel: largestGapPoint?.label ?? periodLabel(for: currentReferenceDate, period: period, locale: locale),
            largestGapAmount: largestGapPoint.map { $0.currentAmount - $0.previousAmount } ?? 0,
            expenseTrendPoints: expenseTrendPoints,
            incomeTrendPoints: incomeTrendPoints,
            topGrowthCategories: Array(topGrowthCategories),
            topDeclineCategories: Array(topDeclineCategories),
            patternMessage: ComparisonPatternRule.message(
                points: comparablePoints,
                topGrowthCategories: Array(topGrowthCategories),
                topDeclineCategories: Array(topDeclineCategories)
            )
        )
    }

    private static func dateInterval(
        containing date: Date,
        period: ComparisonPeriod,
        calendar: Calendar
    ) -> DateInterval? {
        switch period {
        case .day:
            return calendar.dateInterval(of: .day, for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)
        case .month:
            return calendar.dateInterval(of: .month, for: date)
        case .year:
            return calendar.dateInterval(of: .year, for: date)
        }
    }

    private static func periodLabel(for date: Date, period: ComparisonPeriod, locale: Locale) -> String {
        ComparePeriodFormatter.label(for: date, period: period, locale: locale)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
