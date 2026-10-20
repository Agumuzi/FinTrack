import Foundation

enum ComparePeriodFormatter {
    static func label(
        for date: Date,
        period: ComparisonPeriod,
        locale: Locale,
        calendar: Calendar = .current
    ) -> String {
        switch period {
        case .day:
            return dayLabel(for: date, locale: locale)
        case .week:
            return weekLabel(containing: date, locale: locale, calendar: calendar)
        case .month:
            return monthLabel(for: date, locale: locale)
        case .year:
            return yearLabel(for: date, locale: locale)
        }
    }

    private static func dayLabel(for date: Date, locale: Locale) -> String {
        if isChineseLocale(locale) {
            return string(from: date, format: "yyyy年M月d日", locale: locale)
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func weekLabel(
        containing date: Date,
        locale: Locale,
        calendar: Calendar
    ) -> String {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date),
              let endDate = calendar.date(byAdding: .day, value: -1, to: interval.end)
        else {
            return dayLabel(for: date, locale: locale)
        }

        let startDate = interval.start
        let startYear = calendar.component(.year, from: startDate)
        let endYear = calendar.component(.year, from: endDate)
        let startMonth = calendar.component(.month, from: startDate)
        let endMonth = calendar.component(.month, from: endDate)
        let startDay = calendar.component(.day, from: startDate)
        let endDay = calendar.component(.day, from: endDate)

        if isChineseLocale(locale) {
            if startYear == endYear {
                if startMonth == endMonth {
                    return "\(startMonth)月\(startDay)日-\(endDay)日 \(startYear)"
                }
                return "\(startMonth)月\(startDay)日-\(endMonth)月\(endDay)日 \(startYear)"
            }
            return "\(startYear)年\(startMonth)月\(startDay)日-\(endYear)年\(endMonth)月\(endDay)日"
        }

        let monthDayFormatter = DateFormatter()
        monthDayFormatter.locale = locale
        monthDayFormatter.setLocalizedDateFormatFromTemplate("MMM d")

        let dayFormatter = DateFormatter()
        dayFormatter.locale = locale
        dayFormatter.setLocalizedDateFormatFromTemplate("d")

        let startText = monthDayFormatter.string(from: startDate)
        let endText = startMonth == endMonth
            ? dayFormatter.string(from: endDate)
            : monthDayFormatter.string(from: endDate)

        if startYear == endYear {
            return "\(startText)-\(endText), \(startYear)"
        }
        return "\(startText), \(startYear)-\(endText), \(endYear)"
    }

    private static func monthLabel(for date: Date, locale: Locale) -> String {
        if isChineseLocale(locale) {
            return string(from: date, format: "yyyy年M月", locale: locale)
        }
        return string(from: date, format: "MMM yyyy", locale: locale)
    }

    private static func yearLabel(for date: Date, locale: Locale) -> String {
        if isChineseLocale(locale) {
            return string(from: date, format: "yyyy年", locale: locale)
        }
        return string(from: date, format: "yyyy", locale: locale)
    }

    private static func string(from date: Date, format: String, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static func isChineseLocale(_ locale: Locale) -> Bool {
        locale.identifier.hasPrefix("zh")
    }
}
