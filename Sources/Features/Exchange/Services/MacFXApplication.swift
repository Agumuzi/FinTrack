import Foundation
import Combine
import AppKit

/// FinTrack's single directory; query configuration never needs a ledger.
enum MacFXCatalog {
    static var codes: [String] {
        let raw: [String] = MacSettingsStore.load("v2_currencies", fallback: [])
        var seen: Set<String> = []
        return raw.compactMap { try? MacFXPair(base: $0, quote: $0).base }.filter { seen.insert($0).inserted }
    }
    static var enabled: [String] {
        let disabled: [String] = MacSettingsStore.load("v2_disabled_currencies", fallback: [])
        return codes.filter { !disabled.contains($0) }
    }
}

@MainActor
final class MacFXQuerySession: ObservableObject {
    @Published var converter: MacFXConverterState
    var inputText: String { get { converter.inputText } set { converter.edit(newValue) } }
    var inputCurrency: String { get { converter.activeCode ?? "" } set { converter.select(newValue) } }
    @Published var expandedPair: String?
    @Published var cardInputs: [String: MacFXConverterState] = [:]
    @Published var cardModes: [String: MacFXCardMode] = [:]
    @Published var cardRanges: [String: MacFXHistoryRange] = [:]
    @Published var ratesScrollPair: String?
    @Published var converterScrollCode: String?
    @Published var settingsQueryBase: String?
    @Published var settingsSectionRequest: String?
    init(currency: String) { converter = MacFXConverterState(currency: currency) }
    func cardInput(_ pair: MacFXPair) -> MacFXConverterState { cardInputs[pair.key] ?? MacFXConverterState(currency: pair.base) }
    func selectCardCurrency(_ code: String, pair: MacFXPair) {
        var value = cardInput(pair); value.select(code); cardInputs[pair.key] = value
    }
    func editCard(_ text: String, pair: MacFXPair) {
        var value = cardInput(pair); value.edit(text); cardInputs[pair.key] = value
    }
}

/// FinTrack storage/lifecycle adapter around the model-free monitoring core.
@MainActor
final class MacFXApplication: ObservableObject {
    static let shared = MacFXApplication()
    static let cacheKey = "v3_fx_monitor_cache"
    let monitor: MacFXMonitor
    let query: MacFXQuerySession
    let history: MacFXHistoryService
    let transport: MacFXProviderAdapter
    private let accountingTransport: MacFXProviderAdapter
    var menuPair: MacFXPair?
    private var observers: [AnyCancellable] = []
    private var preferencesFingerprint: [Data?] = []
    private var catalogSignature: String
    @Published private(set) var settingsError: String?

    private init() {
        let adapter = MacFXProviderAdapter()
        // The application host must not issue background requests while hosted
        // model tests mutate preferences. Explicit provider probes use their own adapters.
        adapter.mock = MacSettingsVisual.preview || (MacPreferences.isTesting && ProcessInfo.processInfo.environment["FINTRACK_FX_MOCK"] != "0")
        transport = adapter
        let accounting = MacFXProviderAdapter()
        accounting.mock = MacSettingsVisual.preview || (MacPreferences.isTesting && ProcessInfo.processInfo.environment["FINTRACK_FX_MOCK"] == "1")
        accountingTransport = accounting
        var initial = MacSettingsStore.load(MacFXConfiguration.storageKey, fallback: MacFXConfiguration())
        let codes = MacFXCatalog.codes
        if MacPreferences.defaults.data(forKey: MacFXConfiguration.storageKey) == nil {
            initial.referenceCurrency = codes.contains("USD") ? "USD" : codes.first ?? "USD"
            if let legacy = MacPreferences.defaults.string(forKey: "v2_fx_preferred_source"), UUID(uuidString: legacy) != nil { initial.sourcePolicy = legacy }
        }
        let rawCache: MacFXQuoteCache = MacSettingsStore.load(Self.cacheKey, fallback: .init())
        monitor = MacFXMonitor(configuration: initial, cache: rawCache, providers: { adapter.providers() }, currencyCodes: { MacFXCatalog.codes }, persist: { value in
            if let data = try? JSONEncoder().encode(value) { MacPreferences.defaults.set(data, forKey: Self.cacheKey) }
        })
        query = MacFXQuerySession(currency: initial.referenceCurrency)
        history = MacFXHistoryService(data: MacPreferences.defaults.data(forKey: MacFXHistoryService.storageKey), legacyData: MacPreferences.defaults.data(forKey: MacFXHistoryService.legacyStorageKey), persist: { data in
            MacPreferences.defaults.set(data, forKey: MacFXHistoryService.storageKey)
        })
        catalogSignature = codes.joined(separator: ":")
        monitor.enabledCurrencyCodes = { MacFXCatalog.enabled }
        monitor.demandPairs = { [weak self] in self?.demands() ?? [] }
        observers.append(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).sink { [weak self] _ in
            Task { @MainActor in self?.reload() }
        })
        observers.append(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange).sink { [weak self] _ in Task { @MainActor in self?.monitor.contextChanged() } })
        observers.append(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).sink { [weak self] _ in Task { @MainActor in self?.monitor.contextChanged() } })
        observers.append(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in Task { @MainActor in await self?.monitor.checkDue() } })
    }
    var accountingContext: (policy:String,signature:String) {
        let policy = monitor.configuration.accountingSourcePolicy
        return (policy,accountingTransport.accountingSignature(policy:policy))
    }
    func accountingQuote(pair:MacFXPair,day:String,expectedSignature:String,cycle:String) async throws -> MacFXEvidenceQuote {
        let context = accountingContext
        guard context.signature == expectedSignature else { throw MacFXContractFailure.invalidEvidence }
        let result = try await accountingTransport.accountingQuote(pair:pair,day:day,policy:context.policy,cycle:cycle)
        guard accountingContext.signature == expectedSignature else { throw MacFXContractFailure.invalidEvidence }
        return result
    }
    func sourceLabel(_ id:String) -> String {
        if MacFXSourceScope.isSystem(id) { return "系统数据源" }
        if id == "identity" { return "同币种" }
        if id == "isolated-fixture" { return "隔离演示" }
        return MacFXService.sources.first { $0.id.uuidString == id }.map { "自定义 · " + $0.name } ?? "已保存来源"
    }
    func start() { monitor.start() }
    func update(_ change: (inout MacFXConfiguration) -> Void) {
        var next = monitor.configuration; change(&next); next = next.normalized()
        do {
            try MacSettingsStore.save(next, key: MacFXConfiguration.storageKey)
            settingsError = nil; monitor.configure(next)
        } catch { settingsError = error.localizedDescription }
    }
    /// Stage both encodings before committing either preference; never creates a pair or ledger.
    func addConverterCurrency(_ raw: String) throws {
        let code = try MacFXPair(base:raw,quote:raw).base
        var config = monitor.configuration
        if !config.converterCurrencies.contains(code) { config.converterCurrencies.append(code) }
        try commit(config,adding:[code])
    }
    func addWatchedPair(base: String, quote: String) throws {
        let pair = try MacFXPair(base:base,quote:quote)
        guard pair.base != pair.quote else { throw MacFXContractFailure.invalidPair }
        var config = monitor.configuration
        if !config.watchedPairs.contains(pair) { config.watchedPairs.append(pair) }
        try commit(config,adding:[pair.base,pair.quote])
    }
    func setReferenceCurrency(_ raw: String) throws {
        let code = try MacFXPair(base:raw,quote:raw).base
        var config = monitor.configuration; config.referenceCurrency = code
        try commit(config,adding:[code])
    }
    private func commit(_ config:MacFXConfiguration,adding additions:[String]) throws {
        var codes = MacFXCatalog.codes
        for code in additions where !codes.contains(code) { codes.append(code) }
        let directoryData = try JSONEncoder().encode(codes)
        let configurationData = try JSONEncoder().encode(config.normalized())
        MacPreferences.defaults.set(directoryData,forKey:"v2_currencies")
        MacPreferences.defaults.set(configurationData,forKey:MacFXConfiguration.storageKey)
        settingsError = nil; reload()
    }
    func reload() {
        let fingerprint = [MacFXConfiguration.storageKey, "v2_currencies", "v2_disabled_currencies", "v2_fx_sources", "v3_fx_source_revisions"].map { MacPreferences.defaults.data(forKey: $0) }
        guard fingerprint != preferencesFingerprint else { return }
        preferencesFingerprint = fingerprint
        let config = MacSettingsStore.load(MacFXConfiguration.storageKey, fallback: monitor.configuration)
        monitor.configure(config)
        let signature = MacFXCatalog.codes.joined(separator: ":")
        if catalogSignature != signature { catalogSignature = signature; monitor.contextChanged() }
    }
    private func demands() -> Set<MacFXPair> {
        var pairs = Set(monitor.configuration.converterCurrencies.compactMap { code -> MacFXPair? in
            guard code != query.inputCurrency else { return nil }; return try? MacFXPair(base: query.inputCurrency, quote: code)
        })
        if let menuPair, monitor.configuration.watchedPairs.contains(menuPair) { pairs.insert(menuPair) }
        if let base = query.settingsQueryBase { pairs.formUnion(MacFXCatalog.enabled.filter { $0 != base }.compactMap { try? MacFXPair(base: base, quote: $0) }) }
        return pairs
    }
}
