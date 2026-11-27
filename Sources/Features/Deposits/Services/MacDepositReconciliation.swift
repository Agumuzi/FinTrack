import SwiftUI
import SwiftData

enum MacDepositReconciliation {
    /// Resolve the exact persisted occurrence. CRUD protection remains in force.
    static func deposit(for receipt: Transaction, in context: ModelContext) throws -> DepositRecord {
        let rows = try context.fetch(FetchDescriptor<Transaction>())
        guard let identity = TransactionRecognition.depositIdentity(receipt.note),
              let deposit = try context.fetch(FetchDescriptor<DepositRecord>()).first(where: { $0.id == identity.depositID && $0.deletedAt == nil }),
              rows.contains(where: { $0 === receipt }),
              MacDepositsData.audit(deposit, transactions: rows).receipts.contains(where: { $0 === receipt })
        else { throw MacSettingsFailure.invalid(L10n.text("receipt.review.invalid")) }
        return deposit
    }

    static func mayBeIncludedInCash(_ receipt: Transaction, in context: ModelContext) throws -> Bool {
        guard !TransactionRecognition.isRealized(receipt), let profile = try MacLiquidity.profile(in: context),
              let data = profile.liquidityData else { return false }
        let state = try LiquidityState.decode(data)
        guard state.currency == receipt.baseCurrencyCode else { throw MacCurrency.Failure.mixedBooks }
        let reference = max(state.confirmedAt, state.events.filter { $0.kind == "calibration" }.map(\.date).max() ?? state.confirmedAt)
        return reference >= Calendar.current.startOfDay(for: receipt.date)
    }

    static func confirm(_ receipt: Transaction, deposit: DepositRecord, amount: Double, rate: Double, partial: Bool = false,
                        includedInCash: Bool = false, in context: ModelContext) throws {
        try MacRecoveryJournal.assertWritable(in:context)
        guard !MacAutomaticPosting.isRunning, !context.hasChanges,
              try self.deposit(for: receipt, in: context) === deposit,
              rate == receipt.exchangeRateToBase,
              amount.isFinite, amount >= 0, amount <= 1_000_000_000_000 else { throw MacSettingsFailure.invalid(L10n.text("mac.depositReconciliation.confirm.56224673cb")) }
        let rounded = FinancialPrecision.roundAmountForStorage(amount)
        if amount != receipt.originalAmount, abs(amount - rounded) > amount.ulp * 2 {
            throw MacTransactionCRUD.PostingError.amountPrecision
        }
        let actual = amount == receipt.originalAmount ? amount : rounded
        let duplicates = try context.fetch(FetchDescriptor<Transaction>()).filter { ($0.note ?? "").contains(MacDepositSettlement.receiptMarker(depositID: deposit.id, date: receipt.date, monthly: deposit.typedInterestSettlementMode == .monthly)) }
        guard duplicates.count == 1 else { throw MacSettingsFailure.invalid(L10n.text("mac.depositReconciliation.confirm.da12d11804")) }
        if partial {
            guard let expected = MacDepositTerms.schedule(deposit).first(where: { $0.date == receipt.date })?.interest,
                  rounded < expected else { throw MacSettingsFailure.invalid(L10n.text("deposit.earnings.partial.invalid")) }
        }
        let snapshot = try MacCurrency.snapshot(amount: actual, original: receipt.originalCurrency, base: receipt.baseCurrencyCode, rate: rate)
        let original = receipt.originalAmount
        let cashMayIncludeReceipt = try mayBeIncludedInCash(receipt, in: context)
        guard !includedInCash || cashMayIncludeReceipt else { throw MacSettingsFailure.invalid(L10n.text("receipt.review.invalid")) }
        do {
            // Freeze old recognition bridges before changing any receipt amount/state.
            try MacLiquidity.normalizeRecognition(in: context)
            if includedInCash, let profile = try MacLiquidity.profile(in: context), let data = profile.liquidityData {
                var state = try LiquidityState.decode(data)
                state.events.append(.init(depositID: deposit.id, kind: "interestAlreadyIncluded", amount: -snapshot.baseAmount, date: receipt.date))
                profile.liquidityData = try state.encode()
            }
            receipt.originalAmount = actual
            receipt.baseAmount = snapshot.baseAmount; receipt.amount = snapshot.baseAmount
            receipt.note = TransactionRecognition.replacingPendingState(receipt.note) + " [FTVerified] 核对前金额:\(MacNumberInput.presentation(String(original)))" + (partial ? " [FTPartial]" : "")
            receipt.updatedAt = Date()
            if receipt.syncVersion < Int.max { receipt.syncVersion += 1 }
            try context.save()
        } catch { context.rollback(); throw error }
    }
}

struct MacDepositReceiptReviewView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    let deposit: DepositRecord
    let receipt: Transaction
    var onSaved: () -> Void = {}
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var partial = false
    @State private var offersCashChoice = false
    @State private var includedInCash = false
    @State private var error: String?
    private var cashChange: String? {
        guard let entered = try? MacFinancialSettings.nonnegativeAmount(amount),
              let value = try? MacCurrency.snapshot(amount: entered, original: receipt.originalCurrency,
                                                     base: receipt.baseCurrencyCode, rate: receipt.exchangeRateToBase) else { return nil }
        let old = TransactionRecognition.isRealized(receipt) ? receipt.baseAmount : 0
        let delta = includedInCash ? 0 : value.baseAmount - old
        let text = (delta > 0 ? "+" : "") + MacOverviewStyle.money(delta) + " " + receipt.baseCurrencyCode
        return L10n.format("deposit.confirm.cashDifference", text)
    }
    var body: some View {
        MacFormShell(width: 520) { Text(L10n.text("receipt.review.action")).appFont(.dialogTitle, weight: .semibold) } fields: {
            VStack(alignment: .leading, spacing: 14) {
                Text(deposit.bankName + " · " + MacDateDisplay.string(receipt.date))
                Text(MacOverviewStyle.money(deposit.originalPrincipal) + " " + deposit.originalCurrency + " · " + MacDateDisplay.string(deposit.startDate) + " – " + MacDateDisplay.string(deposit.maturityDate)).appFont(.caption).foregroundStyle(.secondary)
                Text(L10n.text("mac.depositReconciliation.MacFormShell.16c3cefe93") + MacOverviewStyle.money(receipt.originalAmount) + " " + receipt.originalCurrency).foregroundStyle(.secondary)
                MacFinanceNumberField(title: L10n.text("mac.depositReconciliation.MacFinanceNumberField.6084a059f1"), text: $amount, identifier: "depositActualInterest")
                Toggle(L10n.text("deposit.earnings.partial.label"), isOn: $partial).accessibilityIdentifier("depositInterestPartial")
                Text(L10n.text("deposit.earnings.partial.help")).appFont(.caption).foregroundStyle(.secondary)
                if receipt.originalCurrency != receipt.baseCurrencyCode {
                    Text(L10n.text("receipt.review.storedFX") + " " + receipt.exchangeRateToBase.formatted(.number.precision(.fractionLength(0...12))) + " · " + MacOverviewStyle.money(receipt.baseAmount) + " " + receipt.baseCurrencyCode).appFont(.caption).foregroundStyle(.secondary)
                }
                if offersCashChoice {
                    Toggle(L10n.text("receipt.review.includedCash"), isOn: $includedInCash).accessibilityIdentifier("depositInterestIncludedCash")
                    Text(L10n.text("receipt.review.cashHelp")).appFont(.caption).foregroundStyle(.secondary)
                }
                if let cashChange { Text(cashChange).accessibilityIdentifier("receiptReviewCashDifference") }
                Text(L10n.text("mac.depositReconciliation.MacFormShell.bd46325fe5")).appFont(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }
        } footer: {
            HStack { Button(L10n.text("mac.depositReconciliation.MacFormShell.2cd0f3be87")) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(L10n.text("mac.depositReconciliation.MacFormShell.b151c87932")) {
                do { try MacDepositReconciliation.confirm(receipt, deposit: deposit, amount: amount == MacTransactionCRUD.amountEditingText(receipt.originalAmount) ? receipt.originalAmount : MacFinancialSettings.nonnegativeAmount(amount), rate: receipt.exchangeRateToBase, partial: partial, includedInCash: includedInCash, in: context); onSaved(); dismiss() }
                catch { self.error = MacLocalization.error(error) }
            }.keyboardShortcut(.defaultAction).accessibilityIdentifier("depositReviewSave") }
        }.onAppear {
            amount = String(receipt.originalAmount); partial = TransactionRecognition.depositStateContains("[FTPartial]", in: receipt.note)
            do { offersCashChoice = try MacDepositReconciliation.mayBeIncludedInCash(receipt, in: context); includedInCash = offersCashChoice }
            catch { self.error = MacLocalization.error(error) }
        }
    }
}
