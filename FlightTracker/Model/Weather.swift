import Foundation

/// A METAR in words: "61°F and clear".
struct WeatherSummary {
    let fahrenheit: Int?
    let condition: String
    let symbol: String
    let category: String?

    init?(_ w: JSON) {
        guard let raw = w["raw"].string else { return nil }
        category = w["category"].string
        let body = (" " + raw + " ").components(separatedBy: " RMK ").first ?? raw
        let words = body.split(separator: " ").map(String.init)
        // temperature: 12/08 or M02/M05
        var t: Int?
        for wd in words {
            let parts = wd.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count == 2, parts[0].count >= 2, parts[0].count <= 3,
               let c = Int(parts[0].replacingOccurrences(of: "M", with: "-")), parts[0].allSatisfy({ $0.isNumber || $0 == "M" }) {
                t = c
                break
            }
        }
        fahrenheit = t.map { Int((Double($0) * 9 / 5 + 32).rounded()) }
        let wx = words.filter { w in
            ["TS", "DZ", "RA", "SN", "SG", "IC", "PL", "GR", "GS", "BR", "FG", "FU", "HZ", "SQ"].contains { w.contains($0) }
                && w.count <= 9 && !w.contains("/") && !w.hasSuffix("KT") && !w.hasPrefix("RMK")
        }
        func has(_ s: String) -> Bool { wx.contains { $0.contains(s) } }
        let light = wx.contains { $0.hasPrefix("-") }, heavy = wx.contains { $0.hasPrefix("+") }
        if has("TS") { condition = "thunderstorms"; symbol = "cloud.bolt.rain.fill" }
        else if has("SN") || has("SG") || has("PL") || has("IC") { condition = light ? "light snow" : "snow"; symbol = "cloud.snow.fill" }
        else if has("RA") || has("DZ") { condition = has("DZ") ? "drizzle" : light ? "light rain" : heavy ? "heavy rain" : "rain"; symbol = "cloud.rain.fill" }
        else if has("FG") { condition = "fog"; symbol = "cloud.fog.fill" }
        else if has("BR") || has("HZ") || has("FU") { condition = has("BR") ? "mist" : "haze"; symbol = "sun.haze.fill" }
        else if body.contains(" OVC") { condition = "overcast"; symbol = "cloud.fill" }
        else if body.contains(" BKN") { condition = "mostly cloudy"; symbol = "cloud.fill" }
        else if body.contains(" SCT") { condition = "partly cloudy"; symbol = "cloud.sun.fill" }
        else if body.contains(" FEW") { condition = "few clouds"; symbol = "cloud.sun.fill" }
        else { condition = "clear"; symbol = "sun.max.fill" }
    }

    var text: String { (fahrenheit.map { "\($0)°F and " } ?? "") + condition }
}
