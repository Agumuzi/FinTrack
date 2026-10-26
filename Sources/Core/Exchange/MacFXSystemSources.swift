import Foundation
import CoreFoundation

/// Private upstreams of the single user-facing system source. Each upstream
/// keeps its own identity and calendar so comparisons never mix definitions.
actor MacFXSystemSources {
    private let rangeClient = MacFXRangeClient(load: { try await MacFXService.publicData($0) })
    private var batches: [String:Task<Data,Error>] = [:]
    private var order: [String] = []
    private static let ecbCodes = ["USD","JPY","CZK","DKK","GBP","HUF","PLN","RON","SEK","CHF","ISK","NOK","AUD","BRL","CAD","CNY","HKD","IDR","ILS","INR","KRW","MXN","MYR","NZD","PHP","SGD","THB","TRY","ZAR"]
    nonisolated static var moscow: Calendar { var c = MacFXDates.utc; c.timeZone = TimeZone(identifier:"Europe/Moscow")!; return c }
    nonisolated func providers() -> [MacFXProvider] {
        ["ecb","frankfurter","cbr","floatrates"].map { kind in
            MacFXProvider(id:"system." + kind,revision:"system-" + kind + "-daily-v1",name:"系统数据源",supportsHistory:kind != "floatrates",dayCalendar:kind == "cbr" ? Self.moscow : MacFXDates.utc,rangeAvailable:kind != "floatrates", rangeFetch: { [weak self] pair, start, end in
                guard let self else { throw MacFXContractFailure.unavailable }
                return try await self.rangeClient.fetch(pair: pair, source: "system." + kind, start: start, end: end)
            }) { [weak self] pair,requested,purpose,cycle in
                guard let self, purpose != .accountingDay else { throw MacFXContractFailure.invalidEvidence }
                return try await self.quote(kind:kind,pair:pair,requested:requested,purpose:purpose,cycle:cycle)
            }
        }
    }
    func quote(kind:String,pair:MacFXPair,requested:MacFXRequestDate,purpose:MacFXPurpose,cycle:String) async throws -> MacFXEvidenceQuote {
        let day: String? = { if case .day(let d) = requested { return d }; return nil }()
        let calendar = kind == "cbr" ? Self.moscow : MacFXDates.utc
        var rate: Double, actual: String
        switch kind {
        case "ecb", "frankfurter":
            guard [pair.base,pair.quote].allSatisfy({$0 == "EUR" || Self.ecbCodes.contains($0)}) else { throw MacFXNetworkFailure.invalid }
            let url: String
            if kind == "ecb" {
                url = "https://data-api.ecb.europa.eu/service/data/EXR/D." + Self.ecbCodes.joined(separator:"+") + ".EUR.SP00.A?format=jsondata&detail=dataonly&" + (day.map { "startPeriod=" + $0 + "&endPeriod=" + $0 } ?? "lastNObservations=5")
            } else {
                url = "https://api.frankfurter.dev/v2/providers/ecb/rates?base=EUR&quotes=" + Self.ecbCodes.joined(separator:",") + (day.map { "&date=" + $0 } ?? "")
            }
            let data = try await loadData(url,cycle:cycle)
            let values = try kind == "ecb" ? MacFXSystemParsing.ecb(data) : MacFXSystemParsing.frankfurter(data)
            (rate,actual) = try MacFXSystemParsing.cross(values,pair:pair,requested:day)
        case "cbr":
            let queryDay = day ?? MacFXDates.tag(Date(),calendar:calendar)
            guard MacFXDates.day(queryDay,calendar:calendar) != nil else { throw MacFXNetworkFailure.invalid }
            let parts = queryDay.split(separator:"-")
            let url = "https://www.cbr.ru/scripts/XML_daily.asp?date_req=\(parts[2])/\(parts[1])/\(parts[0])"
            let document = try MacFXSystemCBRParser.document(try await loadData(url,cycle:cycle))
            guard let a = document.rates[pair.base], let b = document.rates[pair.quote] else { throw MacFXNetworkFailure.invalid }
            rate = a / b; actual = document.day
        case "floatrates":
            let payload = try await loadData("https://www.floatrates.com/daily/" + pair.base.lowercased() + ".json",cycle:cycle)
            guard let root = try JSONSerialization.jsonObject(with:payload) as? [String:Any], let entry = root[pair.quote.lowercased()] as? [String:Any],
                  entry["code"] as? String == pair.quote, let value = MacFXSystemParsing.number(entry["rate"]), let text = entry["date"] as? String else { throw MacFXNetworkFailure.invalid }
            let f = DateFormatter(); f.locale = Locale(identifier:"en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT:0); f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            guard let timestamp = f.date(from:text), timestamp <= Date().addingTimeInterval(300) else { throw MacFXNetworkFailure.invalid }
            rate = value; actual = MacFXDates.tag(timestamp,calendar:MacFXDates.utc)
        default: throw MacFXNetworkFailure.invalid
        }
        guard MacFXMath.validRate(rate), MacFXDates.day(actual,calendar:calendar) != nil,
              actual <= MacFXDates.tag(Date(),calendar:calendar), day == nil || actual == day else { throw MacFXNetworkFailure.invalid }
        if day == nil {
            let oldest = calendar.date(byAdding:.day,value:-14,to:Date())!
            guard actual >= MacFXDates.tag(oldest,calendar:calendar) else { throw MacFXNetworkFailure.invalid }
        }
        return MacFXEvidenceQuote(identity:.init(purpose:purpose,pair:pair,sourceID:"system." + kind,sourceRevision:"system-" + kind + "-daily-v1",requested:requested),unitRate:rate,quoteTime:.day(actual,timeZoneID:calendar.timeZone.identifier),retrievedAt:Date(),legs:[])
    }
    private func loadData(_ url:String,cycle:String) async throws -> Data {
        let key = cycle + "/" + url
        if let pending = batches[key] { return try await pending.value }
        let task = Task { try await MacFXService.requestData(MacFXSource(name:"系统数据源",urlTemplate:url),from:"USD",to:"CNY",date:Date(),keyOverride:"") }
        batches[key] = task; order.append(key)
        while order.count > 128 { batches.removeValue(forKey:order.removeFirst()) }
        return try await task.value
    }
}
