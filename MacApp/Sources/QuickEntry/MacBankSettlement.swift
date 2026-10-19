import Foundation

/// An explicitly entered settlement amount is authoritative. Its derived rate
/// keeps calculation precision; automatic/reference-rate storage stays unchanged.
/// Both values fit the original Transaction snapshot: no schema or note metadata.
@MainActor
enum MacBankSettlement {
    static func snapshot(originalAmount: Double, actualBaseAmount: Double, original: String, base: String) throws -> MacCurrencySnapshot {
        let source = try MacCurrency.code(original), book = try MacCurrency.code(base)
        guard originalAmount.isFinite, actualBaseAmount.isFinite,
              originalAmount > 0, actualBaseAmount > 0,
              originalAmount <= 1e12, actualBaseAmount <= 1e12 else { throw MacCurrency.Failure.invalidAmount }
        let amount = FinancialPrecision.roundAmountForStorage(originalAmount)
        let actual = FinancialPrecision.roundAmountForStorage(actualBaseAmount)
        guard amount > 0, actual > 0 else { throw MacCurrency.Failure.invalidAmount }
        if source == book {
            guard abs(actual - amount) < 0.005 else { throw MacSettingsFailure.invalid("同币种的记账金额须与原金额一致。") }
            return .init(originalAmount:amount,originalCurrency:source,baseAmount:actual,baseCurrency:book,rate:1)
        }
        let derived = actual / amount
        guard derived.isFinite, derived > 0,
              abs(FinancialPrecision.roundAmountForStorage(amount * derived) - actual) < 0.005 else { throw MacCurrency.Failure.invalidRate }
        return .init(originalAmount:amount,originalCurrency:source,baseAmount:actual,baseCurrency:book,rate:derived)
    }
    static func snapshot(originalText: String, actualText: String, original: String, base: String) throws -> MacCurrencySnapshot {
        try snapshot(originalAmount:MacTransactionCRUD.amount(originalText),actualBaseAmount:MacTransactionCRUD.amount(actualText),original:original,base:base)
    }
    /// CSV accepts the full derived rate only when it reproduces the saved cents.
    /// Recurring/deposit/loan contracts continue through their original validators.
    static func validateSavedSnapshot(amount: Double, actual: Double, source: String, base: String, rate: Double) throws {
        guard amount.isFinite, actual.isFinite, rate.isFinite, amount >= 0, actual >= 0,
              amount <= 1e12, actual <= 1e12, rate > 0, rate <= 1e14,
              abs(FinancialPrecision.roundAmountForStorage(amount) - amount) < 1e-6,
              abs(FinancialPrecision.roundAmountForStorage(actual) - actual) < 1e-6,
              abs(FinancialPrecision.roundAmountForStorage(amount * rate) - actual) < 0.005,
              source != base || (rate == 1 && abs(amount - actual) < 0.005) else {
            throw MacSettingsFailure.invalid("记账金额与保存的汇率快照不一致。")
        }
    }
    static func reusableRateText(_ rate: Double) -> String {
        let text = String(format:"%.6f",rate)
        return (try? MacCurrency.rate(text)) == nil ? "" : text
    }
    static func amountText(_ amount: Double) -> String { String(format:"%.2f",amount) }
    static func rateText(_ rate: Double) -> String { MacFXMath.formatted(rate,digits:8) }
}
