import Foundation
import CoreFoundation

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
    private var ids: [String: String] = [:]
    private var recordID = ""
    static func document(_ data:Data) throws -> (day:String,rates:[String:Double],ids:[String:String]) {
        let delegate = MacFXSystemCBRParser(), parser = XMLParser(data:data)
        parser.shouldResolveExternalEntities = false; parser.externalEntityResolvingPolicy = .never; parser.delegate = delegate
        guard parser.parse(), delegate.rates.count > 1 else { throw MacFXNetworkFailure.invalid }
        let parts = delegate.effective.split(separator:".")
        guard parts.count == 3 else { throw MacFXNetworkFailure.invalid }
        let day = "\(parts[2])-\(parts[1])-\(parts[0])"
        guard MacFXDates.day(day) != nil else { throw MacFXNetworkFailure.invalid }
        return (day,delegate.rates,delegate.ids)
    }
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String] = [:]) {
        element = name
        if name == "ValCurs" { effective = attributes["Date"] ?? "" }
        if name == "Valute" { code = ""; nominal = ""; value = ""; recordID = attributes["ID"] ?? "" }
    }
    func parser(_ parser:XMLParser,foundCharacters text:String) {
        switch element { case "CharCode":code += text; case "Nominal":nominal += text; case "Value":value += text; default:break }
    }
    func parser(_ parser:XMLParser,didEndElement name:String,namespaceURI:String?,qualifiedName:String?) {
        if name == "Valute" {
            let currency = code.trimmingCharacters(in:.whitespacesAndNewlines)
            let n = nominal.filter { !$0.isWhitespace }, v = value.filter { !$0.isWhitespace }.replacingOccurrences(of:",",with:".")
            if (try? MacFXPair(base:currency,quote:currency)) != nil, let units = Double(n), units > 0, let amount = Double(v), MacFXMath.validRate(amount / units) { rates[currency] = amount / units; if recordID.range(of: "^R[0-9]+$", options: .regularExpression) != nil { ids[currency] = recordID } }
        }
        element = ""
    }
}
