import Foundation
import SwiftData
import CoreFoundation

struct MacCurrencySnapshot: Sendable {
    let originalAmount: Double
    let originalCurrency: String
    let baseAmount: Double
    let baseCurrency: String
    let rate: Double
}

/// Read-only view of the active ledger's saved base-currency codes. A single
/// existing currency remains displayable even when the preference changed;
/// posting validation separately requires agreement with that preference.
struct MacLedgerCurrencyResolution: Equatable, Sendable {
    let currencies: [String]
    let preferredCurrency: String

    var displayCurrency: String? {
        if currencies.isEmpty { return preferredCurrency }
        return currencies.count == 1 ? currencies[0] : nil
    }

    var availableCurrencies: [String] {
        currencies.isEmpty ? [preferredCurrency] : currencies
    }

    var matchesPreference: Bool {
        currencies.isEmpty || currencies == [preferredCurrency]
    }
}

@MainActor
enum MacCurrency {
    enum Failure: LocalizedError {
        case invalidCurrency, invalidRate, invalidAmount, mixedBooks, missingRate, staleQuote
        var errorDescription: String? {
            switch self {
            case .invalidCurrency: "Enter a three-letter currency code."
            case .invalidRate: "Enter a positive finite exchange rate."
            case .invalidAmount: "The converted amount is outside the supported range."
            case .mixedBooks: "The ledger has different base currencies. Reconcile the base currency before posting."
            case .missingRate: "A foreign-currency entry needs an explicit exchange rate."
            case .staleQuote: "The rate provider did not return the requested date. Enter a verified rate manually."
            }
        }
    }

    static func code(_ raw: String) throws -> String {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 3, code.unicodeScalars.allSatisfy({ (65...90).contains($0.value) })
        else { throw Failure.invalidCurrency }
        return code
    }

    static func rate(_ text: String) throws -> Double {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty, text.allSatisfy({ "0123456789.".contains($0) }),
              text.filter({ $0 == "." }).count <= 1,
              let value = Double(text), value.isFinite, value > 0, value <= 1_000_000_000
        else { throw Failure.invalidRate }
        let rounded = FinancialPrecision.roundExchangeRateForStorage(value)
        guard rounded > 0 else { throw Failure.invalidRate }
        return rounded
    }

    static func snapshot(amount: Double, original: String, base: String,
                         rate: Double?) throws -> MacCurrencySnapshot {
        let original = try code(original), base = try code(base)
        let amount = FinancialPrecision.roundAmountForStorage(amount)
        guard amount.isFinite, amount >= 0, amount <= 1_000_000_000_000
        else { throw Failure.invalidAmount }
        let resolved: Double
        if original == base {
            guard rate == nil || rate == 1 else { throw Failure.invalidRate }
            resolved = 1
        } else {
            guard let rate else { throw Failure.missingRate }
            guard rate.isFinite, rate > 0, rate <= 1_000_000_000 else { throw Failure.invalidRate }
            resolved = FinancialPrecision.roundExchangeRateForStorage(rate)
            guard resolved > 0 else { throw Failure.invalidRate }
        }
        let converted = FinancialPrecision.roundAmountForStorage(amount * resolved)
        guard converted.isFinite, converted <= 1_000_000_000_000,
              amount == 0 || converted > 0 else { throw Failure.invalidAmount }
        return .init(originalAmount: amount, originalCurrency: original,
                     baseAmount: converted, baseCurrency: base, rate: resolved)
    }

    static func ledgerCurrency(in context: ModelContext, preferred: String) throws -> String {
        let requested = try code(preferred)
        // Posting still rejects any active mismatching book; existence queries need at most one row.
        var transactions = FetchDescriptor<Transaction>(predicate: #Predicate { $0.deletedAt == nil && $0.baseCurrencyCode != requested })
        var deposits = FetchDescriptor<DepositRecord>(predicate: #Predicate { $0.deletedAt == nil && $0.baseCurrencyCode != requested })
        var loans = FetchDescriptor<LoanRule>(predicate: #Predicate { $0.deletedAt == nil && $0.baseCurrencyCode != requested })
        var recurring = FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.deletedAt == nil && $0.baseCurrencyCode != requested })
        transactions.fetchLimit = 1; deposits.fetchLimit = 1; loans.fetchLimit = 1; recurring.fetchLimit = 1
        guard try context.fetch(transactions).isEmpty, try context.fetch(deposits).isEmpty,
              try context.fetch(loans).isEmpty, try context.fetch(recurring).isEmpty else { throw Failure.mixedBooks }
        return requested
    }

    static func resolveLedgerCurrency(
        transactions: [Transaction], deposits: [DepositRecord], loans: [LoanRule],
        recurring: [RecurringTransaction], preferred: String
    ) -> MacLedgerCurrencyResolution {
        var codes = Set(transactions.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        codes.formUnion(deposits.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        codes.formUnion(loans.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        codes.formUnion(recurring.filter { $0.deletedAt == nil }.map(\.baseCurrencyCode))
        return MacLedgerCurrencyResolution(currencies: codes.sorted(), preferredCurrency: preferred)
    }
}

/// Financial requests have a date/policy/revision-scoped cache, independent of
/// menu-bar monitoring. Missing dated quotes never become rate 1 or today's rate.
actor MacExchangeRates {
    static let shared = MacExchangeRates()
    private var evidenceCache:[String:MacFXEvidenceQuote] = [:]
    private var pending:[String:Task<MacFXEvidenceQuote,Error>] = [:]
    init() {}

    nonisolated static func dateTag(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }

    func quote(from source:String,to base:String,on date:Date,useCustomSources:Bool = false,forceRefresh:Bool = false) async throws -> Double {
        // The legacy parameter is retained for callers; the explicit accounting
        // preference now governs every financial workflow consistently.
        try await evidence(pair:MacFXPair(base:source,quote:base),day:Self.dateTag(date),forceRefresh:forceRefresh).unitRate
    }
    func evidence(pair:MacFXPair,day:String,forceRefresh:Bool = false,cycle:String = "accounting/" + UUID().uuidString) async throws -> MacFXEvidenceQuote {
        if await MacSettingsVisual.preview {
            let rates = await MacSettingsVisual.previewRates
            let raw = (rates[pair.quote] ?? 1) / (rates[pair.base] ?? 1)
            return MacFXEvidenceQuote(identity:.init(purpose:.accountingDay,pair:pair,sourceID:"isolated-fixture",sourceRevision:"fixture",requested:.day(day)),unitRate:FinancialPrecision.roundExchangeRateForStorage(raw),quoteTime:.day(day,timeZoneID:"UTC"),retrievedAt:Date(),legs:[])
        }
        let context = await MacFXApplication.shared.accountingContext
        let key = context.signature + "/" + pair.key + "/" + day
        if !forceRefresh, let value = evidenceCache[key], Date().timeIntervalSince(value.retrievedAt) < 3600 { return value }
        if let task = pending[key] { return try await task.value }
        let task = Task {
            let value = try await MacFXApplication.shared.accountingQuote(pair:pair,day:day,expectedSignature:context.signature,cycle:cycle)
            let rate = FinancialPrecision.roundExchangeRateForStorage(value.unitRate)
            guard value.unitRate <= 1_000_000_000, rate.isFinite, rate > 0 else { throw MacCurrency.Failure.staleQuote }
            return MacFXEvidenceQuote(identity:value.identity,unitRate:rate,quoteTime:value.quoteTime,retrievedAt:value.retrievedAt,legs:value.legs)
        }
        pending[key] = task; defer { pending[key] = nil }
        let result = try await task.value; evidenceCache[key] = result
        if evidenceCache.count > 256, let oldest = evidenceCache.min(by:{$0.value.retrievedAt < $1.value.retrievedAt})?.key { evidenceCache.removeValue(forKey:oldest) }
        return result
    }

    nonisolated static func decode(_ data: Data, source: String, base: String, dateTag: String) throws -> Double {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["date"] as? String == dateTag,
              let rates = root[source] as? [String: Any],
              let number = rates[base] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { throw MacCurrency.Failure.staleQuote }
        let rate = number.doubleValue
        guard rate.isFinite, rate > 0, rate <= 1_000_000_000 else { throw MacCurrency.Failure.staleQuote }
        let result = FinancialPrecision.roundExchangeRateForStorage(rate)
        guard result > 0 else { throw MacCurrency.Failure.staleQuote }
        return result
    }
}
