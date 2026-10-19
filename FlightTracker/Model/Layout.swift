import Foundation
import CoreLocation

/// An airport's diagram from OpenStreetMap (the add-on fetches it once): terminals, runways,
/// taxiways, and the names to write on them.
struct AirportLayout {
    struct Label { let id: Int; let at: CLLocationCoordinate2D; let text: String; let kind: Kind }
    enum Kind { case terminal, runway, taxiway, gate }
    var terminals: [[CLLocationCoordinate2D]] = []
    var runways: [[CLLocationCoordinate2D]] = []
    var taxiways: [[CLLocationCoordinate2D]] = []
    var labels: [Label] = []

    init(_ d: JSON) {
        func pts(_ g: JSON) -> [CLLocationCoordinate2D] {
            g.array.compactMap { p in
                guard let la = p[0].double, let lo = p[1].double else { return nil }
                return CLLocationCoordinate2D(latitude: la, longitude: lo)
            }
        }
        func km(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
            CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1000
        }
        func mid(_ p: [CLLocationCoordinate2D]) -> (CLLocationCoordinate2D, Double) {
            var seg: [Double] = [], tot = 0.0
            for i in 1..<max(1, p.count) { let k = km(p[i - 1], p[i]); seg.append(k); tot += k }
            var half = tot / 2
            for (i, s) in seg.enumerated() {
                if half <= s {
                    let t = s > 0 ? half / s : 0
                    return (CLLocationCoordinate2D(latitude: p[i].latitude + (p[i + 1].latitude - p[i].latitude) * t,
                                                   longitude: p[i].longitude + (p[i + 1].longitude - p[i].longitude) * t), tot)
                }
                half -= s
            }
            return (p[0], tot)
        }
        var placed: [String: [CLLocationCoordinate2D]] = [:]
        func near(_ ref: String, _ p: CLLocationCoordinate2D, _ k: Double) -> Bool { (placed[ref] ?? []).contains { km($0, p) < k } }
        var n = 0
        func add(_ at: CLLocationCoordinate2D, _ text: String, _ kind: Kind) { labels.append(Label(id: n, at: at, text: text, kind: kind)); n += 1 }
        for f in d["features"].array {
            let k = f["k"].string ?? "", ref = f["ref"].string
            let line = f["g"][0].array.isEmpty ? [] : pts(f["g"])
            switch k {
            case "terminal" where line.count > 2:
                terminals.append(line)
                if let t = f["name"].string ?? ref {
                    let c = CLLocationCoordinate2D(latitude: line.map(\.latitude).reduce(0, +) / Double(line.count), longitude: line.map(\.longitude).reduce(0, +) / Double(line.count))
                    add(c, t, .terminal)
                }
            case "runway" where line.count > 1:
                runways.append(line)
                if let r = ref { add(mid(line).0, r.replacingOccurrences(of: #"^0"#, with: "", options: .regularExpression).replacingOccurrences(of: "/0", with: "/"), .runway) }
            case "taxiway" where line.count > 1:
                taxiways.append(line)
                if let r = ref {
                    let (p, len) = mid(line)
                    if len < 0.08 || near(r, p, 0.35) { continue }
                    placed[r, default: []].append(p)
                    add(p, r, .taxiway)
                }
            case "gate", "stand":
                guard let r = ref, let la = f["g"][0].double, let lo = f["g"][1].double else { continue }
                let p = CLLocationCoordinate2D(latitude: la, longitude: lo)
                if near("gate:" + r, p, 0.05) { continue }
                placed["gate:" + r, default: []].append(p)
                add(p, r, .gate)
            default: break
            }
        }
    }
}
