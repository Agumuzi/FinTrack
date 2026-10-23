import SwiftUI
import SwiftData

enum MacDepositReconciliation {
    static func confirm(_ receipt: Transaction, deposit: DepositRecord, amount: Double, rate: Double, in context: ModelContext) throws {
        guard !MacAutomaticPosting.isRunning, !context.hasChanges, receipt.deletedAt == nil,
              receipt.typedType == .income, receipt.originalCurrency == deposit.originalCurrency,
              receipt.baseCurrencyCode == deposit.baseCurrencyCode,
              (receipt.note ?? "").contains("[FTDep:\(deposit.id.uuidString):"),
              MacDepositTerms.schedule(deposit).contains(where: { $0.date == receipt.date && (receipt.note ?? "").contains(MacDepositSettlement.receiptMarker(depositID: deposit.id, date: $0.date, monthly: deposit.typedInterestSettlementMode == .monthly)) }),
              amount.isFinite, amount >= 0, amount <= 1_000_000_000_000 else { throw MacSettingsFailure.invalid("入账关联或金额无效，请重新核对") }
        let duplicates = try context.fetch(FetchDescriptor<Transaction>()).filter { ($0.note ?? "").contains(MacDepositSettlement.receiptMarker(depositID: deposit.id, date: receipt.date, monthly: deposit.typedInterestSettlementMode == .monthly)) }
        guard duplicates.count == 1 else { throw MacSettingsFailure.invalid("存在重复入账标记，请先核对历史") }
        let snapshot = try MacCurrency.snapshot(amount: amount, original: receipt.originalCurrency, base: receipt.baseCurrencyCode, rate: rate)
        let original = receipt.originalAmount
        do {
            receipt.originalAmount = FinancialPrecision.roundAmountForStorage(amount)
            receipt.exchangeRateToBase = snapshot.rate; receipt.baseAmount = snapshot.baseAmount; receipt.amount = snapshot.baseAmount
            receipt.note = (receipt.note ?? "").replacingOccurrences(of: " [FTEstimated]", with: "").replacingOccurrences(of: "（待核对）", with: "") + " [FTVerified] 核对前金额:\(original)"
            receipt.updatedAt = Date(); try context.save()
        } catch { context.rollback(); throw error }
    }
}

struct MacDepositReceiptReviewView: View {
    let deposit: DepositRecord
    let receipt: Transaction
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var rate = ""
    @State private var error: String?
    var body: some View {
        MacFormShell(width: 480) { Text("核对实际到账利息").appFont(.dialogTitle, weight: .semibold) } fields: {
            VStack(alignment: .leading, spacing: 14) {
                Text(deposit.bankName + " · " + MacDateDisplay.string(receipt.date))
                Text("计划金额：" + MacOverviewStyle.money(receipt.originalAmount) + " " + receipt.originalCurrency).foregroundStyle(.secondary)
                MacFinanceNumberField(title: "实际到账金额", text: $amount, identifier: "depositActualInterest")
                if receipt.originalCurrency != receipt.baseCurrencyCode { MacFinanceNumberField(title: "实际记账汇率", text: $rate, identifier: "depositActualInterestRate") }
                Text("确认后更新这笔收入并标记已核对，保留原计划关联；不会再生成第二笔账目。").appFont(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }
        } footer: {
            HStack { Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("确认实际到账") {
                do { try MacDepositReconciliation.confirm(receipt, deposit: deposit, amount: MacFinancialSettings.nonnegativeAmount(amount), rate: receipt.originalCurrency == receipt.baseCurrencyCode ? 1 : MacCurrency.rate(rate), in: context); dismiss() }
                catch { self.error = MacLocalization.error(error) }
            }.keyboardShortcut(.defaultAction) }
        }.onAppear { amount = String(receipt.originalAmount); rate = String(receipt.exchangeRateToBase) }
    }
}
