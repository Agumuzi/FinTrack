import SwiftUI
import SwiftData

enum MacDepositReconciliation {
    static func confirm(_ receipt: Transaction, deposit: DepositRecord, amount: Double, rate: Double, partial: Bool = false, in context: ModelContext) throws {
        try MacRecoveryJournal.assertWritable(in:context)
        guard !MacAutomaticPosting.isRunning, !context.hasChanges, receipt.deletedAt == nil,
              receipt.typedType == .income, receipt.originalCurrency == deposit.originalCurrency,
              receipt.baseCurrencyCode == deposit.baseCurrencyCode,
              (receipt.note ?? "").contains("[FTDep:\(deposit.id.uuidString):"),
              MacDepositTerms.schedule(deposit).contains(where: { $0.date == receipt.date && (receipt.note ?? "").contains(MacDepositSettlement.receiptMarker(depositID: deposit.id, date: $0.date, monthly: deposit.typedInterestSettlementMode == .monthly)) }),
              amount.isFinite, amount >= 0, amount <= 1_000_000_000_000 else { throw MacSettingsFailure.invalid(L10n.text("mac.depositReconciliation.confirm.56224673cb")) }
        let duplicates = try context.fetch(FetchDescriptor<Transaction>()).filter { ($0.note ?? "").contains(MacDepositSettlement.receiptMarker(depositID: deposit.id, date: receipt.date, monthly: deposit.typedInterestSettlementMode == .monthly)) }
        guard duplicates.count == 1 else { throw MacSettingsFailure.invalid(L10n.text("mac.depositReconciliation.confirm.da12d11804")) }
        if partial {
            guard let expected = MacDepositTerms.schedule(deposit).first(where: { $0.date == receipt.date })?.interest,
                  amount < expected else { throw MacSettingsFailure.invalid(L10n.text("deposit.earnings.partial.invalid")) }
        }
        let snapshot = try MacCurrency.snapshot(amount: amount, original: receipt.originalCurrency, base: receipt.baseCurrencyCode, rate: rate)
        let original = receipt.originalAmount
        do {
            receipt.originalAmount = FinancialPrecision.roundAmountForStorage(amount)
            receipt.exchangeRateToBase = snapshot.rate; receipt.baseAmount = snapshot.baseAmount; receipt.amount = snapshot.baseAmount
            receipt.note = (receipt.note ?? "").replacingOccurrences(of: " [FTEstimated]", with: "").replacingOccurrences(of: "（待核对）", with: "").replacingOccurrences(of: " [FTPartial]", with: "") + " [FTVerified] 核对前金额:\(MacNumberInput.presentation(String(original)))" + (partial ? " [FTPartial]" : "")
            receipt.updatedAt = Date(); try context.save()
        } catch { context.rollback(); throw error }
    }
}

struct MacDepositReceiptReviewView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    let deposit: DepositRecord
    let receipt: Transaction
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var rate = ""
    @State private var partial = false
    @State private var error: String?
    var body: some View {
        MacFormShell(width: 480) { Text(L10n.text("mac.depositReconciliation.MacFormShell.dd493c2653")).appFont(.dialogTitle, weight: .semibold) } fields: {
            VStack(alignment: .leading, spacing: 14) {
                Text(deposit.bankName + " · " + MacDateDisplay.string(receipt.date))
                Text(L10n.text("mac.depositReconciliation.MacFormShell.16c3cefe93") + MacOverviewStyle.money(receipt.originalAmount) + " " + receipt.originalCurrency).foregroundStyle(.secondary)
                MacFinanceNumberField(title: L10n.text("mac.depositReconciliation.MacFinanceNumberField.6084a059f1"), text: $amount, identifier: "depositActualInterest")
                Toggle(L10n.text("deposit.earnings.partial.label"), isOn: $partial).accessibilityIdentifier("depositInterestPartial")
                Text(L10n.text("deposit.earnings.partial.help")).appFont(.caption).foregroundStyle(.secondary)
                if receipt.originalCurrency != receipt.baseCurrencyCode { MacFinanceNumberField(title: L10n.text("mac.depositReconciliation.MacFinanceNumberField.3b230879f8"), text: $rate, identifier: "depositActualInterestRate", digits: 6) }
                Text(L10n.text("mac.depositReconciliation.MacFormShell.bd46325fe5")).appFont(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }
        } footer: {
            HStack { Button(L10n.text("mac.depositReconciliation.MacFormShell.2cd0f3be87")) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(L10n.text("mac.depositReconciliation.MacFormShell.b151c87932")) {
                do { try MacDepositReconciliation.confirm(receipt, deposit: deposit, amount: MacFinancialSettings.nonnegativeAmount(amount), rate: receipt.originalCurrency == receipt.baseCurrencyCode ? 1 : MacCurrency.rate(rate), partial: partial, in: context); dismiss() }
                catch { self.error = MacLocalization.error(error) }
            }.keyboardShortcut(.defaultAction) }
        }.onAppear { amount = String(receipt.originalAmount); rate = String(receipt.exchangeRateToBase); partial = (receipt.note ?? "").contains("[FTPartial]") }
    }
}
