import Foundation
import Observation

/// Everything the screens show: your flights (api/state), each flight's full detail (api/leg/<id>)
/// with its live position (api/live/<id>), the aircraft pictures index and FAA ages.
@Observable
@MainActor
final class Store {
    var legs: [Leg] = []
    /// the whole api/state answer (settings, version, recent alerts, where alerts go)
    var stateJ: JSON = .null
    var minTurn: Int { stateJ["settings"]["min_turn_minutes"].int ?? 30 }
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

    // ---------- Alerts and Passport ----------
    var alerts: [JSON] = []
    var passport: JSON = .null
    var passYear: String? = nil
    /// the search button: Passport opens with its search box ready
    var searchRequest = 0
    var histDetails: [String: JSON] = [:]

    func loadAlerts() async {
        if let r = try? await API.get("api/alerts") { alerts = r.0["alerts"].array }
    }

    func loadPassport() async {
        let path = "api/history" + (passYear.map { "?year=\($0)" } ?? "")
        if let r = try? await API.get(path) { passport = r.0 }
    }

    /// Ask the add-on to check a flight again now.
    func refreshLeg(_ id: String) async {
        _ = try? await API.post("api/refresh/\(id)")
    }

    // ---------- the airplane's earlier legs, and FAA status everywhere ----------
    var rotations: [String: [JSON]] = [:]
    var airportsStatus: JSON = .null

    func loadRotation(_ id: String) async {
        if let r = try? await API.get("api/leg/\(id)?rotation") { rotations[id] = r.0["rotation"].array; details[id] = Leg(j: r.0) }
    }

    func loadAirports() async {
        if let r = try? await API.get("api/airports/status") { airportsStatus = r.0 }
    }

    /// One of the airplane's earlier legs as a flight of its own (the same page as yours).
    func rotationLeg(_ id: String, _ n: Int) -> Leg? {
        let rot = rotations[id] ?? (leg(id)?.j["rotation"].array ?? [])
        guard rot.indices.contains(n), let parent = leg(id) else { return nil }
        let h = rot[n], t = h["times"]
        let prior = Array(rot.dropFirst(n + 1))
        var o: [String: JSON] = [
            "id": .string("\(id)~\(n)"), "ident": h["ident"], "display": h["display_ident"].isNull ? h["ident"] : h["display_ident"],
            "airline": parent.j["airline"], "dep_ap": h["origin"], "arr_ap": h["destination"], "flight": h, "phase": h["phase"],
            "status": h["status"], "sched_out": t["out"]["scheduled"].isNull ? t["off"]["scheduled"] : t["out"]["scheduled"],
            "sched_in": t["in"]["scheduled"].isNull ? t["on"]["scheduled"] : t["in"]["scheduled"],
            "rotation": .array(prior), "inbound": prior.first ?? .null, "source": .string("FlightAware"),
            "finished": .bool(["arrived", "cancelled", "diverted"].contains(h["phase"].string ?? "")),
            "watching": .bool(true), "tail_count": h["tail_count"],
        ]
        if n == 0, !parent.j["inbound_live"].isNull { o["live"] = parent.j["inbound_live"] }
        // its turn: from the airplane reaching the gate before it to this leg's departure
        if let before = prior.first, let inB = Times(before["times"]["in"]).best, let outB = Times(t["out"]).best {
            o["turn"] = .number((outB.timeIntervalSince(inB) / 60).rounded())
        }
        return Leg(j: .object(o))
    }

    func loadHist(_ id: String) async {
        if let r = try? await API.get("api/history/\(id)") { histDetails[id] = r.0 }
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
            stateJ = j
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

// ---------- FAA programs (ground stops, delay programs, closures, delay trends) ----------
let majorKinds = ["gs", "closure", "gdp"]

struct NasGroup: Identifiable {
    let n: JSON
    let tz: TimeZone
    var uses: [(leg: Leg, impact: [JSON])]
    var id: String { n["key"].string ?? UUID().uuidString }
    var kind: String { n["kind"].string ?? "" }
    var airport: String { n["airport"].string ?? "" }
    var major: Bool { majorKinds.contains(kind) }
    /// does it hold one of your flights (or its inbound)?
    var holds: Bool { uses.contains { $0.impact.contains { !$0["hit"].isNull ? $0["hit"].bool : true } } }
}

/// One group per program, listing every flight it touches; programs first.
func nasGroups(_ legs: [Leg]) -> [NasGroup] {
    var order: [String] = [], by: [String: NasGroup] = [:]
    for l in legs {
        for n in l.nas {
            let key = n["key"].string ?? "\(n["airport"].string ?? "")-\(n["kind"].string ?? "")"
            let apt = n["airport"].string
            let tz = apt == l.dep.code ? l.dep.timeZone : apt == l.arr.code ? l.arr.timeZone : .current
            if by[key] == nil { by[key] = NasGroup(n: n, tz: tz, uses: []); order.append(key) }
            by[key]?.uses.append((l, n["impact"].array))
        }
    }
    let rank: (NasGroup) -> Int = { majorKinds.firstIndex(of: $0.kind) ?? 9 }
    return order.compactMap { by[$0] }.sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0.airport < $1.airport }
}

