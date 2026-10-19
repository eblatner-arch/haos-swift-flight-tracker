import Foundation
import Observation

/// Everything the screens show: your flights (api/state), each flight's full detail (api/leg/<id>)
/// with its live position (api/live/<id>), the aircraft pictures index and FAA ages.
@Observable
@MainActor
final class Store {
    var legs: [Leg] = []
    var details: [String: Leg] = [:]
    var offline = false
    var error: String?
    var updated: Date?
    var loading = false
    var liveries: JSON = .null
    var tailInfo: [String: JSON] = [:]

    /// What the map should show next (the flight page's buttons ask; the map follows focusTick).
    enum MapFocus: Equatable {
        case fit                                  // the selected flight's route, or all your flights
        case area(lat: Double, lon: Double, km: Double)
        case plane
    }
    var mapFocus: MapFocus = .fit
    var focusTick = 0
    func focus(_ f: MapFocus) {
        mapFocus = f
        focusTick += 1
    }

    /// Upcoming and in-progress first, then the ones that are done (most recent first).
    var upcoming: [Leg] {
        legs.filter { !$0.finished }.sorted { ($0.out.best ?? .distantFuture) < ($1.out.best ?? .distantFuture) }
    }
    var recent: [Leg] {
        legs.filter { $0.finished }.sorted { ($0.out.best ?? .distantPast) > ($1.out.best ?? .distantPast) }
    }

    func leg(_ id: String) -> Leg? {
        details[id] ?? legs.first { $0.id == id }
    }

    func refresh() async {
        guard API.base != nil else { error = API.Failure.noServer.errorDescription; return }
        loading = true
        defer { loading = false }
        do {
            let (j, fromPhone) = try await API.get("api/state")
            legs = j["legs"].array.map { Leg(j: $0) }
            offline = fromPhone
            error = nil
            if !fromPhone { updated = Date() }
        } catch {
            if (error as? CancellationError) == nil { self.error = error.localizedDescription }
        }
        if liveries.isNull, let r = try? await API.get("api/liveries") { liveries = r.0 }
    }

    func loadDetail(_ id: String) async {
        guard let r = try? await API.get("api/leg/\(id)") else { return }
        let fromPhone = r.1
        var leg = Leg(j: r.0)
        if let old = details[id], fromPhone { leg = old }   // a fresher one in memory beats the saved copy
        details[id] = leg
        if !fromPhone { offline = false }
    }

    /// New positions since the last one we have (every few seconds while the flight's page is open).
    func pollLive(_ id: String) async {
        guard var leg = details[id] else { return }
        let since = Int(leg.track.last?.at ?? 0)
        guard let r = try? await API.get("api/live/\(id)?since=\(since)", timeout: 8, keep: false), !r.1 else { return }
        let d = r.0
        var changed = false
        if !d["live"].isNull, (d["live"]["at"].double ?? 0) > (leg.live?.at ?? 0) {
            leg.j.set("live", d["live"])
            changed = true
        }
        let add = d["track"].array.filter { ($0[4].double ?? 0) > Double(since) }
        if !add.isEmpty {
            var f = leg.j["flight"]
            f.set("track", .array(f["track"].array + add))
            leg.j.set("flight", f)
            changed = true
        }
        if changed { details[id] = leg }
    }

    // ---------- aircraft pictures (Kyle's AI Works liveries, sorted by the add-on) ----------
    func liveryURL(_ leg: Leg) -> URL? {
        guard leg.airlineCode == "UA", let key = acKey(leg.aircraftType, leg.aircraftName) else { return nil }
        if let t = leg.tail, liveries["tails"][t].string == key { return API.url("api/livery/\(t).png") }
        if let first = liveries["types"][key][0].string { return API.url("api/livery/\(first).png") }
        return nil
    }

    // ---------- FAA registry: how old the airplane is ----------
    func loadTail(_ tail: String, type: String?) async {
        let key = "\(tail):\(type ?? "")"
        guard tailInfo[key] == nil else { return }
        let q = type.map { "?type=\($0)" } ?? ""
        if let r = try? await API.get("api/tail/\(tail)\(q)") { tailInfo[key] = r.0 }
    }

    func ageText(_ tail: String, type: String?) -> String? {
        guard let d = tailInfo["\(tail):\(type ?? "")"], d["found"].bool else { return nil }
        let now = Date()
        if let aw = d["aw"].string {
            let p = aw.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3, let when = Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return nil }
            let c = Calendar.current.dateComponents([.year, .month], from: when, to: now)
            let y = c.year ?? 0, m = c.month ?? 0
            let age = y < 0 ? "brand new" : (y > 0 ? "\(y) year\(y == 1 ? "" : "s") " : "") + "\(m) month\(m == 1 ? "" : "s") old"
            return "First flight · \(when.formatted(.dateTime.month(.abbreviated).day().year())) · \(age)"
        }
        if let y = d["year"].int {
            let a = Calendar.current.component(.year, from: now) - y
            return "Built \(y) · about \(a) year\(a == 1 ? "" : "s") old"
        }
        return nil
    }
}

/// Which 737 picture set fits a type code or name.
func acKey(_ type: String?, _ name: String?) -> String? {
    let t = (type ?? "").uppercased(), n = (name ?? "").uppercased()
    if t == "B39M" || t == "B3XM" || n.contains("MAX 9") || n.contains("MAX 10") { return "b39m" }
    if t == "B38M" || n.contains("MAX 8") { return "b38m" }
    if t == "B739" || n.contains("737-9") { return "b739" }
    if t == "B738" || n.contains("737-8") { return "b738" }
    if t == "B737" || n.contains("737-7") { return "b737" }
    return nil
}
