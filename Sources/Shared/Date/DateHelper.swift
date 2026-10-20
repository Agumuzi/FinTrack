import Foundation

enum DateRangeDisplayUnit {
    case day
    case week
    case month
    case year
    case all
}

struct DateFilterRangeState {
    var startDate: Date
    var endDate: Date

    static func currentMonth() -> DateFilterRangeState {
        let now = Date()
        let monthStart = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: now)
        ) ?? now
        return DateFilterRangeState(startDate: monthStart, endDate: now)
    }

    var normalizedStartDate: Date {
        Calendar.current.startOfDay(for: min(startDate, endDate))
    }

    var normalizedEndDate: Date {
        let end = max(startDate, endDate)
        let startOfNextDay = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: end)
        ) ?? end
        return startOfNextDay
    }
}

enum DateHelper {
    private struct FormatterCacheKey: Hashable {
        let localeIdentifier: String
        let kind: FormatterKind
    }

    private enum FormatterKind: Hashable {
        case dateFormat(String)
        case localizedTemplate(String)
        case shortMonthSymbols
        case mediumDateStyle
        case mediumDateInterval
    }

    // DateFormatter and DateIntervalFormatter are not thread-safe. These caches
    // are used from UI formatting hot paths and cleared when the app language changes.
    private static var dateFormatterCache: [FormatterCacheKey: DateFormatter] = [:]
    private static var dateIntervalFormatterCache: [FormatterCacheKey: DateIntervalFormatter] = [:]

    private static var currentLocale: Locale {
        LanguageManager.shared.currentLocale
    }

    static func clearFormatterCache() {
        dateFormatterCache.removeAll()
        dateIntervalFormatterCache.removeAll()
    }

    private static func cachedDateFormatter(
        locale: Locale,
        kind: FormatterKind,
        configure: (DateFormatter) -> Void
    ) -> DateFormatter {
        let key = FormatterCacheKey(localeIdentifier: locale.identifier, kind: kind)
        if let formatter = dateFormatterCache[key] {
            return formatter
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        configure(formatter)
        dateFormatterCache[key] = formatter
        return formatter
    }

    private static func cachedDateIntervalFormatter(locale: Locale) -> DateIntervalFormatter {
        let key = FormatterCacheKey(localeIdentifier: locale.identifier, kind: .mediumDateInterval)
        if let formatter = dateIntervalFormatterCache[key] {
            return formatter
        }

        let formatter = DateIntervalFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        dateIntervalFormatterCache[key] = formatter
        return formatter
    }

    private static func formatter(for format: String, locale: Locale) -> DateFormatter {
        cachedDateFormatter(locale: locale, kind: .dateFormat(format)) {
            $0.dateFormat = format
        }
    }

    private static func localizedTemplateFormatter(
        template: String,
        locale: Locale
    ) -> DateFormatter {
        cachedDateFormatter(locale: locale, kind: .localizedTemplate(template)) {
            $0.setLocalizedDateFormatFromTemplate(template)
        }
    }

    private static func mediumDateFormatter(locale: Locale) -> DateFormatter {
        cachedDateFormatter(locale: locale, kind: .mediumDateStyle) {
            $0.dateStyle = .medium
        }
    }

    private static func shortMonthSymbols(for locale: Locale) -> [String] {
        cachedDateFormatter(locale: locale, kind: .shortMonthSymbols) { _ in }.shortMonthSymbols
    }

    static func isCurrentMonth(_ date: Date) -> Bool {
        Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month)
    }

    // Unified formatting through DateFormatManager
    static func displayDate(_ date: Date, using dateFormatManager: DateFormatManager) -> String {
        dateFormatManager.string(from: date)
    }

    // Legacy helpers now route to the unified formatter
    static func monthString(from date: Date, using dateFormatManager: DateFormatManager) -> String {
        displayDate(date, using: dateFormatManager)
    }

    static func dayAndMonth(from date: Date, using dateFormatManager: DateFormatManager) -> String {
        displayDate(date, using: dateFormatManager)
    }

    static func yearMonthDay(from date: Date, using dateFormatManager: DateFormatManager) -> String {
        displayDate(date, using: dateFormatManager)
    }

    static func shortDisplayDate(_ date: Date, using dateFormatManager: DateFormatManager) -> String {
        displayDate(date, using: dateFormatManager)
    }

    static func weekdayAbbreviation(from date: Date) -> String {
        formatter(for: "EEE", locale: currentLocale).string(from: date)
    }

    static func monthYearString(from date: Date) -> String {
        formatter(for: "MMMM yyyy", locale: currentLocale).string(from: date)
    }

    static func yearString(from date: Date) -> String {
        formatter(for: "yyyy", locale: currentLocale).string(from: date)
    }

    static func shortMonthName(_ month: Int) -> String {
        shortMonthSymbols(for: currentLocale)[month - 1]
    }

    static func shortMonthSymbols(locale: Locale) -> [String] {
        shortMonthSymbols(for: locale)
    }

    static func weekDates(containing date: Date) -> [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return [date]
        }

        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
    }

    static func rangeSubtitle(
        for date: Date,
        unit: DateRangeDisplayUnit
    ) -> String {
        switch unit {
        case .day:
            return mediumDateFormatter(locale: currentLocale).string(from: date)
        case .week:
            let dates = weekDates(containing: date)
            guard let start = dates.first, let end = dates.last else { return "" }
            return cachedDateIntervalFormatter(locale: currentLocale).string(from: start, to: end)
        case .month:
            return monthYearString(from: date)
        case .year:
            return yearString(from: date)
        case .all:
            return ""
        }
    }

    static func customRangeSubtitle(
        _ range: DateFilterRangeState,
        locale: Locale
    ) -> String {
        return cachedDateIntervalFormatter(locale: locale).string(
            from: range.normalizedStartDate,
            to: range.normalizedEndDate.addingTimeInterval(-1)
        )
    }

    static func weekRangeSubtitle(
        containing date: Date,
        locale: Locale,
        languageCode: String
    ) -> String {
        let dates = weekDates(containing: date)
        guard let start = dates.first, let end = dates.last else { return "" }

        let calendar = Calendar.current
        let startDay = calendar.component(.day, from: start)
        let endDay = calendar.component(.day, from: end)
        let year = calendar.component(.year, from: start)

        switch languageCode {
        case "zh-Hans":
            let month = calendar.component(.month, from: start)
            return "\(year)年\(month)月\(startDay)–\(endDay)日"
        case "ru":
            let monthWithDay = localizedTemplateFormatter(
                template: "d MMMM",
                locale: locale
            ).string(from: start)
            let dayPrefix = "\(startDay) "
            let monthText: String
            if monthWithDay.hasPrefix(dayPrefix) {
                monthText = String(monthWithDay.dropFirst(dayPrefix.count))
            } else {
                monthText = monthWithDay
            }
            return "\(startDay)–\(endDay) \(monthText) \(year)"
        default:
            let monthText = localizedTemplateFormatter(
                template: "MMM d",
                locale: locale
            ).string(from: start)
            return "\(monthText)–\(endDay), \(year)"
        }
    }

    static func isDate(
        _ date: Date,
        within selectedDate: Date,
        unit: DateRangeDisplayUnit
    ) -> Bool {
        let calendar = Calendar.current

        switch unit {
        case .day:
            return calendar.isDate(date, inSameDayAs: selectedDate)
        case .week:
            return calendar.isDate(date, equalTo: selectedDate, toGranularity: .weekOfYear)
        case .month:
            return calendar.isDate(date, equalTo: selectedDate, toGranularity: .month)
        case .year:
            return calendar.isDate(date, equalTo: selectedDate, toGranularity: .year)
        case .all:
            return true
        }
    }
}
