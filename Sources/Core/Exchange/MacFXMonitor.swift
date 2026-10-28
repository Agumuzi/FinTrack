import Foundation
import Combine

nonisolated struct MacFXProvider {
    let id: String
    let revision: String
    let name: String
    let supportsHistory: Bool
    let dayCalendar: Calendar
    var rangeAvailable = false
    var rangeFetch: (@Sendable (MacFXPair, String, String) async throws -> [MacFXHistoryPoint])? = nil
    let fetch: (MacFXPair, MacFXRequestDate, MacFXPurpose, String) async throws -> MacFXEvidenceQuote
}

nonisolated enum MacFXNetworkFailure: LocalizedError {
    case http(Int, retryAfter: TimeInterval?), unavailable, invalid, cooling
    var errorDescription: String? {
        switch self {
        case .http(401, _): "访问未获授权（401），请检查 API Key"
        case .http(429, _): "数据源限流（429），稍后重试"
        case .http(let code, _): "数据源返回 HTTP \(code)"
        case .unavailable: "网络不可用或请求超时"
        case .invalid: "数据源没有返回可核验的报价"
        case .cooling: "数据源冷却中，请稍后更新"
        }
    }
}

/// App-level monitoring only. Dependencies expose no financial models or writes.
@MainActor
final class MacFXMonitor: ObservableObject {
    @Published private(set) var configuration: MacFXConfiguration
    @Published private(set) var cache: MacFXQuoteCache
    @Published private(set) var errors: [MacFXPair: String] = [:]
    @Published private(set) var warnings: [MacFXPair: String] = [:]
    @Published private(set) var busy = false
    @Published private(set) var status = "等待更新"
    @Published private(set) var revision = 0
    private(set) var quoteRequestCount = 0
    var providerList: () -> [MacFXProvider]
    var currencyCodes: () -> [String]
    var enabledCurrencyCodes: () -> [String]
    var demandPairs: () -> Set<MacFXPair> = { [] }
    var persist: (MacFXQuoteCache) -> Void
    var now: () -> Date
    private var generation = 0
    private var sourceSignature = ""
    private var refreshTask: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var pending: Set<MacFXPair> = []
    private var cooldown: [String: Date] = [:]
    private var baselineAttempts: [MacFXRequestIdentity: Date] = [:]
    private var lastAttempt: Date?
    private var cachedPairs: Set<MacFXPair>

    init(configuration: MacFXConfiguration, cache: MacFXQuoteCache = .init(),
         providers: @escaping () -> [MacFXProvider], currencyCodes: @escaping () -> [String],
         now: @escaping () -> Date = Date.init, persist: @escaping (MacFXQuoteCache) -> Void = { _ in }) {
        let restored = (try? cache.validated(now: now())) ?? MacFXQuoteCache()
        self.configuration = configuration.normalized(); self.cache = restored
        providerList = providers; self.currencyCodes = currencyCodes; enabledCurrencyCodes = currencyCodes; self.now = now; self.persist = persist
        cachedPairs = Set(restored.snapshots.map(\.pair))
        sourceSignature = providers().map { $0.id + $0.revision }.joined(separator: ":")
    }
    deinit { timer?.cancel(); refreshTask?.cancel() }

    func configure(_ config: MacFXConfiguration) {
        let next = config.normalized(), signature = providerList().map { $0.id + $0.revision }.joined(separator: ":")
        guard next != configuration || signature != sourceSignature else { return }
        let requestChanged = next.sourcePolicy != configuration.sourcePolicy || next.automatic != configuration.automatic || signature != sourceSignature
        let scheduleChanged = next.automatic != configuration.automatic || next.intervalMinutes != configuration.intervalMinutes || signature != sourceSignature
        if requestChanged { generation += 1; errors = [:]; warnings = [:] }
        sourceSignature = signature; configuration = next; revision += 1
        if scheduleChanged { restartSchedule() }
    }
    func contextChanged() { generation += 1; revision += 1 }
    func start() { restartSchedule() }
    private func restartSchedule() {
        timer?.cancel(); timer = nil
        guard configuration.automatic else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self.map({ Double($0.configuration.intervalMinutes) * 60 }) else { return }
                let delay = self?.lastAttempt.map { max(1, interval - (self?.now().timeIntervalSince($0) ?? 0)) } ?? interval
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard !Task.isCancelled, let self else { return }
                await self.checkDue()
            }
        }
    }
    func checkDue() async {
        guard configuration.automatic, lastAttempt.map({ now().timeIntervalSince($0) >= Double(configuration.intervalMinutes) * 60 }) ?? true else { return }
        await refresh(reason: .scheduled)
    }
    func pageOpened() async {
        guard configuration.refreshOnOpen else { return }
        let maxAge = Double(configuration.openMaxAgeMinutes) * 60
        let missing = requiredPairs(manual: false).filter { pair in quote(pair).map { now().timeIntervalSince($0.retrievedAt) >= maxAge } ?? true }
        if !missing.isEmpty { await refresh(reason: .pageOpen, extraPairs: Set(missing)) }
    }
    private func providers(for config: MacFXConfiguration) -> [MacFXProvider] {
        let all = providerList()
        switch config.sourcePolicy {
        case "auto": return all
        case "free": return all.filter { MacFXSourceScope.isSystem($0.id) }
        default:
            return all.filter { $0.id == config.sourcePolicy } + all.filter { MacFXSourceScope.isSystem($0.id) }
        }
    }
    func sourceName(_ quote: MacFXEvidenceQuote) -> String { providerList().first { $0.id == quote.identity.sourceID }?.name ?? "旧来源缓存" }
    func historyProvider(_ pair: MacFXPair) -> MacFXProvider? {
        // Chart history is a separate daily reference, never a live-price baseline.
        let all = providerList().filter { MacFXSourceScope.isSystem($0.id) && $0.supportsHistory }
        return all.first { $0.rangeAvailable && MacFXRangeClient.supports(pair, source: $0.id) } ?? all.first
    }
    func supportsRange(_ request: MacFXHistoryRequest) -> Bool {
        providerList().contains { $0.id == request.sourceID && $0.revision == request.revision && $0.rangeAvailable && MacFXRangeClient.supports(request.pair, source: $0.id) }
    }
    func historyRange(_ request: MacFXHistoryRequest, start: String, end: String) async throws -> [MacFXHistoryPoint] {
        guard let source = providerList().first(where: { $0.id == request.sourceID && $0.revision == request.revision }),
              MacFXRangeClient.supports(request.pair, source: source.id),
              end <= MacFXDates.tag(now(), calendar: source.dayCalendar) else { throw MacFXContractFailure.invalidEvidence }
        let key = source.id + source.revision
        if let until = cooldown[key], now() < until { throw MacFXNetworkFailure.cooling }
        do {
            guard let rangeFetch = source.rangeFetch else { throw MacFXContractFailure.unavailable }
            return try await rangeFetch(request.pair, start, end)
        } catch {
            if case MacFXNetworkFailure.http(let code, let retry) = error, code == 429 || code == 401 {
                cooldown[key] = now().addingTimeInterval(code == 401 ? 1800 : max(1, retry ?? 900))
            }
            throw error
        }
    }
    /// Shares source cooldown with live monitoring, but never accepts into its cache.
    func historyPoint(pair: MacFXPair, day: String, sourceID: String, revision: String, cycle: String) async throws -> MacFXHistoryPoint {
        guard let source = providerList().first(where: { $0.id == sourceID && $0.revision == revision && $0.supportsHistory }) else { throw MacFXContractFailure.unavailable }
        guard MacFXDates.day(day) != nil, day <= MacFXDates.tag(now(), calendar: source.dayCalendar) else { throw MacFXContractFailure.invalidEvidence }
        let value = try await fetch(source, pair: pair, requested: .day(day), purpose: .monitorHistory, cycle: cycle)
        guard value.identity == MacFXRequestIdentity(purpose: .monitorHistory, pair: pair, sourceID: sourceID, sourceRevision: revision, requested: .day(day)),
              MacFXMath.validRate(value.unitRate), value.retrievedAt <= now().addingTimeInterval(300) else { throw MacFXContractFailure.invalidEvidence }
        switch value.quoteTime {
        case .day(let actual, _): guard actual == day else { throw MacFXContractFailure.invalidEvidence }
        case .instant(let date, let zone):
            guard TimeZone(identifier: zone) != nil, date <= now().addingTimeInterval(300), MacFXDates.tag(date, calendar: source.dayCalendar) == day else { throw MacFXContractFailure.invalidEvidence }
        case .unknown: throw MacFXContractFailure.invalidEvidence
        }
        return MacFXHistoryPoint(day: day, unitRate: value.unitRate, quoteTime: value.quoteTime, retrievedAt: value.retrievedAt)
    }
    private func fetch(_ source: MacFXProvider, pair: MacFXPair, requested: MacFXRequestDate, purpose: MacFXPurpose, cycle: String) async throws -> MacFXEvidenceQuote {
        let key = source.id + source.revision
        if let until = cooldown[key], now() < until { throw MacFXNetworkFailure.cooling }
        do {
            quoteRequestCount += 1
            return try await source.fetch(pair, requested, purpose, cycle)
        } catch {
            if case MacFXNetworkFailure.http(let code, let retry) = error {
                if code == 401 { cooldown[key] = now().addingTimeInterval(1800) }
                if code == 429 { cooldown[key] = now().addingTimeInterval(max(1, retry ?? 900)) }
            }
            throw error
        }
    }
    func quote(_ pair: MacFXPair) -> MacFXEvidenceQuote? {
        guard currencyCodes().contains(pair.base), currencyCodes().contains(pair.quote), let value = cache.snapshot(pair)?.current,
              providers(for: configuration).contains(where: { $0.id == value.identity.sourceID && $0.revision == value.identity.sourceRevision }) else { return nil }
        return value
    }
    var quotes: [MacFXEvidenceQuote] { cache.snapshots.compactMap { quote($0.pair) } }
    /// Selection conversion is a quote consumer, never an accounting write or a forced
    /// refresh of the entire directory. Keep its source/revision checks identical to monitoring.
    func selectionRoute(from: String, to: String, maximumAge: TimeInterval = .greatestFiniteMagnitude) -> MacFXMath.Conversion? {
        let active = providers(for: configuration)
        let values = cache.snapshots.map(\.current).filter { value in
            now().timeIntervalSince(value.retrievedAt) <= maximumAge &&
            active.contains { $0.id == value.identity.sourceID && $0.revision == value.identity.sourceRevision }
        }
        return MacFXMath.resolve(from: from, to: to, quotes: values)
    }
    func loadSelectionRoute(from: String, to: String) async -> MacFXMath.Conversion? {
        if let route = selectionRoute(from: from, to: to) { return route }
        if let task = refreshTask {
            await task.value
            if let route = selectionRoute(from: from, to: to) { return route }
        }
        guard !Task.isCancelled, let pair = try? MacFXPair(base: from, quote: to) else { return nil }
        let expected = generation, active = providers(for: configuration), cycle = "selection/" + UUID().uuidString
        for source in active {
            guard !Task.isCancelled else { return nil }
            do {
                let value = try await fetch(source, pair: pair, requested: .latest, purpose: .monitorCurrent, cycle: cycle)
                guard !Task.isCancelled, expected == generation else { return nil }
                guard value.identity == MacFXRequestIdentity(purpose: .monitorCurrent, pair: pair, sourceID: source.id, sourceRevision: source.revision, requested: .latest), MacFXQuoteCache.valid(value, now: now()) else { continue }
                var next = cache
                guard next.accept(value, now: now()) else { continue }
                cache = next; revision += 1; persist(cache)
                return selectionRoute(from: from, to: to)
            } catch { continue }
        }
        return nil
    }

    func isCached(_ pair: MacFXPair) -> Bool { cachedPairs.contains(pair) || errors[pair] != nil }
    func comparison(_ pair: MacFXPair, calendar: Calendar = .current) -> MacFXComparison {
        _ = revision
        return .evaluate(current: quote(pair), previous: cache.snapshot(pair)?.previous, history: cache.observations,
                         automatic: configuration.automatic, now: now(), calendar: calendar)
    }
    private func requiredPairs(manual: Bool) -> Set<MacFXPair> {
        let codes = Set(currencyCodes())
        var pairs = Set(configuration.watchedPairs.filter { codes.contains($0.base) && codes.contains($0.quote) })
        pairs.formUnion(demandPairs())
        pairs.formUnion((manual ? currencyCodes() : enabledCurrencyCodes()).filter { $0 != configuration.referenceCurrency }.compactMap { try? MacFXPair(base: configuration.referenceCurrency, quote: $0) })
        return pairs.filter { $0.base != $0.quote && codes.contains($0.base) && codes.contains($0.quote) }
    }

    func refresh(reason: MacFXRefreshReason, extraPairs: Set<MacFXPair> = []) async {
        let manual: Bool
        switch reason {
        case .scheduled: guard configuration.automatic else { return }; manual = false
        case .pageOpen: guard configuration.refreshOnOpen else { return }; manual = false
        case .manual: manual = true
        }
        pending.formUnion(requiredPairs(manual: manual).union(extraPairs))
        if let task = refreshTask {
            let requestedGeneration = generation
            await task.value
            if requestedGeneration == generation, pending.isEmpty { return }
            // An old generation cannot satisfy a request made after reconfiguration.
            if !pending.isEmpty { lastAttempt = nil; await refresh(reason: reason, extraPairs: extraPairs) }
            return
        }
        if let lastAttempt, now().timeIntervalSince(lastAttempt) < 2 {
            pending = []; status = "更新冷却中，请稍后重试"; return
        }
        lastAttempt = now(); busy = true
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh()
            self.busy = false; self.refreshTask = nil
        }
        refreshTask = task
        await task.value
    }
    private func performRefresh() async {
        let cycle = UUID().uuidString, requestGeneration = generation, capturedConfig = configuration
        let activeProviders = providers(for: capturedConfig), clock = now(), calendar = Calendar.current
        var attempted: Set<MacFXPair> = [], successes = 0
        var nextCache = cache
        var baselines: [(MacFXPair, MacFXEvidenceQuote)] = []
        var accepted: [MacFXEvidenceQuote] = []
        while requestGeneration == generation, let pair = pending.sorted(by: { $0.key < $1.key }).first {
            pending.remove(pair)
            guard attempted.insert(pair).inserted else { continue }
            var failures: [String] = [], returned: MacFXEvidenceQuote?
            for source in activeProviders {
                if let until = cooldown[source.id + source.revision], clock < until { if !MacFXSourceScope.isSystem(source.id) { failures.append(source.name) }; continue }
                do {
                    let value = try await fetch(source, pair: pair, requested: .latest, purpose: .monitorCurrent, cycle: cycle)
                    guard value.identity.purpose == .monitorCurrent, value.identity.pair == pair,
                          value.identity.sourceID == source.id, value.identity.sourceRevision == source.revision,
                          MacFXQuoteCache.valid(value, now: now()) else { throw MacFXNetworkFailure.invalid }
                    returned = value; break
                } catch {
                    if !MacFXSourceScope.isSystem(source.id) { failures.append(source.name) }
                    if case MacFXNetworkFailure.http(let code, let retry) = error {
                        if code == 401 { cooldown[source.id + source.revision] = now().addingTimeInterval(1800) }
                        if code == 429 { cooldown[source.id + source.revision] = now().addingTimeInterval(max(1, retry ?? 900)) }
                    }
                }
            }
            guard requestGeneration == generation else { pending.insert(pair); break }
            if let returned {
                if nextCache.accept(returned, now: now(), calendar: calendar) {
                    accepted.append(returned)
                    successes += 1; cachedPairs.remove(pair); errors[pair] = nil
                    warnings[pair] = failures.isEmpty ? nil : "自定义来源暂不可用，已使用系统数据源"
                    if !capturedConfig.automatic { baselines.append((pair, returned)) }
                } else { warnings[pair] = "旧报价未覆盖较新的有效值" }
            } else { errors[pair] = "暂未取得有效汇率，请检查网络或稍后更新" }
        }
        if requestGeneration == generation {
            // Publish the complete current-rate batch before optional daily baselines.
            var merged = cache
            for value in accepted { _ = merged.accept(value, now: now(), calendar: calendar) }
            cache = merged
            revision += 1; status = successes > 0 ? "已更新 \(successes) 个汇率" : "未取得新报价，保留有效缓存"
            persist(cache)
            for (pair, current) in baselines {
                guard requestGeneration == generation else { break }
                await backfill(pair: pair, current: current, providers: activeProviders, cycle: cycle, requestGeneration: requestGeneration, clock: clock, calendar: calendar)
            }
        }
    }
    private func backfill(pair: MacFXPair, current: MacFXEvidenceQuote, providers: [MacFXProvider], cycle: String,
                          requestGeneration: Int, clock: Date, calendar: Calendar) async {
        guard let source = providers.first(where: { $0.id == current.identity.sourceID && $0.revision == current.identity.sourceRevision }), source.supportsHistory,
              let currentTag = MacFXDates.publicationDay(current.quoteTime, calendar: source.dayCalendar),
              let currentDay = MacFXDates.day(currentTag, calendar: source.dayCalendar) else { return }
        if cache.observations.contains(where: { MacFXComparison.sameDefinition(current, $0) && MacFXComparison.usable($0) && MacFXComparison.newer(current, than: $0) }) { return }
        // Instant quotes retain the existing local previous-day contract. Daily
        // sources query relative to their actual latest publication, not today.
        let daily: Bool = { if case .day = current.quoteTime { return true }; return false }()
        for offset in 1...(daily ? 10 : 1) {
            guard generation == requestGeneration,
                  let previousDay = source.dayCalendar.date(byAdding: .day, value: -offset, to: currentDay) else { return }
            let tag = MacFXDates.tag(previousDay, calendar: source.dayCalendar)
            let identity = MacFXRequestIdentity(purpose: .monitorPreviousDay, pair: pair, sourceID: source.id, sourceRevision: source.revision, requested: .day(tag))
            if let last = baselineAttempts[identity], clock.timeIntervalSince(last) < 300 { continue }
            if let until = cooldown[source.id + source.revision], clock < until { return }
            baselineAttempts[identity] = clock
            do {
                let value = try await fetch(source, pair: pair, requested: .day(tag), purpose: .monitorPreviousDay, cycle: cycle)
                guard generation == requestGeneration, value.identity == identity,
                      MacFXDates.publicationDay(value.quoteTime, calendar: source.dayCalendar) == tag,
                      MacFXComparison.sameDefinition(current, value), MacFXComparison.newer(current, than: value) else { continue }
                var updated = cache
                if updated.accept(value, now: now(), calendar: calendar) { cache = updated; revision += 1; persist(cache) }
                return
            } catch {
                if case MacFXNetworkFailure.http(429, let retry) = error { cooldown[source.id + source.revision] = now().addingTimeInterval(max(1, retry ?? 900)); return }
                if case MacFXNetworkFailure.unavailable = error { return }
                // A non-publication day can be skipped, never filled with a copy.
            }
        }
    }
}
