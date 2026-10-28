import Foundation
import Combine
import SwiftData

/// One app-owned financial draft. No persistence or fetch occurs in init.
@MainActor
final class MacQuickEntryDraft: ObservableObject {
    @Published var amount = ""
    @Published var note = ""
    @Published var currency = ""
    @Published var customCurrencyEntry = false
    @Published var categoryID: UUID?
    @Published var income = false { didSet { if oldValue != income { categoryID = nil } } }
    @Published var date = Date()
    @Published var continueAdding = false
    @Published var showsExchangeDetails = false
    @Published var rate = ""
    @Published var useBankAmount = false
    @Published var bankAmount = ""
    @Published private(set) var quoteMessage: String?
    @Published private(set) var error: String?
    @Published private(set) var savedMessage: String?
    @Published private(set) var isSaving = false
    @Published private(set) var fetching = false
    private(set) var draftID = UUID()
    private var committed: Set<UUID> = []
    private var requestID = UUID()
    private var quoteBase: String?
    var quotes: any MacFXAccountingQuotes = MacFXAccountingAdapter()
    var type: TransactionType { income ? .income : .expense }

    /// Only the explicit Other action enters editing; no sentinel enters finance data.
    func chooseCurrency(_ code: String?) {
        if let code { currency = code; customCurrencyEntry = false }
        else { customCurrencyEntry = true }
    }
    func setManualRate(_ text: String, base: String) {
        quoteBase = base
        requestID = UUID(); fetching = false; quoteMessage = nil; useBankAmount = false; rate = text
    }
    func setManualBaseAmount(_ text: String, base: String) {
        quoteBase = base
        requestID = UUID(); fetching = false; quoteMessage = nil; bankAmount = text; useBankAmount = true
    }
    func resetAmountToRate() { useBankAmount = false }
    func amountText(base: String) -> String {
        guard quoteBase == nil || quoteBase == base else { return "" }
        if useBankAmount { return bankAmount }
        guard let amount = try? MacTransactionCRUD.amount(amount), let rate = try? MacCurrency.rate(rate),
              let value = try? MacCurrency.snapshot(amount:amount,original:currency,base:base,rate:rate) else { return "" }
        return MacBankSettlement.amountText(value.baseAmount)
    }
    func displayedRate(base: String) -> String {
        guard quoteBase == nil || quoteBase == base else { return "" }
        guard useBankAmount else { return rate }
        guard let value = try? MacBankSettlement.snapshot(originalText:amount,actualText:bankAmount,original:currency,base:base) else { return "" }
        return MacBankSettlement.rateText(value.rate)
    }
    func invalidateQuote() {
        requestID = UUID(); fetching = false; quoteMessage = nil; rate = ""
    }
    func fetchRate(base: String) async {
        let token = UUID(); requestID = token
        let source = currency, day = MacFXDates.tag(date, calendar:.current)
        fetching = true; error = nil
        defer { if requestID == token { fetching = false } }
        do {
            let result = try await quotes.accountingQuote(pair:MacFXPair(base:source,quote:base),day:day)
            guard token == requestID, source == currency, day == MacFXDates.tag(date,calendar:.current) else { return }
            guard result.identity.purpose == .accountingDay, result.identity.requested == .day(day), result.identity.pair == (try MacFXPair(base:source,quote:base)) else { throw MacFXContractFailure.invalidEvidence }
            quoteBase = base
            rate = String(format: "%.6f", result.unitRate)
            quoteMessage = "交易日 " + day + " · " + MacFXApplication.shared.sourceLabel(result.identity.sourceID) + "，请核对银行结算。"
        } catch {
            guard token == requestID else { return }
            self.error = MacLocalization.error(error)
        }
    }
    @discardableResult
    func save(context: ModelContext, preferredBase: String) throws -> UUID? {
        guard !isSaving, !committed.contains(draftID) else { return nil }
        isSaving = true; defer { isSaving = false }
        do {
            let base = try MacCurrency.ledgerCurrency(in:context,preferred:preferredBase)
            let source = try MacCurrency.code(currency.isEmpty ? base : currency)
            // Fetch current categories at the final write boundary: deletion/rename
            // while this draft was hidden must never recreate a stale selection.
            let categories = try context.fetch(FetchDescriptor<FinTrackMac.Category>())
            guard let id = categoryID, let category = categories.first(where: { $0.id == id && $0.deletedAt == nil && $0.type == type.rawValue }) else {
                throw MacSettingsFailure.invalid("分类已变更，请重新选择有效分类。")
            }
            guard source == base || quoteBase == nil || quoteBase == base else {
                throw MacSettingsFailure.invalid("账本本位币已变化，请重新核对汇率或本币记账金额。草稿尚未保存。")
            }
            let resolvedRate: Double
            if source == base { resolvedRate = 1 }
            else if useBankAmount { resolvedRate = 1 }
            else { resolvedRate = try MacCurrency.rate(rate) }
            let saved = try MacTransactionCRUD.create(.init(type:type,amountText:amount,category:category.name,note:note,date:date),currency:base,originalCurrency:source,exchangeRate:resolvedRate,actualBaseAmount:source != base && useBankAmount ? try MacTransactionCRUD.amount(bankAmount) : nil,in:context)
            committed.insert(draftID)
            if committed.count > 500 { committed = [draftID] }
            amount = ""; note = ""; error = nil
            // The next transaction may reuse its rate, never the previous
            // transaction's explicitly settled monetary amount.
            quoteBase = base
            rate = MacBankSettlement.reusableRateText(saved.exchangeRateToBase)
            useBankAmount = false; bankAmount = ""
            requestID = UUID(); fetching = false; quoteMessage = nil
            savedMessage = "已保存"; draftID = UUID()
            return saved.id
        } catch { self.error = MacLocalization.error(error); throw error }
    }
}
