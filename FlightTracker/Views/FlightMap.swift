import SwiftUI
import MapKit

/// What the map draws: lines, airport tags and airplanes. Each sheet page makes one.
struct MapScene {
    struct Line: Identifiable {
        let id: String
        let coords: [CLLocationCoordinate2D]
        let color: Color
        let width: CGFloat
        let geodesic: Bool
        var dashed = false
    }
    struct Pin: Identifiable {
        let id: String
        let label: String
        let coordinate: CLLocationCoordinate2D
        var color: Color = .route
        var small = false
    }
    struct Plane: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let heading: Double
        var color: Color = .white
        var size: CGFloat = 24
    }
    var lines: [Line] = []
    var pins: [Pin] = []
    var planes: [Plane] = []
    /// what to frame
    var frame: [CLLocationCoordinate2D] = []
}

private func coord(_ p: JSON) -> CLLocationCoordinate2D? {
    guard let la = p[0].double, let lo = p[1].double else { return nil }
    return CLLocationCoordinate2D(latitude: la, longitude: lo)
}

/// Apple's map (satellite, a globe when zoomed out): your flights' routes, a flight's route, track and
/// airplane (and its inbound), or everything in your Passport.
struct FlightMap: View {
    @Environment(Store.self) private var store
    let route: Route?
    let tab: Tab
    @State private var camera: MapCameraPosition = .automatic

    private var scene: MapScene {
        switch route {
        case .leg(let id)?:
            if let leg = store.leg(id) { return legScene(leg) }
        case .hist(let id)?:
            if let f = store.histDetails[id] { return histScene(f) }
        case nil:
            if tab == .passport { return passScene() }
        }
        return homeScene()
    }

    private func straight(_ leg: Leg) -> [CLLocationCoordinate2D] {
        guard let a = leg.dep.coordinate, let b = leg.arr.coordinate else { return [] }
        return [a, b]
    }

    private func homeScene() -> MapScene {
        var s = MapScene(), seen = Set<String>()
        for leg in store.upcoming.prefix(15) {
            let pts = straight(leg)
            guard pts.count == 2 else { continue }
            let key = [leg.dep.code, leg.arr.code].sorted().joined(separator: "-")
            if !seen.contains(key) { seen.insert(key); s.lines.append(.init(id: key, coords: pts, color: .route, width: 2, geodesic: true)) }
            for (ap, c) in [(leg.dep, pts[0]), (leg.arr, pts[1])] where !s.pins.contains(where: { $0.id == ap.code }) {
                s.pins.append(.init(id: ap.code, label: ap.code, coordinate: c))
            }
            if let pos = leg.position { s.planes.append(.init(id: leg.id, coordinate: pos.0, heading: pos.1, size: 18)) }
            s.frame += pts
        }
        return s
    }

    private func legScene(_ leg: Leg) -> MapScene {
        var s = MapScene()
        let planned = leg.plannedRoute
        if planned.count > 1 {
            s.lines.append(.init(id: "plan", coords: planned, color: .route.opacity(0.8), width: 2, geodesic: false, dashed: true))
            s.frame += planned
        } else if !straight(leg).isEmpty {
            s.lines.append(.init(id: "plan", coords: straight(leg), color: .gray.opacity(0.8), width: 2, geodesic: true, dashed: true))
            s.frame += straight(leg)
        }
        var flown = leg.track.map(\.coordinate)
        if let lv = leg.live, ["airborne", "taxi_out", "landed"].contains(leg.phase) { flown.append(lv.coordinate) }
        if flown.count > 1 { s.lines.append(.init(id: "track", coords: flown, color: .route, width: 4, geodesic: false)) }
        // the airplane bringing you in, while it still matters
        let ib = leg.inbound
        if !ib.isNull {
            let o = Airport(j: ib["origin"])
            let open = !["arrived", "cancelled", "diverted"].contains(ib["phase"].string ?? "") && leg.phase == "scheduled"
            let itr = ib["track"].array.compactMap(coord)
            if itr.count > 1 { s.lines.append(.init(id: "itrack", coords: itr, color: .purple.opacity(open ? 0.9 : 0.35), width: 2.5, geodesic: false)) }
            if open, let oc = o.coordinate, let a = leg.dep.coordinate {
                s.lines.append(.init(id: "iplan", coords: [oc, a], color: .purple.opacity(0.45), width: 2, geodesic: true, dashed: true))
                s.pins.append(.init(id: "i-" + o.code, label: o.code, coordinate: oc, color: .purple))
                s.frame.append(oc)
            }
            if let last = itr.last, ib["phase"].string == "airborne" {
                let hdg = itr.count > 1 ? bearing(itr[itr.count - 2], last) : 0
                s.planes.append(.init(id: "inbound", coordinate: last, heading: hdg, color: .purple, size: 20))
                if open { s.frame.append(last) }
            }
        }
        for ap in [leg.dep, leg.arr] {
            if let c = ap.coordinate { s.pins.append(.init(id: ap.code, label: "\(ap.city)  \(ap.code)", coordinate: c)); s.frame.append(c) }
        }
        if let pos = leg.position { s.planes.append(.init(id: leg.id, coordinate: pos.0, heading: pos.1, size: 28)) }
        return s
    }

    private func histScene(_ f: JSON) -> MapScene {
        var s = MapScene()
        let a = Airport(j: f["dep_ap"]), b = Airport(j: f["arr_ap"])
        let tr = f["track"].array.compactMap(coord)
        if tr.count > 1 { s.lines.append(.init(id: "track", coords: tr, color: .route, width: 3.5, geodesic: false)); s.frame += tr }
        else if let ac = a.coordinate, let bc = b.coordinate { s.lines.append(.init(id: "gc", coords: [ac, bc], color: .route, width: 3, geodesic: true)) }
        for ap in [a, b] { if let c = ap.coordinate { s.pins.append(.init(id: ap.code, label: ap.code, coordinate: c)); s.frame.append(c) } }
        return s
    }

    private func passScene() -> MapScene {
        var s = MapScene(), seen = Set<String>(), aps = Set<String>()
        let A = store.passport["airports"]
        for f in store.passport["flights"].array where !f["cancelled"].bool {
            guard let d = f["dep"].string, let r = f["diverted_to"].string ?? f["arr"].string,
                  let la = A[d]["lat"].double, let lo = A[d]["lon"].double, let lb = A[r]["lat"].double, let lob = A[r]["lon"].double else { continue }
            let p = CLLocationCoordinate2D(latitude: la, longitude: lo), q = CLLocationCoordinate2D(latitude: lb, longitude: lob)
            let key = [d, r].sorted().joined(separator: "-")
            if !seen.contains(key) { seen.insert(key); s.lines.append(.init(id: key, coords: [p, q], color: Color(white: 0.92), width: 1.4, geodesic: true)) }
            for (code, c) in [(d, p), (r, q)] where !aps.contains(code) {
                aps.insert(code)
                s.pins.append(.init(id: code, label: code, coordinate: c, small: true))
                s.frame.append(c)
            }
        }
        return s
    }

    var body: some View {
        let sc = scene
        Map(position: $camera) {
            ForEach(sc.lines) { l in
                if l.dashed {
                    MapPolyline(coordinates: l.coords, contourStyle: l.geodesic ? .geodesic : .straight)
                        .stroke(l.color, style: StrokeStyle(lineWidth: l.width, lineCap: .round, dash: [6, 6]))
                } else {
                    MapPolyline(coordinates: l.coords, contourStyle: l.geodesic ? .geodesic : .straight)
                        .stroke(l.color, style: StrokeStyle(lineWidth: l.width, lineCap: .round, lineJoin: .round))
                }
            }
            ForEach(sc.pins) { p in
                Annotation(p.label, coordinate: p.coordinate, anchor: .center) {
                    if p.small {
                        Circle().fill(Color.route).stroke(.white, lineWidth: 1).frame(width: 6, height: 6)
                    } else {
                        Text(p.label)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(p.color, in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.white)
                    }
                }
                .annotationTitles(.hidden)
            }
            ForEach(sc.planes) { pl in
                Annotation("", coordinate: pl.coordinate, anchor: .center) {
                    Image(systemName: "airplane")
                        .font(.system(size: pl.size, weight: .bold))
                        .foregroundStyle(pl.color)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                        .rotationEffect(.degrees(pl.heading - 90))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onChange(of: store.focusTick) { _, _ in apply(store.mapFocus) }
        .onChange(of: frameKey) { _, _ in apply(.fit) }
        .onAppear { apply(.fit) }
    }

    /// changes when there's something new to frame (another page, or its data arrived)
    private var frameKey: String {
        let s = scene
        return "\(String(describing: route))|\(tab.rawValue)|\(s.lines.count)|\(s.pins.count)"
    }

    private func apply(_ f: Store.MapFocus) {
        let target: MapCameraPosition?
        switch f {
        case .fit:
            let pts = scene.frame
            target = pts.isEmpty ? nil : .rect(fitRect(pts))
        case .area(let la, let lo, let km):
            let d = km / 111.0
            target = .rect(fitRect([CLLocationCoordinate2D(latitude: la - d, longitude: lo - d), CLLocationCoordinate2D(latitude: la + d, longitude: lo + d)], margin: 0.05))
        case .plane:
            if let p = scene.planes.last {
                let d = 0.6, c = p.coordinate
                target = .rect(fitRect([CLLocationCoordinate2D(latitude: c.latitude - d, longitude: c.longitude - d),
                                        CLLocationCoordinate2D(latitude: c.latitude + d, longitude: c.longitude + d)], margin: 0.05))
            } else {
                target = nil
            }
        }
        guard let target else { return }
        withAnimation(.easeInOut(duration: 1.1)) { camera = target }
    }

    /// A map rectangle around the points, with room below for the sheet (it covers about half
    /// the screen) so the route sits in the part of the map you can see.
    private func fitRect(_ pts: [CLLocationCoordinate2D], margin: Double = 0.12) -> MKMapRect {
        var r = MKMapRect.null
        for c in pts {
            let p = MKMapPoint(c)
            r = r.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1))
        }
        let w = max(r.width, 2000), h = max(r.height, 2000)
        let padW = w * margin, padTop = h * margin
        let below = h * 1.1   // the sheet
        return MKMapRect(x: r.midX - w / 2 - padW, y: r.minY - padTop, width: w + 2 * padW, height: h + padTop + below)
    }
}
