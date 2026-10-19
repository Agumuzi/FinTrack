import Foundation

enum CompareAvailabilityRule {
    static let minimumMeaningfulPreviousYearMonths = 6

    struct Evaluation {
        let availableYears: [String]
        let currentYear: Int
        let previousYear: Int
        let currentYearMonthCount: Int
        let previousYearMonthCount: Int
        let isEligible: Bool

        static func empty(referenceDate: Date) -> Evaluation {
            let currentYear = Calendar.current.component(.year, from: referenceDate)
            return Evaluation(
                availableYears: [],
                currentYear: currentYear,
                previousYear: currentYear - 1,
                currentYearMonthCount: 0,
                previousYearMonthCount: 0,
                isEligible: false
            )
        }
    }

    static func evaluate(
        earliestTransactionDate: Date?,
        recentTransactions: [Transaction],
        referenceDate: Date
    ) -> Evaluation {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: referenceDate)
        let previousYear = currentYear - 1
        let firstYear = earliestTransactionDate.map { calendar.component(.year, from: $0) } ?? currentYear
        let availableYears = firstYear <= currentYear
            ? Array(firstYear...currentYear).map(String.init)
            : []

        let monthsByYear = Dictionary(grouping: recentTransactions) {
            calendar.component(.year, from: $0.date)
        }
        .mapValues { yearTransactions in
            Set(yearTransactions.map { calendar.component(.month, from: $0.date) })
        }

        let currentYearMonthCount = monthsByYear[currentYear]?.count ?? 0
        let previousYearMonthCount = monthsByYear[previousYear]?.count ?? 0
        let isEligible = currentYearMonthCount >= 1 &&
            previousYearMonthCount >= minimumMeaningfulPreviousYearMonths

        return Evaluation(
            availableYears: availableYears,
            currentYear: currentYear,
            previousYear: previousYear,
            currentYearMonthCount: currentYearMonthCount,
            previousYearMonthCount: previousYearMonthCount,
            isEligible: isEligible
        )
    }
}
