import Foundation
import CryptoKit
import CoreFoundation

/// Reuses FinTrack's provider definitions, parser, HTTPS validation and Keychain.
/// Raw monitoring values never go through financial six-place storage rounding.
@MainActor
final class MacFXProviderAdapter {
    private var payloads: [String: Task<Data, Error>] = [:]
    private var payloadOrder: [String] = []
    private(set) var networkRequestCount = 0
    var mock = false
    private let system = MacFXSystemSources()

    func providers() -> [MacFXProvider] {
        let configured = MacFXService.sources.filter(\.enabled).map { source -> MacFXProvider in
            let revision = self.revision(source)
            var calendar = MacFXDates.utc
            if let tz = source.dateTimeZoneID.flatMap(TimeZone.init(identifier:)) { calendar.timeZone = tz }
            return MacFXProvider(id: source.id.uuidString, revision: revision, name: "自定义 · " + source.name + (mock ? " · 隔离演示" : ""),
                                 supportsHistory: source.provider == "openExchangeRates" || (source.urlTemplate.contains("{date}") && !source.datePath.isEmpty),
                                 dayCalendar: calendar) { [weak self] pair, requested, purpose, cycle in
                guard let self else { throw MacFXNetworkFailure.unavailable }
                guard purpose != .accountingDay else { throw MacFXContractFailure.invalidEvidence }
                if self.mock { return self.mockQuote(pair: pair, sourceID: source.id.uuidString, revision: revision, requested: requested, purpose: purpose) }
                return try await self.fetch(source: source, revision: revision, pair: pair, requested: requested, purpose: purpose, cycle: cycle)
            }
        }
        let free = MacFXProvider(id: "free", revision: "currency-api-v1-utc-publication-day", name: mock ? "系统数据源 · 隔离演示" : "系统数据源", supportsHistory: true, dayCalendar: MacFXDates.utc) { [weak self] pair, requested, purpose, cycle in
            guard let self else { throw MacFXNetworkFailure.unavailable }
            guard purpose != .accountingDay else { throw MacFXContractFailure.invalidEvidence }
            if self.mock { return self.mockQuote(pair: pair, sourceID: "free", revision: "currency-api-v1-utc-publication-day", requested: requested, purpose: purpose) }
            return try await self.fetchFree(pair: pair, requested: requested, purpose: purpose, cycle: cycle)
        }
        let alternatives = system.providers().map { original in
            MacFXProvider(id:original.id,revision:original.revision,name:mock ? "系统数据源 · 隔离演示" : "系统数据源",supportsHistory:original.supportsHistory,dayCalendar:original.dayCalendar) { [weak self] pair,requested,purpose,cycle in
                guard let self, purpose != .accountingDay else { throw MacFXContractFailure.invalidEvidence }
                if self.mock { return self.mockQuote(pair:pair,sourceID:original.id,revision:original.revision,requested:requested,purpose:purpose) }
                return try await original.fetch(pair,requested,purpose,cycle)
            }
        }
        return configured + [free] + alternatives
    }
    private func revision(_ source: MacFXSource) -> String {
        let revisions: [String: String] = MacSettingsStore.load("v3_fx_source_revisions", fallback: [:])
        let definition = [source.urlTemplate, source.ratePath, source.datePath, source.provider ?? "", source.dateTimeZoneID ?? "", revisions[source.id.uuidString] ?? "legacy"]
        return SHA256.hash(data: Data(definition.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func payload(key: String, cycle: String, operation: @escaping () async throws -> Data) async throws -> Data {
        // Concurrent chart/live cycles must not evict one another's in-flight batch.
        let batchKey = cycle + "/" + key
        if let task = payloads[batchKey] { return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() } }
        networkRequestCount += 1
        let task = Task { try await operation() }; payloads[batchKey] = task; payloadOrder.append(batchKey)
        while payloadOrder.count > 128 { payloads.removeValue(forKey: payloadOrder.removeFirst()) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    private func tag(_ requested: MacFXRequestDate) -> String {
        if case .day(let tag) = requested { return tag }; return "latest"
    }
    private func fetch(source original: MacFXSource, revision: String, pair: MacFXPair,
                       requested: MacFXRequestDate, purpose: MacFXPurpose, cycle: String) async throws -> MacFXEvidenceQuote {
        var source = original
        let day = tag(requested)
        if day != "latest" && source.provider == "openExchangeRates" {
            source.urlTemplate = "https://openexchangerates.org/api/historical/{date}.json?app_id={key}"
        }
        try source.validate()
        let group: String
        if source.provider == "openExchangeRates" { group = "USD" }
        else if source.urlTemplate.contains("{quote") { group = pair.key }
        else if source.urlTemplate.contains("{base") { group = pair.base }
        else { group = "all" }
        let data = try await payload(key: source.id.uuidString + revision + day + group, cycle: cycle) {
            try await MacFXService.requestData(source, from: pair.base, to: pair.quote, date: Date(), dateTagOverride: day == "latest" ? MacFXDates.tag(Date()) : day)
        }
        let (rate, actualDay) = try MacFXService.decode(data, source: source, from: pair.base, to: pair.quote,
                                                      date: day == "latest" ? nil : day, preserveRawRate: true)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let time: MacFXQuoteTime
        if source.provider != nil, let timestamp = number(root?["timestamp"]) { time = .instant(Date(timeIntervalSince1970: timestamp), timeZoneID: "UTC") }
        else if let actualDay { time = .day(actualDay, timeZoneID: source.dateTimeZoneID ?? "unknown") }
        else { time = .unknown }
        let batch = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var legs: [MacFXQuoteLeg] = []
        if source.provider == "openExchangeRates", let rates = root?["rates"] as? [String: Any] {
            if pair.base != "USD", let denominator = number(rates[pair.base]), MacFXMath.validRate(1 / denominator) {
                legs.append(MacFXQuoteLeg(pair: try MacFXPair(base: pair.base, quote: "USD"), sourceID: source.id.uuidString, sourceRevision: revision, quoteTime: time, batchID: batch, unitRate: 1 / denominator))
            }
            if pair.quote != "USD", let numerator = number(rates[pair.quote]) {
                legs.append(MacFXQuoteLeg(pair: try MacFXPair(base: "USD", quote: pair.quote), sourceID: source.id.uuidString, sourceRevision: revision, quoteTime: time, batchID: batch, unitRate: numerator))
            }
        }
        return MacFXEvidenceQuote(identity: .init(purpose: purpose, pair: pair, sourceID: source.id.uuidString, sourceRevision: revision, requested: requested),
                                  unitRate: rate, quoteTime: time, retrievedAt: Date(), legs: legs)
    }
    private func fetchFree(pair:MacFXPair,requested:MacFXRequestDate,purpose:MacFXPurpose,cycle:String) async throws -> MacFXEvidenceQuote {
        let day = tag(requested), base = pair.base.lowercased(), quote = pair.quote.lowercased()
        let data = try await payload(key:"free/" + day + base,cycle:cycle) {
            var last:Error = MacFXNetworkFailure.unavailable
            var best:(Data,String)?
            // Mirrors can be at different publication days. A successful HTTP
            // response is not accepted until its date and requested rate validate.
            let pages = "https://{date}.currency-api.pages.dev/v1/currencies/{baseLower}.min.json"
            let cdn = "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@{date}/v1/currencies/{baseLower}.min.json"
            // Dated CDN releases avoid a rejected Pages request for every chart
            // point. Both mirrors still validate the exact publication day.
            for template in day == "latest" ? [pages, cdn] : [cdn, pages] {
                try Task.checkCancellation()
                do {
                    let value = try await MacFXService.requestData(MacFXSource(name:"系统数据源",urlTemplate:template),from:pair.base,to:pair.quote,date:Date(),keyOverride:"",dateTagOverride:day)
                    guard let root = try JSONSerialization.jsonObject(with:value) as? [String:Any], let actual = root["date"] as? String, MacFXDates.day(actual) != nil,
                          actual <= MacFXDates.tag(Date(),calendar:MacFXDates.utc), day == "latest" || actual == day,
                          let rates = root[base] as? [String:Any], self.number(rates[quote]) != nil else { throw MacFXNetworkFailure.invalid }
                    if best == nil || actual > best!.1 { best = (value,actual) }
                    if day != "latest" || actual == MacFXDates.tag(Date(),calendar:MacFXDates.utc) { break }
                } catch { try Task.checkCancellation(); last = error }
            }
            guard let best else { throw last }; return best.0
        }
        guard let root = try JSONSerialization.jsonObject(with:data) as? [String:Any], let actual = root["date"] as? String,
              let rates = root[base] as? [String:Any], let rate = number(rates[quote]) else { throw MacFXNetworkFailure.invalid }
        if day == "latest" { guard actual >= MacFXDates.tag(Date().addingTimeInterval(-14*86400),calendar:MacFXDates.utc) else { throw MacFXNetworkFailure.invalid } }
        return MacFXEvidenceQuote(identity:.init(purpose:purpose,pair:pair,sourceID:"free",sourceRevision:"currency-api-v1-utc-publication-day",requested:requested),unitRate:rate,quoteTime:.day(actual,timeZoneID:"UTC"),retrievedAt:Date(),legs:[])
    }
    func selectedProviders(_ policy:String) -> [MacFXProvider] {
        let all = providers(), builtIn = all.filter { MacFXSourceScope.isSystem($0.id) }
        return policy == "free" || policy == "auto" ? builtIn : all.filter { $0.id == policy } + builtIn
    }
    func accountingSignature(policy:String) -> String { policy + ":" + selectedProviders(policy).map { $0.id + ":" + $0.revision }.joined(separator:"|") }
    /// Separate accounting request path; monitoring provider closures continue
    /// refusing the accounting namespace and no monitor cache is consulted.
    func accountingQuote(pair:MacFXPair,day:String,policy:String,cycle:String = "accounting/" + UUID().uuidString) async throws -> MacFXEvidenceQuote {
        guard MacFXDates.day(day,calendar:.current) != nil, day <= MacFXDates.tag(Date(),calendar:.current) else { throw MacFXNetworkFailure.invalid }
        if pair.base == pair.quote { return MacFXEvidenceQuote(identity:.init(purpose:.accountingDay,pair:pair,sourceID:"identity",sourceRevision:"identity-v1",requested:.day(day)),unitRate:1,quoteTime:.day(day,timeZoneID:Calendar.current.timeZone.identifier),retrievedAt:Date(),legs:[]) }
        for provider in selectedProviders(policy) {
            guard provider.supportsHistory || day == MacFXDates.tag(Date(),calendar:provider.dayCalendar) else { continue }
            do {
                let result:MacFXEvidenceQuote
                if mock {
                    let value = mockQuote(pair:pair,sourceID:provider.id,revision:provider.revision,requested:.day(day),purpose:.accountingDay)
                    result = MacFXEvidenceQuote(identity:value.identity,unitRate:value.unitRate,quoteTime:.day(day,timeZoneID:"UTC"),retrievedAt:value.retrievedAt,legs:value.legs)
                } else if provider.id == "free" { result = try await fetchFree(pair:pair,requested:.day(day),purpose:.accountingDay,cycle:cycle) }
                else if provider.id.hasPrefix("system.") { result = try await system.quote(kind:String(provider.id.dropFirst(7)),pair:pair,requested:.day(day),purpose:.accountingDay,cycle:cycle) }
                else if let source = MacFXService.sources.first(where:{$0.id.uuidString == provider.id && $0.enabled}) {
                    result = try await fetch(source:source,revision:provider.revision,pair:pair,requested:.day(day),purpose:.accountingDay,cycle:cycle)
                } else { continue }
                let actual:String?
                switch result.quoteTime {
                case .day(let d,_): actual = d
                case .instant(let d,_): actual = d <= Date().addingTimeInterval(300) ? MacFXDates.tag(d,calendar:provider.dayCalendar) : nil
                case .unknown: actual = nil
                }
                guard actual == day, result.identity.purpose == .accountingDay, result.identity.pair == pair, result.identity.requested == .day(day), MacFXMath.validRate(result.unitRate) else { throw MacFXContractFailure.invalidEvidence }
                return result
            } catch { continue }
        }
        throw MacSettingsFailure.invalid("暂未取得该交易日的有效参考汇率，请稍后重试或手动核对输入")
    }
    func systemQuote(pair:MacFXPair) async throws -> MacFXEvidenceQuote {
        let cycle = "system-check/" + UUID().uuidString
        for provider in selectedProviders("free") { if let value = try? await provider.fetch(pair,.latest,.monitorCurrent,cycle), MacFXQuoteCache.valid(value) { return value } }
        throw MacFXNetworkFailure.unavailable
    }
    private func number(_ raw: Any?) -> Double? {
        let value: Double?
        if let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { value = n.doubleValue }
        else if let s = raw as? String { value = Double(s) } else { value = nil }
        guard let value, MacFXMath.validRate(value) else { return nil }; return value
    }
    private func mockQuote(pair: MacFXPair, sourceID: String, revision: String, requested: MacFXRequestDate, purpose: MacFXPurpose) -> MacFXEvidenceQuote {
        let rates = ["USD":1.0,"CNY":7.2,"EUR":0.92,"RUB":98,"JPY":150,"GBP":0.77,"CHF":0.88,"HKD":7.78,"TRY":34.2]
        if purpose == .monitorHistory, case .day(let day) = requested, let date = MacFXDates.day(day) {
            let variation = 1 + sin(date.timeIntervalSince1970 / 86400 / 5) * 0.012
            return MacFXEvidenceQuote(identity: .init(purpose: purpose, pair: pair, sourceID: sourceID, sourceRevision: revision, requested: requested),
                unitRate: (rates[pair.quote] ?? 1) / (rates[pair.base] ?? 1) * variation, quoteTime: .day(day, timeZoneID: "UTC"), retrievedAt: Date(), legs: [])
        }
        let clock: Date
        if case .day(let day) = requested { clock = (MacFXDates.day(day) ?? Date()).addingTimeInterval(86399) } else { clock = Date() }
        return MacFXEvidenceQuote(identity: .init(purpose: purpose, pair: pair, sourceID: sourceID, sourceRevision: revision, requested: requested),
                                  unitRate: (rates[pair.quote] ?? 1) / (rates[pair.base] ?? 1), quoteTime: .instant(clock, timeZoneID: "UTC"), retrievedAt: Date(), legs: [])
    }
}
