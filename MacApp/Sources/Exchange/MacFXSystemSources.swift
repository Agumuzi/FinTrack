import Foundation
import CoreFoundation

/// Private upstreams of the single user-facing system source. Each upstream
/// keeps its own identity and calendar so comparisons never mix definitions.
@MainActor
final class MacFXSystemSources {
    private var batches: [String:Task<Data,Error>] = [:]
    private var order: [String] = []
    private static let ecbCodes = ["USD","JPY","CZK","DKK","GBP","HUF","PLN","RON","SEK","CHF","ISK","NOK","AUD","BRL","CAD","CNY","HKD","IDR","ILS","INR","KRW","MXN","MYR","NZD","PHP","SGD","THB","TRY","ZAR"]
    static var moscow: Calendar { var c = MacFXDates.utc; c.timeZone = TimeZone(identifier:"Europe/Moscow")!; return c }
    func providers() -> [MacFXProvider] {
        ["ecb","frankfurter","cbr","floatrates"].map { kind in
            MacFXProvider(id:"system." + kind,revision:"system-" + kind + "-daily-v1",name:"系统数据源",supportsHistory:kind != "floatrates",dayCalendar:kind == "cbr" ? Self.moscow : MacFXDates.utc) { [weak self] pair,requested,purpose,cycle in
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

nonisolated enum MacFXSystemParsing {
    static func number(_ value:Any?) -> Double? {
        let result:Double?
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { result = n.doubleValue }
        else if let s = value as? String { result = Double(s) }
        else { result = nil }
        guard let result, MacFXMath.validRate(result) else { return nil }; return result
    }
    /// Currency -> effective day -> units per EUR.
    static func ecb(_ data:Data) throws -> [String:[String:Double]] {
        guard let root = try JSONSerialization.jsonObject(with:data) as? [String:Any], let structure = root["structure"] as? [String:Any], let dimensions = structure["dimensions"] as? [String:Any],
              let seriesDimensions = dimensions["series"] as? [[String:Any]], let currencyIndex = seriesDimensions.firstIndex(where:{$0["id"] as? String == "CURRENCY"}),
              let currencyValues = seriesDimensions[currencyIndex]["values"] as? [[String:Any]], let observations = dimensions["observation"] as? [[String:Any]],
              let time = observations.first(where:{$0["id"] as? String == "TIME_PERIOD"}), let days = time["values"] as? [[String:Any]],
              let sets = root["dataSets"] as? [[String:Any]], let series = sets.first?["series"] as? [String:[String:Any]] else { throw MacFXNetworkFailure.invalid }
        var result:[String:[String:Double]] = [:]
        for (key,value) in series {
            let indices = key.split(separator:":").compactMap { Int($0) }
            func dimension(_ name:String) -> String? {
                guard let index = seriesDimensions.firstIndex(where:{$0["id"] as? String == name}), indices.indices.contains(index),
                      let values = seriesDimensions[index]["values"] as? [[String:Any]], values.indices.contains(indices[index]) else { return nil }
                return values[indices[index]]["id"] as? String
            }
            guard dimension("FREQ") == "D", dimension("CURRENCY_DENOM") == "EUR",
                  indices.indices.contains(currencyIndex), currencyValues.indices.contains(indices[currencyIndex]), let code = currencyValues[indices[currencyIndex]]["id"] as? String,
                  let points = value["observations"] as? [String:[Any]] else { continue }
            for (index,values) in points {
                guard let i = Int(index), days.indices.contains(i), let day = days[i]["id"] as? String, MacFXDates.day(day) != nil, let rate = number(values.first) else { continue }
                result[code,default:[:]][day] = rate
            }
        }
        guard !result.isEmpty else { throw MacFXNetworkFailure.invalid }; return result
    }
    static func frankfurter(_ data:Data) throws -> [String:[String:Double]] {
        guard let rows = try JSONSerialization.jsonObject(with:data) as? [[String:Any]] else { throw MacFXNetworkFailure.invalid }
        var result:[String:[String:Double]] = [:]
        for row in rows {
            guard row["base"] as? String == "EUR", let code = row["quote"] as? String, let day = row["date"] as? String, MacFXDates.day(day) != nil, let rate = number(row["rate"]) else { continue }
            result[code,default:[:]][day] = rate
        }
        guard !result.isEmpty else { throw MacFXNetworkFailure.invalid }; return result
    }
    static func cross(_ values:[String:[String:Double]],pair:MacFXPair,requested:String?) throws -> (Double,String) {
        let a = pair.base == "EUR" ? nil : values[pair.base], b = pair.quote == "EUR" ? nil : values[pair.quote]
        guard pair.base == "EUR" || a != nil, pair.quote == "EUR" || b != nil else { throw MacFXNetworkFailure.invalid }
        let days = Set(a?.keys.map{$0} ?? b?.keys.map{$0} ?? []).intersection(Set(b?.keys.map{$0} ?? a?.keys.map{$0} ?? []))
        guard let day = requested ?? days.sorted().last, days.contains(day), let numerator = pair.quote == "EUR" ? 1 : b?[day], let denominator = pair.base == "EUR" ? 1 : a?[day], MacFXMath.validRate(numerator / denominator) else { throw MacFXNetworkFailure.invalid }
        return (numerator / denominator,day)
    }
}

nonisolated final class MacFXSystemCBRParser: NSObject, XMLParserDelegate {
    private var element = "", code = "", nominal = "", value = "", effective = ""
    private var rates:[String:Double] = ["RUB":1]
    static func document(_ data:Data) throws -> (day:String,rates:[String:Double]) {
        let delegate = MacFXSystemCBRParser(), parser = XMLParser(data:data)
        parser.shouldResolveExternalEntities = false; parser.externalEntityResolvingPolicy = .never; parser.delegate = delegate
        guard parser.parse(), delegate.rates.count > 1 else { throw MacFXNetworkFailure.invalid }
        let parts = delegate.effective.split(separator:".")
        guard parts.count == 3 else { throw MacFXNetworkFailure.invalid }
        let day = "\(parts[2])-\(parts[1])-\(parts[0])"
        guard MacFXDates.day(day) != nil else { throw MacFXNetworkFailure.invalid }
        return (day,delegate.rates)
    }
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String] = [:]) {
        element = name
        if name == "ValCurs" { effective = attributes["Date"] ?? "" }
        if name == "Valute" { code = ""; nominal = ""; value = "" }
    }
    func parser(_ parser:XMLParser,foundCharacters text:String) {
        switch element { case "CharCode":code += text; case "Nominal":nominal += text; case "Value":value += text; default:break }
    }
    func parser(_ parser:XMLParser,didEndElement name:String,namespaceURI:String?,qualifiedName:String?) {
        if name == "Valute" {
            let currency = code.trimmingCharacters(in:.whitespacesAndNewlines)
            let n = nominal.filter { !$0.isWhitespace }, v = value.filter { !$0.isWhitespace }.replacingOccurrences(of:",",with:".")
            if (try? MacFXPair(base:currency,quote:currency)) != nil, let units = Double(n), units > 0, let amount = Double(v), MacFXMath.validRate(amount / units) { rates[currency] = amount / units }
        }
        element = ""
    }
}
