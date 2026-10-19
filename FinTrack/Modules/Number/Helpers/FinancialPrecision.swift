import Foundation

enum FinancialPrecision {
    nonisolated static let amountStorageScale = 2
    nonisolated static let amountDisplayScale = 2
    nonisolated static let exchangeRateStorageScale = 6
    nonisolated static let exchangeRateDisplayScale = 4
    nonisolated static let interestRateStorageScale = 4

    nonisolated static func roundAmountForStorage(_ value: Double) -> Double {
        round(value, scale: amountStorageScale)
    }

    nonisolated static func roundAmountForDisplay(_ value: Double) -> Double {
        round(value, scale: amountDisplayScale)
    }

    nonisolated static func roundExchangeRateForStorage(_ value: Double) -> Double {
        round(value, scale: exchangeRateStorageScale)
    }

    nonisolated static func roundExchangeRateForDisplay(_ value: Double) -> Double {
        round(value, scale: exchangeRateDisplayScale)
    }

    nonisolated static func roundInterestRateForStorage(_ value: Double) -> Double {
        round(value, scale: interestRateStorageScale)
    }

    nonisolated private static func round(_ value: Double, scale: Int) -> Double {
        var source = Decimal(value)
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return NSDecimalNumber(decimal: result).doubleValue
    }
}
