import Foundation
import Security
import CoreFoundation

struct MacFXSource: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name = ""
    var urlTemplate = ""
    var ratePath = "rates.{quote}"
    var datePath = ""
    var enabled = true
    var imageData: Data? = nil
    var provider: String? = nil
    var dateTimeZoneID: String? = nil
    func resolved(from: String, to: String, date: String, key: String = "") throws -> URL {
        let from = try MacCurrency.code(from), to = try MacCurrency.code(to)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        var text = urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        for (token, value) in ["base": from, "quote": to, "baseLower": from.lowercased(), "quoteLower": to.lowercased(), "date": date, "key": key] {
            text = text.replacingOccurrences(of: "{" + token + "}", with: value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }
        guard !text.contains("{"), !text.contains("}"), let url = URL(string: text), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil, url.port == nil || url.port == 443
        else { throw MacSettingsFailure.invalid("URL 必须是无嵌入凭证的 HTTPS 地址，且占位符有效") }
        return url
    }
    func validate() throws {
        if let imageData { try MacImageAssets.validatePreparedPNG(imageData) }
        if let dateTimeZoneID, TimeZone(identifier: dateTimeZoneID) == nil { throw MacSettingsFailure.invalid("报价日时区无效") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80, !ratePath.isEmpty,
              !urlTemplate.contains("\n"), ratePath.count <= 256 else { throw MacSettingsFailure.invalid("请填写名称、HTTPS URL 模板和 JSON 路径") }
        _ = try resolved(from: "USD", to: "CNY", date: "2026-10-14")
        guard provider == nil || ["twelveData", "openExchangeRates"].contains(provider!) else {
            throw MacSettingsFailure.invalid("未知的汇率模板")
        }
        // Keep secrets in Keychain; never embed them in the persisted URL template.
        let resolved = urlTemplate.replacingOccurrences(of: "{key}", with: "FINTRACK_SECRET_PLACEHOLDER")
        if let components = URLComponents(string: resolved) {
            for item in components.queryItems ?? [] where ["key", "api_key", "apikey", "access_key", "app_id", "token"].contains(item.name.lowercased()) {
                guard item.value == "FINTRACK_SECRET_PLACEHOLDER" else { throw MacSettingsFailure.invalid("密钥参数请使用 {key}，并在 API Key 字段填写密钥") }
            }
        }
    }
}

enum MacFXTemplate: String, CaseIterable {
    case twelveData, openExchangeRates, custom
    var title: String { switch self { case .twelveData: "Twelve Data"; case .openExchangeRates: "Open Exchange Rates"; case .custom: "自定义 API" } }
    func source(id: UUID = UUID()) -> MacFXSource {
        switch self {
        case .twelveData:
            return MacFXSource(id: id, name: title, urlTemplate: "https://api.twelvedata.com/exchange_rate?symbol={base}/{quote}&apikey={key}", ratePath: "rate", provider: rawValue)
        case .openExchangeRates:
            // USD-based payload works on the free plan; decode derives any cross rate.
            return MacFXSource(id: id, name: title, urlTemplate: "https://openexchangerates.org/api/latest.json?app_id={key}", ratePath: "rates.{quote}", provider: rawValue)
        case .custom: return MacFXSource(id: id)
        }
    }
}

struct MacFXQuote: Codable, Identifiable, Sendable {
    var id = UUID()
    var from: String
    var to: String
    var rate: Double
    var source: String
    var sourceID: UUID?
    var date: String?
    var retrievedAt: Date
    var stale: Bool { Date().timeIntervalSince(retrievedAt) > 86400 }
}

enum MacFXSecrets {
    private static var testValues: [String: String] = [:]
    private static var sessionValues: [UUID: String] = [:]
    private static var refused = Set<UUID>()
    private static func revise(_ id: UUID) {
        var values: [String: String] = MacSettingsStore.load("v3_fx_source_revisions", fallback: [:])
        values[id.uuidString] = UUID().uuidString
        try? MacSettingsStore.save(values, key: "v3_fx_source_revisions")
    }
    static func read(_ id: UUID, retryAuthorization: Bool = false) throws -> String {
        if retryAuthorization { refused.remove(id); sessionValues[id] = nil }
        if MacPreferences.isTesting { return testValues[id.uuidString] ?? "" }
        guard !refused.contains(id) else { throw MacSettingsFailure.invalid("钥匙串需要授权；请打开对应数据源设置后重试。") }
        if let value = sessionValues[id] { return value }
        let (status, value) = try MacFXKeychainClient.perform("read", id:id, authorize:retryAuthorization)
        if status == errSecItemNotFound { sessionValues[id] = ""; return "" }
        if status == errSecUserCanceled || status == errSecAuthFailed { refused.insert(id) }
        if status == errSecUserCanceled || status == errSecAuthFailed || status == errSecInteractionNotAllowed {
            throw MacSettingsFailure.invalid("钥匙串需要授权或解锁；请打开对应数据源设置后重试。后台更新不会弹出密码窗口。")
        }
        guard status == errSecSuccess, let value else { throw MacSettingsFailure.invalid("无法读取系统钥匙串中的 API Key") }
        sessionValues[id] = value
        return value
    }
    static func save(_ key: String, id: UUID) throws {
        if MacPreferences.isTesting { testValues[id.uuidString] = key; revise(id); return }
        let (status, _) = try MacFXKeychainClient.perform(key.isEmpty ? "delete" : "save", id:id, value:key, authorize:true)
        guard status == errSecSuccess || (key.isEmpty && status == errSecItemNotFound) else {
            throw MacSettingsFailure.invalid(key.isEmpty ? "无法移除 API Key" : "API Key 未能保存到钥匙串")
        }
        sessionValues[id] = key; refused.remove(id)
        revise(id)
    }
    private static var versions: [UUID: Int] = [:]
    static func readAsync(_ id: UUID, retryAuthorization: Bool = false) async throws -> String {
        if MacPreferences.isTesting { return testValues[id.uuidString] ?? "" }
        if retryAuthorization { refused.remove(id);sessionValues[id]=nil }
        guard !refused.contains(id) else {throw MacSettingsFailure.invalid("钥匙串需要授权，请在数据源设置中重试。")}
        if let value=sessionValues[id] {return value}
        let generation=versions[id,default:0]
        let (status,value)=try await MacFXKeychainClient.performAsync("read",id:id,authorize:retryAuthorization)
        guard versions[id,default:0] == generation else {throw MacSettingsFailure.invalid("密钥配置已变化，请重试。")}
        if status == errSecItemNotFound {sessionValues[id]="";return ""}
        if status == errSecUserCanceled || status == errSecAuthFailed {refused.insert(id)}
        guard status == errSecSuccess,let value else {throw MacSettingsFailure.invalid("钥匙串需要授权或解锁，请在数据源设置中重试。")}
        sessionValues[id]=value;return value
    }
    static func saveAsync(_ key: String, id: UUID) async throws {
        if MacPreferences.isTesting {try save(key,id:id);return}
        versions[id,default:0] += 1;let generation=versions[id]!
        let (status,_)=try await MacFXKeychainClient.performAsync(key.isEmpty ? "delete":"save",id:id,value:key,authorize:true)
        guard status == errSecSuccess || (key.isEmpty && status == errSecItemNotFound) else {throw MacSettingsFailure.invalid("密钥未能保存，请重试。")}
        if versions[id] == generation {sessionValues[id]=key;refused.remove(id);revise(id)}
    }

}

/// Reject redirects so an API key cannot be forwarded to another endpoint.
final class MacNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
enum MacFXService {
    static var testingProtocolClasses: [AnyClass]? {
        didSet { transport.invalidate(); transport = MacFXHTTP(protocols: MacPreferences.isTesting ? testingProtocolClasses : nil) }
    }
    private static var transport = MacFXHTTP()
    static func retryAfter(_ value: String?, now: Date = Date()) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite { return max(0, seconds) }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
    static var sources: [MacFXSource] {
        let values: [MacFXSource] = MacSettingsStore.load("v2_fx_sources", fallback: [])
        let preferred = MacPreferences.defaults.string(forKey: "v2_fx_preferred_source")
        return values.sorted { $0.id.uuidString == preferred && $1.id.uuidString != preferred }
    }
    static var quotes: [MacFXQuote] { MacSettingsStore.load("v2_fx_quotes", fallback: []) }
    static func persist(_ quote: MacFXQuote) throws {
        var list = quotes; list.append(quote)
        try MacSettingsStore.save(Array(list.suffix(2000)), key: "v2_fx_quotes")
    }
    static func save(_ source: MacFXSource, key: String) throws {
        try source.validate()
        let previous = try MacFXSecrets.read(source.id)
        try MacFXSecrets.save(key, id: source.id)
        var list = sources; if let index = list.firstIndex(where: { $0.id == source.id }) { list[index] = source } else { list.append(source) }
        do { try MacSettingsStore.save(list, key: "v2_fx_sources") }
        catch { try? MacFXSecrets.save(previous, id: source.id); throw error }
    }
    static func remove(_ source: MacFXSource) throws {
        try MacFXSecrets.save("", id: source.id)
        try MacSettingsStore.save(sources.filter { $0.id != source.id }, key: "v2_fx_sources")
    }
    static func saveAsync(_ source: MacFXSource, key: String) async throws {
        try source.validate()
        let previous=try await MacFXSecrets.readAsync(source.id)
        try await MacFXSecrets.saveAsync(key,id:source.id)
        var list=sources
        if let index=list.firstIndex(where:{$0.id == source.id}) {list[index]=source}else{list.append(source)}
        do {try MacSettingsStore.save(list,key:"v2_fx_sources")}
        catch {try? await MacFXSecrets.saveAsync(previous,id:source.id);throw error}
    }
    static func removeAsync(_ source: MacFXSource) async throws {
        try await MacFXSecrets.saveAsync("",id:source.id)
        try MacSettingsStore.save(sources.filter{$0.id != source.id},key:"v2_fx_sources")
    }
    nonisolated static func value(_ root: Any, path: String) -> Any? {
        var node: Any? = root
        for part in path.split(separator: ".") {
            if let dict = node as? [String: Any] { node = dict[String(part)] }
            else if let array = node as? [Any], let i = Int(part), array.indices.contains(i) { node = array[i] }
            else { return nil }
        }
        return node
    }
    static func decode(_ data: Data, source: MacFXSource, from: String, to: String, date: String?, preserveRawRate: Bool = false) throws -> (Double, String?) {
        let value = try rawDecoded(data, source: source, from: from, to: to, date: date, preserveRawRate: preserveRawRate)
        return (preserveRawRate ? value.0 : try MacCurrency.rate(String(value.0)), value.1)
    }
    nonisolated static func rawDecoded(_ data: Data, source: MacFXSource, from: String, to: String, date: String?, preserveRawRate: Bool = true) throws -> (Double, String?) {
        let root = try JSONSerialization.jsonObject(with: data)
        if let provider = source.provider {
            guard let root = root as? [String: Any], root["status"] as? String != "error", root["error"] == nil else {
                throw MacSettingsFailure.invalid("服务未返回有效汇率，请检查 API Key 与用量")
            }
            let rawRate: Double
            if provider == "openExchangeRates" {
                guard root["base"] as? String == "USD", let rates = root["rates"] as? [String: Any],
                      let numerator = positiveNumber(rates[to]), let denominator = positiveNumber(rates[from]) else {
                    throw MacSettingsFailure.invalid("数据源未返回该货币对")
                }
                rawRate = numerator / denominator
            } else {
                guard let rate = positiveNumber(root["rate"]), root["symbol"] as? String == from + "/" + to else {
                    throw MacSettingsFailure.invalid("数据源未返回所请求的货币对")
                }
                rawRate = rate
            }
            guard let timestamp = positiveNumber(root["timestamp"]), timestamp <= Date().timeIntervalSince1970 + 300 else {
                throw MacSettingsFailure.invalid("报价时间无效")
            }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"
            let actualDate = formatter.string(from: Date(timeIntervalSince1970: timestamp))
            if let date, date != actualDate { throw MacSettingsFailure.invalid("报价日期与历史记账日期不符") }
            guard rawRate.isFinite, rawRate > 0 else { throw MacFXNetworkFailure.invalid }
            return (rawRate, actualDate)
        }
        let path = source.ratePath.replacingOccurrences(of: "{base}", with: from).replacingOccurrences(of: "{quote}", with: to)
            .replacingOccurrences(of: "{baseLower}", with: from.lowercased()).replacingOccurrences(of: "{quoteLower}", with: to.lowercased())
        let raw = value(root, path: path)
        let rate: Double?
        if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { rate = number.doubleValue }
        else if let string = raw as? String { rate = Double(string) }
        else { rate = nil }
        guard let rate, rate.isFinite, rate > 0, (preserveRawRate || rate <= 1_000_000_000) else { throw MacSettingsFailure.invalid("JSON 路径未返回有效的正数汇率") }
        let actualDate = source.datePath.isEmpty ? nil : value(root, path: source.datePath) as? String
        if !source.datePath.isEmpty {
            var calendar = Calendar.current
            if preserveRawRate {
                calendar = MacFXDates.utc
                if let zone = source.dateTimeZoneID.flatMap(TimeZone.init(identifier:)) { calendar.timeZone = zone }
                else { calendar.timeZone = TimeZone(secondsFromGMT: 14 * 3600)! }
            }
            guard let actualDate, MacFXDates.day(actualDate, calendar: calendar) != nil,
                  actualDate <= MacFXDates.tag(Date(), calendar: calendar) else { throw MacSettingsFailure.invalid("报价日期无效或晚于当前日期") }
        }
        if let date { guard actualDate == date else { throw MacSettingsFailure.invalid("数据源未返回所请求日期，不能用于历史记账") } }
        return (rate, actualDate)
    }
    static func fetch(_ source: MacFXSource, from: String, to: String, date: Date = Date(), keyOverride: String? = nil) async throws -> MacFXQuote {
        try source.validate()
        if MacSettingsVisual.preview {
            let rate = (MacSettingsVisual.previewRates[to] ?? 1) / (MacSettingsVisual.previewRates[from] ?? 1)
            return MacFXQuote(from: from, to: to, rate: rate, source: source.name, sourceID: source.id, date: MacExchangeRates.dateTag(date), retrievedAt: Date())
        }
        let from = try MacCurrency.code(from), to = try MacCurrency.code(to), tag = MacExchangeRates.dateTag(date)
        let historical = tag != MacExchangeRates.dateTag(Date())
        if historical && (!source.urlTemplate.contains("{date}") || source.datePath.isEmpty) { throw MacSettingsFailure.invalid("此数据源不支持可核验的历史日期") }
        let data = try await requestData(source, from: from, to: to, date: date, keyOverride: keyOverride)
        let (rate, actualDate) = try decode(data, source: source, from: from, to: to, date: historical ? tag : nil)
        return MacFXQuote(from: from, to: to, rate: rate, source: source.name, sourceID: source.id, date: actualDate, retrievedAt: Date())
    }
    static func publicData(_ url: String) async throws -> Data {
        try await requestData(MacFXSource(name: "系统数据源", urlTemplate: url), from: "USD", to: "CNY", date: Date(), keyOverride: "")
    }
    static func requestData(_ source: MacFXSource, from: String, to: String, date: Date, keyOverride: String? = nil, dateTagOverride: String? = nil) async throws -> Data {
        let tag = dateTagOverride ?? MacExchangeRates.dateTag(date)
        let key: String
        if let keyOverride {key=keyOverride}else{key=try await MacFXSecrets.readAsync(source.id)}
        let url = try source.resolved(from: from, to: to, date: tag, key: key)
        var request = URLRequest(url: url); request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await transport.data(for: request)
    }

    nonisolated private static func positiveNumber(_ value: Any?) -> Double? {
        let result: Double?
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { result = number.doubleValue }
        else if let text = value as? String { result = Double(text) }
        else { result = nil }
        guard let result, result.isFinite, result > 0 else { return nil }
        return result
    }

    struct RefreshResult {
        var updated: [String] = []
        var failed: [String] = []
        var message: String { updated.isEmpty ? "没有更新汇率" : "已更新 \(updated.count) 种货币：" + updated.joined(separator: "、") }
        var failureMessage: String? { failed.isEmpty ? nil : "获取失败，保留原有缓存：" + failed.joined(separator: "、") }
    }
    static func refreshAll(from: String, codes: [String], date: Date = Date(),
                           fetchOverride: ((String, String, Date) async throws -> MacFXQuote)? = nil) async -> RefreshResult {
        var result = RefreshResult()
        let cycle = "accounting-batch/" + UUID().uuidString
        for code in Array(Set(codes)).sorted() where code != from {
            do {
                let quote:MacFXQuote
                if let fetchOverride { quote = try await fetchOverride(from,code,date) }
                else {
                    let day = MacExchangeRates.dateTag(date)
                    let evidence = try await MacExchangeRates.shared.evidence(pair:MacFXPair(base:from,quote:code),day:day,forceRefresh:true,cycle:cycle)
                    quote = MacFXQuote(from:from,to:code,rate:evidence.unitRate,source:MacFXApplication.shared.sourceLabel(evidence.identity.sourceID),sourceID:UUID(uuidString:evidence.identity.sourceID),date:day,retrievedAt:evidence.retrievedAt)
                }
                try persist(quote); result.updated.append(code)
            } catch { result.failed.append(code) }
        }
        return result
    }
    static func customQuote(from: String, to: String, date: Date) async -> MacFXQuote? {
        for source in sources where source.enabled {
            if let quote = try? await fetch(source, from: from, to: to, date: date) { try? persist(quote); return quote }
        }
        return nil
    }
}
