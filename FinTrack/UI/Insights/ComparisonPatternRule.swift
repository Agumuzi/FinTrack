import Foundation

enum ComparisonPatternRule {
    enum PatternType {
        case concentratedDifference
        case evenlySpreadDifference
        case singleDriverIncrease
        case singleDriverDecrease
        case multiDriverChange
        case minimalChange
        case insufficientPatternData
    }

    struct PatternMessage {
        let patternType: PatternType
        let localizedTemplateKey: String
        let variables: [String]

        func localizedText(using languageManager: LanguageManager) -> String {
            guard !variables.isEmpty else {
                return languageManager.ui(localizedTemplateKey)
            }
            return String(
                format: languageManager.uiFormat(localizedTemplateKey),
                arguments: variables.map { $0 as CVarArg }
            )
        }
    }

    static func message(
        points: [YearComparisonAnalyticsService.TrendPoint],
        topGrowthCategories: [YearComparisonAnalyticsService.CategoryDelta],
        topDeclineCategories: [YearComparisonAnalyticsService.CategoryDelta]
    ) -> PatternMessage {
        let comparablePoints = points.filter(\.isComparable)
        guard !comparablePoints.isEmpty else {
            return PatternMessage(
                patternType: .insufficientPatternData,
                localizedTemplateKey: UIStringKey.Insights.comparePatternInsufficientData,
                variables: []
            )
        }

        let pointDeltas = comparablePoints.map { point in
            (label: point.label, delta: point.currentAmount - point.previousAmount)
        }
        let positivePoints = pointDeltas.filter { $0.delta > 0 }
        let negativePoints = pointDeltas.filter { $0.delta < 0 }
        let totalAbsoluteDelta = pointDeltas.reduce(0.0) { $0 + abs($1.delta) }
        let dominantPoints = pointDeltas
            .sorted { abs($0.delta) > abs($1.delta) }
            .prefix(2)
        let dominantShare = dominantPoints.reduce(0.0) { $0 + abs($1.delta) } / max(totalAbsoluteDelta, 0.01)
        let totalSignedDelta = pointDeltas.reduce(0.0) { $0 + $1.delta }

        if abs(totalSignedDelta) < 0.01 {
            return PatternMessage(
                patternType: .minimalChange,
                localizedTemplateKey: UIStringKey.Insights.comparePatternMinimalChange,
                variables: []
            )
        }

        if positivePoints.count >= max(1, Int(ceil(Double(comparablePoints.count) * 0.66))) {
            return PatternMessage(
                patternType: .evenlySpreadDifference,
                localizedTemplateKey: UIStringKey.Insights.comparePatternHigherBaseline,
                variables: []
            )
        }

        if negativePoints.count >= max(1, Int(ceil(Double(comparablePoints.count) * 0.66))) {
            return PatternMessage(
                patternType: .evenlySpreadDifference,
                localizedTemplateKey: UIStringKey.Insights.comparePatternLowerBaseline,
                variables: []
            )
        }

        if dominantShare >= 0.55, dominantPoints.count >= 2 {
            let labels = dominantPoints.map(\.label).joined(separator: " / ")
            return PatternMessage(
                patternType: .concentratedDifference,
                localizedTemplateKey: UIStringKey.Insights.comparePatternConcentratedFormat,
                variables: [labels]
            )
        }

        if isSingleDominant(topGrowthCategories), let leadingGrowth = topGrowthCategories.first, leadingGrowth.deltaAmount > 0 {
            let category = CategoryUsageHelper.localizedDisplayName(for: leadingGrowth.category)
            return PatternMessage(
                patternType: .singleDriverIncrease,
                localizedTemplateKey: UIStringKey.Insights.comparePatternSingleDriverIncrease,
                variables: [category]
            )
        }

        if isSingleDominant(topDeclineCategories), let leadingDecline = topDeclineCategories.first, leadingDecline.deltaAmount < 0 {
            let category = CategoryUsageHelper.localizedDisplayName(for: leadingDecline.category)
            return PatternMessage(
                patternType: .singleDriverDecrease,
                localizedTemplateKey: UIStringKey.Insights.comparePatternSingleDriverDecrease,
                variables: [category]
            )
        }

        if !topGrowthCategories.isEmpty || !topDeclineCategories.isEmpty {
            return PatternMessage(
                patternType: .multiDriverChange,
                localizedTemplateKey: UIStringKey.Insights.comparePatternMultiDriverChange,
                variables: []
            )
        }

        return PatternMessage(
            patternType: .evenlySpreadDifference,
            localizedTemplateKey: UIStringKey.Insights.comparePatternSpread,
            variables: []
        )
    }

    private static func isSingleDominant(_ deltas: [YearComparisonAnalyticsService.CategoryDelta]) -> Bool {
        guard let first = deltas.first else { return false }
        guard deltas.count > 1, let second = deltas.dropFirst().first else {
            return abs(first.deltaAmount) >= 0.01
        }
        return abs(first.deltaAmount) >= abs(second.deltaAmount) * 1.4
    }
}
