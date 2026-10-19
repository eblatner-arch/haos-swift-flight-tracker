import Foundation
import CoreLocation
import SwiftUI

/// An airport as the add-on sends it.
struct Airport: Equatable {
    let j: JSON

    var code: String { j["iata"].string ?? j["icao"].string ?? "?" }
    var city: String { j["city"].string ?? j["name"].string ?? code }
    var name: String { j["name"].string ?? city }
    var coordinate: CLLocationCoordinate2D? {
        guard let la = j["lat"].double, let lo = j["lon"].double else { return nil }
        return CLLocationCoordinate2D(latitude: la, longitude: lo)
    }
    var timeZone: TimeZone { j["tz"].string.flatMap(TimeZone.init(identifier:)) ?? .current }
}

/// One of the four OOOI times: scheduled, estimated, actual.
struct Times: Equatable {
    let scheduled: Date?
    let estimated: Date?
    let actual: Date?

    init(_ j: JSON) {
        scheduled = j["scheduled"].date
        estimated = j["estimated"].date
        actual = j["actual"].date
    }

    /// The best we know: what happened, else the latest estimate, else the plan.
    var best: Date? { actual ?? estimated ?? scheduled }
    /// Minutes late against the schedule (negative: early).
    var lateMinutes: Int? {
        guard let s = scheduled, let b = best else { return nil }
        return Int((b.timeIntervalSince(s) / 60).rounded())
    }
}

/// A point of a track: [lat, lon, altitude ft, ground speed kt, time].
struct TrackPoint: Equatable {
    let coordinate: CLLocationCoordinate2D
    let altitude: Double?
    let speed: Double?
    let at: Double

    init?(_ j: JSON) {
        guard let la = j[0].double, let lo = j[1].double else { return nil }
        coordinate = CLLocationCoordinate2D(latitude: la, longitude: lo)
        altitude = j[2].double
        speed = j[3].double
        at = j[4].double ?? 0
    }

    static func == (a: TrackPoint, b: TrackPoint) -> Bool {
        a.at == b.at && a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude
    }
}

/// The live position (ADS-B / SWIM), the freshest thing we know about where the airplane is.
struct LivePosition: Equatable {
    let coordinate: CLLocationCoordinate2D
    let altitude: Double?
    let speed: Double?
    let heading: Double?
    let at: Double
    let source: String?

    init?(_ j: JSON) {
        guard let la = j["lat"].double, let lo = j["lon"].double else { return nil }
        coordinate = CLLocationCoordinate2D(latitude: la, longitude: lo)
        altitude = j["alt_ft"].double
        speed = j["gs_kt"].double
        heading = j["heading"].double
        at = j["at"].double ?? 0
        source = j["src"].string
    }

    static func == (a: LivePosition, b: LivePosition) -> Bool {
        a.at == b.at && a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude
    }
}

/// One flight of yours (a "leg" in the add-on), read straight from its JSON.
struct Leg: Identifiable, Equatable {
    var j: JSON

    var id: String { j["id"].string ?? "" }
    var display: String { j["display"].string ?? j["ident"].string ?? "Flight" }
    var airlineCode: String {
        let a = j["airline"].string ?? ""
        return a == "UAL" ? "UA" : a
    }
    var flightNumber: String { j["flight_no"].string ?? "" }
    var dep: Airport { Airport(j: j["dep_ap"]) }
    var arr: Airport { Airport(j: j["arr_ap"]) }
    var phase: String { j["phase"].string ?? "" }
    var status: String { j["status"].string ?? "" }
    var finished: Bool { j["finished"].bool }
    var deadhead: Bool { j["dh"].bool }
    var flight: JSON { j["flight"] }

    var out: Times { Times(flight["times"]["out"].isNull ? .object(["scheduled": j["sched_out"]]) : flight["times"]["out"]) }
    var off: Times { Times(flight["times"]["off"]) }
    var on: Times { Times(flight["times"]["on"]) }
    var inn: Times { Times(flight["times"]["in"].isNull ? .object(["scheduled": j["sched_in"]]) : flight["times"]["in"]) }

    var depGate: String? { flight["origin"]["gate"].string }
    var depTerminal: String? { flight["origin"]["terminal"].string }
    var arrGate: String? { flight["destination"]["gate"].string }
    var arrTerminal: String? { flight["destination"]["terminal"].string }
    var baggage: String? { flight["destination"]["baggage"].string }

    var tail: String? { flight["tail"].string?.uppercased() }
    var aircraftType: String? { flight["aircraft_type"].string?.uppercased() }
    var aircraftName: String? { flight["aircraft_name"].string ?? aircraftType.flatMap { typeNames[$0] } }
    var tailCount: Int? { j["tail_count"].int }
    var distanceNM: Double? { flight["distance_nm"].double }

    var problems: [String] { j["problems"].array.compactMap { $0["text"].string } }
    var live: LivePosition? { LivePosition(j["live"]) }
    var track: [TrackPoint] { flight["track"].array.compactMap(TrackPoint.init) }

    /// The planned route: the filed ATC route when the FAA has it, else FlightAware's waypoints.
    var plannedRoute: [CLLocationCoordinate2D] {
        let atc = flight["swim_route"]["pts"].array
        let src = atc.count > 1 ? atc : flight["waypoints"].array
        return src.compactMap { p in
            guard let la = p[0].double, let lo = p[1].double else { return nil }
            return CLLocationCoordinate2D(latitude: la, longitude: lo)
        }
    }

    /// Where the airplane is now, and which way it's pointing.
    var position: (CLLocationCoordinate2D, Double)? {
        guard ["airborne", "landed"].contains(phase) || phase.contains("taxi") else { return nil }
        let tr = track
        if let lv = live {
            let hdg = lv.heading ?? tr.last.map { bearing($0.coordinate, lv.coordinate) } ?? 0
            return (lv.coordinate, hdg)
        }
        guard let last = tr.last else { return nil }
        let prev = tr.count > 1 ? tr[tr.count - 2].coordinate : dep.coordinate ?? last.coordinate
        return (last.coordinate, bearing(prev, last.coordinate))
    }

    var inbound: JSON { j["inbound"] }
    var turnMinutes: Int? { j["turn"].int }

    /// The FAA's expected departure clearance time (a delay program), until the airplane takes off.
    var edct: (at: Date, program: String?)? {
        guard off.actual == nil, let at = flight["swim"]["edct"]["at"].date else { return nil }
        return (at, flight["swim"]["edct"]["for"].string)
    }
    /// FAA programs, closures and delay trends at this flight's airports.
    var nas: [JSON] { j["nas"].array }
    /// Current weather (METAR) at an airport of this flight.
    func weather(_ ap: Airport) -> JSON {
        for (k, v) in j["wx"].object where k == ap.code || k == (ap.j["icao"].string ?? "") || k.hasSuffix(ap.code) { return v }
        return .null
    }
    var routeStats: JSON { j["route_stats"] }
    var notFound: Bool { status.lowercased().contains("not found") }
}

/// What's happening now, in Flighty's words, and how it's going (for the colored banner).
struct StatusLine {
    let head: String
    let sub: String
    let tone: Color?

    init(head: String, sub: String, tone: Color?) {
        self.head = head
        self.sub = sub
        self.tone = tone
    }

    init(_ leg: Leg) {
        let now = Date()
        let am = leg.inn.lateMinutes, dm = leg.out.lateMinutes
        func lateLower(_ m: Int?) -> String {
            guard let m else { return "on time" }
            if abs(m) < 5 { return "on time" }
            return m > 0 ? "\(Fmt.span(Double(m * 60))) late" : "\(Fmt.span(Double(-m * 60))) early"
        }
        let tone: (Int?) -> Color? = { m in
            guard let m else { return nil }
            return m >= 15 ? .red : m >= 5 ? .orange : .green
        }
        switch leg.phase {
        case "airborne":
            let at = leg.on.best ?? leg.inn.best
            head = at.map { $0 > now ? "Landing in \(Fmt.span($0.timeIntervalSince(now)))" : "Landing now" } ?? "In the air"
            sub = "Arrives at the gate \(lateLower(am))."
            self.tone = tone(am)
        case "taxi_out":
            head = "Taxiing to the runway"
            let pushed = leg.out.actual.map { "Pushed back \(Fmt.span(now.timeIntervalSince($0))) ago. " } ?? ""
            sub = "\(pushed)Arrives \(lateLower(am))."
            self.tone = tone(am)
        case "landed":
            if let i = leg.inn.best, i > now { head = "At the gate in \(Fmt.span(i.timeIntervalSince(now)))" } else { head = "Landed" }
            sub = "Taxiing to the gate · arrives \(lateLower(am))."
            self.tone = tone(am)
        case "arrived":
            head = "Arrived \(lateLower(am))"
            sub = leg.inn.actual.map { "At the gate \(Fmt.span(now.timeIntervalSince($0))) ago." } ?? ""
            self.tone = tone(am)
        case "cancelled":
            head = "Cancelled"; sub = ""; self.tone = .red
        case "diverted":
            head = "Diverted to \(leg.arr.code)"; sub = ""; self.tone = .red
        default:
            if let o = leg.out.best, o > now { head = "Departs in \(Fmt.span(o.timeIntervalSince(now)))" } else { head = "Departing" }
            let known = leg.out.estimated != nil || leg.out.actual != nil
            if !known { sub = "Scheduled." }
            else if let d = dm, d >= 5 { sub = "Departs \(Fmt.span(Double(d * 60))) late" + ((am ?? 0) >= 5 ? ", arrives \(lateLower(am))." : ".") }
            else { sub = "On time" + ((am ?? 0) >= 5 ? ", arrives \(lateLower(am))." : ".") }
            self.tone = known ? tone(max(dm ?? 0, am ?? 0)) : nil
        }
    }
}

/// Degrees from a to b, 0 = north.
func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
    let la1 = a.latitude * .pi / 180, la2 = b.latitude * .pi / 180
    let dLo = (b.longitude - a.longitude) * .pi / 180
    let y = sin(dLo) * cos(la2)
    let x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dLo)
    let deg = atan2(y, x) * 180 / .pi
    return (deg + 360).truncatingRemainder(dividingBy: 360)
}

let typeNames: [String: String] = [
    "B737": "Boeing 737-700", "B738": "Boeing 737-800", "B739": "Boeing 737-900", "B38M": "Boeing 737 MAX 8",
    "B39M": "Boeing 737 MAX 9", "B3XM": "Boeing 737 MAX 10", "B752": "Boeing 757-200", "B753": "Boeing 757-300",
    "B763": "Boeing 767-300", "B764": "Boeing 767-400", "B772": "Boeing 777-200", "B77W": "Boeing 777-300ER",
    "B788": "Boeing 787-8", "B789": "Boeing 787-9", "B78X": "Boeing 787-10", "A319": "Airbus A319",
    "A320": "Airbus A320", "A20N": "Airbus A320neo", "A321": "Airbus A321", "A21N": "Airbus A321neo",
    "E75L": "Embraer 175", "E175": "Embraer 175", "CRJ2": "CRJ-200", "CRJ7": "CRJ-700", "CRJ9": "CRJ-900",
]
