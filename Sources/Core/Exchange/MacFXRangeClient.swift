import Foundation

/// Publication-day series only. Never used for accounting or current quotes.
actor MacFXRangeClient {
    nonisolated static let ecbCodes = Set(["EUR","USD","JPY","CZK","DKK","GBP","HUF","PLN","RON","SEK","CHF","ISK","NOK","AUD","BRL","CAD","CNY","HKD","IDR","ILS","INR","KRW","MXN","MYR","NZD","PHP","SGD","THB","TRY","ZAR"])
    nonisolated static func supports(_ pair: MacFXPair, source: String) -> Bool {
        if source == "system.cbr" { return pair.base == "RUB" || pair.quote == "RUB" }
        return ["system.ecb", "system.frankfurter"].contains(source) && ecbCodes.contains(pair.base) && ecbCodes.contains(pair.quote)
    }
    private let load: @Sendable (String) async throws -> Data
    init(load: @escaping @Sendable (String) async throws -> Data) { self.load = load }
    private var tasks: [String: Task<Data, Error>] = [:]
    private var order: [String] = []
    private var currencyIDs: [String: String] = [:]
    private func payload(_ url: String) async throws -> Data {
        if let task = tasks[url] { return try await task.value }
        let task = Task { try await load(url) }
        tasks[url] = task; order.append(url)
        do {
            let result = try await task.value
            // Share completed payloads briefly within this batch; the repository
            // owns freshness. Bounded entries prevent ever-growing URL retention.
            while order.count > 16 { tasks.removeValue(forKey: order.removeFirst()) }
            return result
        } catch { tasks[url] = nil; order.removeAll { $0 == url }; throw error }
    }
    func fetch(pair: MacFXPair, source: String, start: String, end: String) async throws -> [MacFXHistoryPoint] {
        guard MacFXDates.day(start) != nil, MacFXDates.day(end) != nil, start <= end,
              Self.supports(pair, source: source) else { throw MacFXNetworkFailure.invalid }
        let values: [String: [String: Double]]
        let zone: String
        if source == "system.cbr" {
            zone = "Europe/Moscow"
            if currencyIDs.isEmpty {
                currencyIDs = try MacFXSystemCBRParser.document(await payload("https://www.cbr.ru/scripts/XML_daily.asp")).ids
            }
            var rows: [String: [String: Double]] = [:]
            for code in Set([pair.base, pair.quote]).subtracting(["RUB"]).sorted() {
                guard let id = currencyIDs[code] else { throw MacFXNetworkFailure.invalid }
                func formatted(_ day: String) -> String { day.split(separator: "-").reversed().joined(separator: "/") }
                let url = "https://www.cbr.ru/scripts/XML_dynamic.asp?date_req1=\(formatted(start))&date_req2=\(formatted(end))&VAL_NM_RQ=\(id)"
                rows[code] = try MacFXCBRSeries.parse(await payload(url), expectedID: id)
            }
            values = rows
        } else {
            zone = "UTC"
            let codes = Set([pair.base, pair.quote]).subtracting(["EUR"]).sorted()
            if source == "system.ecb" {
                let url = "https://data-api.ecb.europa.eu/service/data/EXR/D.\(codes.joined(separator: "+")).EUR.SP00.A?format=jsondata&detail=dataonly&startPeriod=\(start)&endPeriod=\(end)"
                values = try MacFXSystemParsing.ecb(await payload(url))
            } else {
                let url = "https://api.frankfurter.dev/v2/providers/ecb/rates?base=EUR&quotes=\(codes.joined(separator: ","))&from=\(start)&to=\(end)"
                values = try MacFXSystemParsing.frankfurter(await payload(url))
            }
        }
        let anchor = source == "system.cbr" ? "RUB" : "EUR"
        let a = values[pair.base], b = values[pair.quote]
        guard pair.base == anchor || a != nil, pair.quote == anchor || b != nil else { throw MacFXNetworkFailure.invalid }
        let days = Set(a?.keys.map { $0 } ?? b?.keys.map { $0 } ?? []).intersection(Set(b?.keys.map { $0 } ?? a?.keys.map { $0 } ?? []))
        let now = Date()
        let result = days.sorted().compactMap { day -> MacFXHistoryPoint? in
            guard day >= start, day <= end, let base = pair.base == anchor ? 1 : a?[day],
                  let quote = pair.quote == anchor ? 1 : b?[day] else { return nil }
            let rate = source == "system.cbr" ? base / quote : quote / base
            guard MacFXMath.validRate(rate) else { return nil }
            return MacFXHistoryPoint(day: day, unitRate: rate, quoteTime: .day(day, timeZoneID: zone), retrievedAt: now)
        }
        guard !result.isEmpty else { throw MacFXNetworkFailure.invalid }
        // Completed URL payloads must not prevent the repository's later refresh.
        tasks = tasks.filter { !order.contains($0.key) }; order = []
        return result
    }
}

nonisolated final class MacFXCBRSeries: NSObject, XMLParserDelegate {
    private var element = "", day = "", nominal = "", value = "", id = ""
    private var expectedID = ""
    private var rows: [String: Double] = [:]
    private var invalid = false
    static func parse(_ data: Data, expectedID: String) throws -> [String: Double] {
        let delegate = MacFXCBRSeries(); delegate.expectedID = expectedID
        let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never; parser.delegate = delegate
        guard parser.parse(), !delegate.invalid, !delegate.rows.isEmpty else { throw MacFXNetworkFailure.invalid }
        return delegate.rows
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        element = name
        if name == "Record" { day = attributes["Date"] ?? ""; id = attributes["Id"] ?? ""; nominal = ""; value = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters text: String) {
        if element == "Nominal" { nominal += text }; if element == "Value" { value += text }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "Record" {
            let date = day.split(separator: ".").reversed().joined(separator: "-")
            let n = Double(nominal.filter { !$0.isWhitespace }), v = Double(value.filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: "."))
            if id == expectedID, MacFXDates.day(date) != nil, let n, n > 0, let v, MacFXMath.validRate(v / n), rows[date] == nil { rows[date] = v / n }
            else { invalid = true }
        }
        element = ""
    }
}
