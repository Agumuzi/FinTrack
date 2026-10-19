import Foundation

nonisolated struct MacFXConfiguration: Codable, Equatable {
    static let storageKey = "v3_fx_monitor"
    var version = 1
    var displayUnits = 1
    var rateDigits = 4
    var automatic = false
    var intervalMinutes = 30
    var refreshOnOpen = true
    var openMaxAgeMinutes = 10
    var sourcePolicy = "free"
    var accountingSourcePolicy = "free"
    var referenceCurrency = "USD"
    var watchedPairs: [MacFXPair] = [try! .init(base: "USD", quote: "CNY"), try! .init(base: "EUR", quote: "CNY"), try! .init(base: "RUB", quote: "CNY"), try! .init(base: "JPY", quote: "CNY")]
    var converterCurrencies = ["USD", "CNY", "EUR", "RUB", "JPY", "GBP", "CHF", "HKD"]
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T { c.contains(key) ? try c.decode(T.self, forKey: key) : fallback }
        version = try read(.version, 1)
        guard version == 1 else { throw MacFXContractFailure.invalidEvidence }
        displayUnits = try read(.displayUnits, 1); rateDigits = try read(.rateDigits, 4)
        automatic = try read(.automatic, false); intervalMinutes = try read(.intervalMinutes, 30)
        refreshOnOpen = try read(.refreshOnOpen, true); openMaxAgeMinutes = try read(.openMaxAgeMinutes, 10)
        sourcePolicy = try read(.sourcePolicy, "free"); accountingSourcePolicy = try read(.accountingSourcePolicy, "free")
        referenceCurrency = try read(.referenceCurrency, "USD")
        watchedPairs = try read(.watchedPairs, watchedPairs); converterCurrencies = try read(.converterCurrencies, converterCurrencies)
        self = normalized()
    }
    func normalized() -> Self {
        var c = self
        c.version = 1
        if ![1,100].contains(c.displayUnits) { c.displayUnits = 1 }
        if ![2,4,6].contains(c.rateDigits) { c.rateDigits = 4 }
        if !(1...1440).contains(c.intervalMinutes) { c.intervalMinutes = 30 }
        if !(1...1440).contains(c.openMaxAgeMinutes) { c.openMaxAgeMinutes = 10 }
        if c.sourcePolicy == "auto" || (c.sourcePolicy != "free" && UUID(uuidString:c.sourcePolicy) == nil) { c.sourcePolicy = "free" }
        if c.accountingSourcePolicy != "free" && UUID(uuidString:c.accountingSourcePolicy) == nil { c.accountingSourcePolicy = "free" }
        if (try? MacFXPair(base: c.referenceCurrency, quote: c.referenceCurrency)) == nil { c.referenceCurrency = "USD" }
        c.referenceCurrency = c.referenceCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var pairs = Set<MacFXPair>(); c.watchedPairs = c.watchedPairs.filter { $0.base != $0.quote && pairs.insert($0).inserted }
        var codes = Set<String>(); c.converterCurrencies = c.converterCurrencies.compactMap { try? MacFXPair(base: $0, quote: $0).base }.filter { codes.insert($0).inserted }
        return c
    }
}

nonisolated enum MacMenuIconStyle: String, Codable, CaseIterable { case application, book, arrows
    var title: String { switch self { case .application: "FinTrack"; case .book: "账本"; case .arrows: "换算" } }
}
nonisolated enum MacMenuInformation: String, Codable, CaseIterable { case icon, iconAndRate, rate
    var title: String { switch self { case .icon: "仅图标"; case .iconAndRate: "图标与汇率"; case .rate: "仅汇率" } }
}
