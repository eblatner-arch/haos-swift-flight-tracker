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
        var style: Style = .pill
        enum Style { case pill, dot, text, dotPill, dotCode }
    }
    struct Plane: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let heading: Double
        var color: Color = .white
        var size: CGFloat = 24
    }
    struct Area: Identifiable {
        let id: String
        let rings: [[CLLocationCoordinate2D]]
        let color: Color
        let fill: Double
        let width: CGFloat
    }
    var areas: [Area] = []
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
    /// the map's size, and the part of it where routes should sit (above the sheet, clear of buttons)
    let screen: CGSize
    let area: CGRect
    @State private var camera: MapCameraPosition = .automatic
    /// a framing just asked for: once the camera stops, it's checked and corrected (MapKit's own
    /// fitting of a rectangle pads it, and the globe zooms out further)
    @State private var want: MKMapRect?
    /// what's on screen now, and how far up the camera is (for the airport diagrams)
    @State private var seen: MKMapRect = .null
    @State private var camDist: Double = 1e7
    /// FAA surface radar at the airport you're looking at (yours, or your inbound's)
    @State private var surf: [JSON] = []
    /// Map shape (Settings): flat frames routes exactly; the globe looks like Flighty's but has to zoom out further
    @AppStorage("mapGlobe") private var globe = false
    @AppStorage("mapDark") private var dark = false
    @AppStorage("mapDays") private var mapDays = 0

    private var scene: MapScene {
        switch route {
        case .leg(let id)?:
            if let leg = store.leg(id) { return legScene(leg) }
        case .hist(let id)?:
            if let f = store.histDetails[id] { return histScene(f) }
        case .aircraft(let id, let n)?:
            if let leg = store.rotationLeg(id, n) { return rotScene(leg, store.rotations[id]?[safe: n]) }
        case .airports?:
            return airportsScene()
        case .nas(let key)?:
            return nasScene(key)
        case .find?, .stats?:
            return passScene()

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
        let until = mapDays > 0 ? Date().addingTimeInterval(Double(mapDays) * 86400) : .distantFuture
        for leg in store.upcoming where (leg.out.best ?? .distantPast) < until {
            let pts = straight(leg)
            guard pts.count == 2 else { continue }
            let key = [leg.dep.code, leg.arr.code].sorted().joined(separator: "-")
            if !seen.contains(key) { seen.insert(key); s.lines.append(.init(id: key, coords: pts, color: .route, width: 2, geodesic: true)) }
            for (ap, c) in [(leg.dep, pts[0]), (leg.arr, pts[1])] where !s.pins.contains(where: { $0.id == ap.code }) {
                s.pins.append(.init(id: ap.code, label: ap.code, coordinate: c, style: .dot))
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
            let iph = ib["phase"].string ?? ""
            var itr = ib["track"].array.compactMap(coord)
            let ilive = LivePosition(leg.j["inbound_live"])
            if let lv = ilive, ["airborne", "landed", "taxi_out"].contains(iph) { itr.append(lv.coordinate) }
            if itr.count > 1 { s.lines.append(.init(id: "itrack", coords: itr, color: .purple.opacity(open ? 0.9 : 0.35), width: 2.5, geodesic: false)) }
            // where it is now: the dashed line is only what's left to fly
            let flying = iph == "airborne" || iph == "taxi_out"
            let here = flying ? (ilive?.coordinate ?? itr.last) : nil
            if open, let a = leg.dep.coordinate {
                if let here {
                    s.lines.append(.init(id: "iplan", coords: [here, a], color: .purple.opacity(0.45), width: 2, geodesic: true, dashed: true))
                    s.frame.append(here)
                } else if let oc = o.coordinate {
                    s.lines.append(.init(id: "iplan", coords: [oc, a], color: .purple.opacity(0.45), width: 2, geodesic: true, dashed: true))
                    s.pins.append(.init(id: "i-" + o.code, label: o.code, coordinate: oc, color: .purple))
                    s.frame.append(oc)
                }
            }
            if let here, iph == "airborne" {
                let hdg = ilive?.heading ?? (itr.count > 1 ? bearing(itr[itr.count - 2], here) : 0)
                s.planes.append(.init(id: "inbound", coordinate: here, heading: hdg, color: .purple, size: 20))
            }
        }
        for ap in [leg.dep, leg.arr] {
            if let c = ap.coordinate { s.pins.append(.init(id: ap.code, label: "\(ap.city)  \(ap.code)", coordinate: c)); s.frame.append(c) }
        }
        if let pos = leg.position { s.planes.append(.init(id: leg.id, coordinate: pos.0, heading: pos.1, size: 28)) }
        return s
    }

    /// an earlier leg of your airplane: its track (if the add-on sent one), its route, the airplane
    private func rotScene(_ leg: Leg, _ raw: JSON?) -> MapScene {
        var s = MapScene()
        var tr = (raw ?? .null)["track"].array.compactMap(coord)
        let ph = leg.phase
        let flying = ["airborne", "taxi_out"].contains(ph)
        if let lv = leg.live, flying || ph == "landed" { tr.append(lv.coordinate) }
        let here = flying ? (leg.live?.coordinate ?? tr.last) : nil
        let gc = straight(leg)
        if gc.count == 2 {
            s.frame += gc
            // the dashed line is what's left to fly: all of it before takeoff, none once it's down
            if let here { s.lines.append(.init(id: "plan", coords: [here, gc[1]], color: Th.violet.opacity(0.6), width: 2, geodesic: true, dashed: true)) }
            else if tr.count < 2 { s.lines.append(.init(id: "plan", coords: gc, color: Th.violet.opacity(0.6), width: 2, geodesic: true, dashed: true)) }
        }
        if tr.count > 1 { s.lines.append(.init(id: "track", coords: tr, color: Th.violet, width: 3.5, geodesic: false)) }
        for ap in [leg.dep, leg.arr] { if let c = ap.coordinate { s.pins.append(.init(id: ap.code, label: "\(ap.city)  \(ap.code)", coordinate: c, color: Th.violet)) } }
        if let here {
            let hdg = leg.live?.heading ?? (tr.count > 1 ? bearing(tr[tr.count - 2], here) : gc.count == 2 ? bearing(gc[0], gc[1]) : 0)
            s.planes.append(.init(id: "p", coordinate: here, heading: hdg, color: Th.violet, size: 26))
        } else if ph == "airborne", gc.count == 2, let est = estimatedPosition(leg, gc) {
            s.planes.append(.init(id: "p", coordinate: est.0, heading: est.1, color: Th.violet, size: 26))
        }
        return s
    }

    /// no track or live position yet: where it should be, along the great circle by time flown
    private func estimatedPosition(_ leg: Leg, _ gc: [CLLocationCoordinate2D]) -> (CLLocationCoordinate2D, Double)? {
        guard let off = leg.off.best ?? leg.out.best, let on = leg.on.best ?? leg.inn.best, on > off else { return nil }
        let f = max(0, min(1, Date().timeIntervalSince(off) / on.timeIntervalSince(off)))
        let p = CLLocationCoordinate2D(latitude: gc[0].latitude + (gc[1].latitude - gc[0].latitude) * f,
                                       longitude: gc[0].longitude + (gc[1].longitude - gc[0].longitude) * f)
        return (p, bearing(gc[0], gc[1]))
    }

    /// FAA status: every airport with an issue, red for programs and stops, amber for delays
    private func airportsScene() -> MapScene {
        var s = MapScene()
        for a in store.airportsStatus["airports"].array {
            guard let la = a["lat"].double, let lo = a["lon"].double, let code = a["code"].string else { continue }
            let kinds = a["items"].array.compactMap { $0["kind"].string }
            let red = kinds.contains { ["gs", "closure", "gdp"].contains($0) }
            let c = CLLocationCoordinate2D(latitude: la, longitude: lo)
            s.pins.append(.init(id: code, label: code, coordinate: c, color: red ? Th.red : Th.amber, style: .dotCode))
            s.frame.append(c)
        }
        if s.frame.isEmpty { s.frame = [CLLocationCoordinate2D(latitude: 48, longitude: -124), CLLocationCoordinate2D(latitude: 25, longitude: -68)] }
        return s
    }

    /// an FAA program: the en-route centers whose departures it holds (shaded), the program's airport,
    /// and where your flights (or their inbounds) depart: red if held, green if not
    private func nasScene(_ key: String) -> MapScene {
        var s = MapScene()
        guard let g = store.nasGroup(key) else { return s }
        let hot = g.kind == "gs" ? Th.red : Th.amber
        let scope = Set(g.n["scope"].array.compactMap { $0.string })
        for (id, c) in store.artcc.object {
            let inS = scope.contains(id)
            let rings = c["rings"].array.map { $0.array.compactMap(coord) }.filter { $0.count > 2 }
            if rings.isEmpty { continue }
            s.areas.append(.init(id: id, rings: rings, color: inS ? hot : Th.muted, fill: inS ? 0.22 : 0, width: inS ? 1.5 : 0.8))
            if inS {
                let big = rings.max { $0.count < $1.count } ?? []
                let la = big.map(\.latitude).reduce(0, +) / Double(max(1, big.count)), lo = big.map(\.longitude).reduce(0, +) / Double(max(1, big.count))
                s.frame.append(CLLocationCoordinate2D(latitude: la, longitude: lo))
            }
            // every center's name, in the program's color when it's held, gray otherwise
            let big = rings.max { $0.count < $1.count } ?? []
            if !big.isEmpty {
                var la = big.map(\.latitude).reduce(0, +) / Double(big.count), lo = big.map(\.longitude).reduce(0, +) / Double(big.count)
                if let at = ctrLabelAt[id] { la = at.0; lo = at.1 }
                s.pins.append(.init(id: "c-" + id, label: id, coordinate: CLLocationCoordinate2D(latitude: la, longitude: lo), color: inS ? hot : Th.muted, style: .text))
            }
        }
        if let p = store.airportCoord(g.airport) {
            s.pins.append(.init(id: g.airport, label: g.airport, coordinate: p, color: hot, style: .dotPill))
            s.frame.append(p)
        }
        for u in g.uses {
            for i in u.impact {
                guard let from = i["from"].string, let p = store.airportCoord(from) ?? Airport(j: u.leg.inbound["origin"]).coordinate else { continue }
                let c = i["airborne"].bool ? Th.muted : i["hit"].isNull ? Th.muted : i["hit"].bool ? hot : Th.green
                if from != g.airport { s.pins.append(.init(id: "f-" + from, label: from, coordinate: p, color: c, style: .dotPill)) }
                s.frame.append(p)
            }
        }
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
                s.pins.append(.init(id: code, label: code, coordinate: c, style: .dot))
                s.frame.append(c)
            }
        }
        return s
    }

    var body: some View {
        let sc = scene
        Map(position: $camera) {
            ForEach(sc.areas) { a in
                ForEach(Array(a.rings.enumerated()), id: \.offset) { _, r in
                    MapPolygon(coordinates: r)
                        .foregroundStyle(a.color.opacity(a.fill))
                        .stroke(a.color.opacity(a.fill > 0 ? 0.9 : 0.5), lineWidth: a.width)
                }
            }
            ForEach(sc.lines) { l in
                if l.dashed {
                    MapPolyline(coordinates: l.coords, contourStyle: l.geodesic ? .geodesic : .straight)
                        .stroke(l.color, style: StrokeStyle(lineWidth: l.width, lineCap: .round, dash: [6, 6]))
                } else {
                    MapPolyline(coordinates: l.coords, contourStyle: l.geodesic ? .geodesic : .straight)
                        .stroke(l.color, style: StrokeStyle(lineWidth: l.width, lineCap: .round, lineJoin: .round))
                }
            }
            layoutContent
            ForEach(sc.pins) { p in
                Annotation(p.label, coordinate: p.coordinate, anchor: [.dotPill, .dotCode].contains(p.style) ? UnitPoint(x: 0.06, y: 0.5) : .center) {
                    switch p.style {
                    case .dot:
                        Circle().fill(p.color).frame(width: 8, height: 8).overlay(Circle().stroke(.white, lineWidth: 1.5))
                    case .text:
                        Text(p.label).font(.system(size: 12, weight: .heavy)).foregroundStyle(p.color)
                            .shadow(color: .black, radius: 1.5).shadow(color: .black.opacity(0.8), radius: 3)
                    case .dotCode:
                        HStack(spacing: 4) {
                            Circle().fill(p.color).frame(width: 11, height: 11).overlay(Circle().stroke(.white, lineWidth: 1.5))
                            Text(p.label).font(.system(size: 11, weight: .heavy)).foregroundStyle(.white).shadow(color: .black, radius: 2)
                        }
                    case .dotPill:
                        HStack(spacing: 5) {
                            Circle().fill(p.color).frame(width: 13, height: 13).overlay(Circle().stroke(.white, lineWidth: 2))
                            Text(p.label).font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(p.color, in: RoundedRectangle(cornerRadius: 7))
                                .foregroundStyle(.white)
                        }
                    case .pill:
                        Text(p.label)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(p.color, in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.white)
                    }
                }
                .annotationTitles(.hidden)
            }
            surfaceContent
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
        .mapStyle(dark ? .standard(elevation: globe ? .realistic : .flat, pointsOfInterest: .excludingAll)
                  : globe ? .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll) : .hybrid(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { ctx in
            seen = ctx.rect
            camDist = ctx.camera.distance
            guard let w = want else { return }
            want = nil
            // too far out (or in, or off center): put the camera right over the wanted framing
            let ratio = ctx.rect.size.height / max(1, w.size.height)
            let dx = abs(ctx.rect.midX - w.midX) / max(1, w.size.width), dy = abs(ctx.rect.midY - w.midY) / max(1, w.size.height)
            guard ratio > 0.05, ratio < 20, abs(ratio - 1) > 0.05 || dx > 0.03 || dy > 0.03 else { return }
            let c = MKMapPoint(x: w.midX, y: w.midY).coordinate
            withAnimation(.easeInOut(duration: 0.35)) {
                camera = .camera(MapCamera(centerCoordinate: c, distance: ctx.camera.distance / ratio, heading: 0, pitch: 0))
            }
        }
        .task(id: surfQuery) {
            guard let q = surfQuery else { surf = []; return }
            while !Task.isCancelled {
                if let r = try? await API.get(q, timeout: 8, keep: false), !r.1 {
                    surf = r.0["targets"].array.filter { $0["mine"].bool || ($0["xpdr"].bool && $0["kind"].string != "vehicle") || $0["kind"].string == "vehicle" }
                }
                try? await Task.sleep(for: .seconds(surf.isEmpty ? 20 : 3))
            }
        }
        .task(id: layoutCodes) { for c in layoutCodes { await store.loadLayout(c) } }
        .onChange(of: store.focusTick) { _, _ in apply(store.mapFocus) }
        .onChange(of: area) { _, _ in apply(store.mapFocus) }
        .onChange(of: frameKey) { _, _ in apply(.fit) }
        .onAppear { apply(.fit) }
    }

    @MapContentBuilder private var layoutContent: some MapContent {
    // airport diagrams, once you're close enough to see them
    if camDist < 40_000 {
        ForEach(layoutCodes, id: \.self) { code in
            if let L = store.layouts[code] {
                ForEach(Array(L.terminals.enumerated()), id: \.offset) { _, r in
                    MapPolygon(coordinates: r).foregroundStyle(Color(hex: 0xC8CDD8).opacity(0.16)).stroke(Color(hex: 0xC8CDD8).opacity(0.5), lineWidth: 1)
                }
                ForEach(Array(L.taxiways.enumerated()), id: \.offset) { _, l in
                    MapPolyline(coordinates: l).stroke(.white.opacity(0.14), style: StrokeStyle(lineWidth: max(1.5, 23 * pointsPerMeter), lineCap: .round, lineJoin: .round))
                }
                if camDist < 6_000 {
                    ForEach(Array(L.taxiways.enumerated()), id: \.offset) { _, l in
                        MapPolyline(coordinates: l).stroke(Color(hex: 0xF6C445).opacity(0.5), lineWidth: 1)
                    }
                }
                ForEach(Array(L.runways.enumerated()), id: \.offset) { _, l in
                    MapPolyline(coordinates: l).stroke(.white.opacity(0.24), style: StrokeStyle(lineWidth: max(3, 45 * pointsPerMeter), lineCap: .butt))
                    MapPolyline(coordinates: l).stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [8, 8]))
                }
                ForEach(layoutLabels(L)) { lb in
                    Annotation("", coordinate: lb.at, anchor: .center) {
                        Text(lb.text)
                            .font(.system(size: lb.kind == .runway ? 13 : lb.kind == .terminal ? 12 : 11, weight: lb.kind == .gate ? .semibold : .heavy))
                            .foregroundStyle(lb.kind == .taxiway ? Color(hex: 0xF6C445) : lb.kind == .gate ? Color(hex: 0x9FC2FF) : .white)
                            .padding(.horizontal, lb.kind == .runway ? 5 : 0).padding(.vertical, lb.kind == .runway ? 1 : 0)
                            .background(lb.kind == .runway ? Color.black.opacity(0.55) : .clear, in: RoundedRectangle(cornerRadius: 4))
                            .shadow(color: .black, radius: 1.5)
                    }
                }
            }
        }
    }
    }

    @MapContentBuilder private var surfaceContent: some MapContent {
    // everything moving on the ground there: airplanes with transponders, yours highlighted
    if camDist < 25_000 {
        ForEach(Array(surf.enumerated()), id: \.offset) { _, t in
            if let la = t["lat"].double, let lo = t["lon"].double {
                let mine = t["mine"].bool
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: la, longitude: lo), anchor: .center) {
                    if !mine && (t["kind"].string == "vehicle" || (t["cs"].isNull && t["type"].isNull)) {
                        Circle().fill(Color(white: 0.56)).frame(width: 5, height: 5)
                    } else {
                        ZStack(alignment: .leading) {
                            Image(systemName: "airplane")
                                .font(.system(size: mine ? 20 : 13, weight: .bold))
                                .foregroundStyle(mine ? Color.route : .white.opacity(0.9))
                                .shadow(color: .black.opacity(0.7), radius: 2)
                                .rotationEffect(.degrees((t["hdg"].double ?? 0) - 90))
                            if mine || camDist < 4_000, let cs = t["cs"].string {
                                Text(cs).font(.system(size: mine ? 12 : 10, weight: .bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(mine ? Color.route : Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                                    .offset(x: mine ? 18 : 12)
                                    .fixedSize()
                            }
                        }
                    }
                }
                .annotationTitles(.hidden)
            }
        }
    }
    }

    /// changes when there's something new to frame (another page, or its data arrived)
    private var frameKey: String {
        let s = scene
        return "\(String(describing: route))|\(tab.rawValue)|\(s.lines.count)|\(s.pins.count)"
    }

    private func apply(_ f: Store.MapFocus) {
        let r: MKMapRect?
        switch f {
        case .fit:
            let pts = scene.frame
            r = pts.isEmpty ? nil : fitRect(pts, fill: 0.92)
        case .area(let la, let lo, let km):
            let d = km / 111.0
            r = fitRect([CLLocationCoordinate2D(latitude: la - d, longitude: lo - d), CLLocationCoordinate2D(latitude: la + d, longitude: lo + d)], fill: 1)
        case .plane:
            if let p = scene.planes.last {
                let d = 0.6, c = p.coordinate
                r = fitRect([CLLocationCoordinate2D(latitude: c.latitude - d, longitude: c.longitude - d),
                             CLLocationCoordinate2D(latitude: c.latitude + d, longitude: c.longitude + d)], fill: 1)
            } else {
                r = nil
            }
        }
        guard let r else { return }
        want = r
        withAnimation(.easeInOut(duration: 1.1)) { camera = .rect(r) }
    }

    /// The whole map's rectangle (same shape as the screen) that puts the points in the open area
    /// above the sheet: as big as fits (times fill), centered in that area.
    private func fitRect(_ pts: [CLLocationCoordinate2D], fill: Double) -> MKMapRect {
        var r = MKMapRect.null
        for c in pts {
            let p = MKMapPoint(c)
            r = r.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1))
        }
        let W = max(1, screen.width), H = max(1, screen.height)
        let aw = max(60, area.width), ah = max(60, area.height)
        // map points per screen point
        let k = max(max(r.width, 3000) / (aw * fill), max(r.height, 3000) / (ah * fill))
        let cx = area.midX, cy = area.midY
        return MKMapRect(x: r.midX - cx * k, y: r.midY - cy * k, width: W * k, height: H * k)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// where a center's name reads best (over land, not its ocean part), like the web app
let ctrLabelAt: [String: (Double, Double)] = [
    "ZNY": (41.05, -76.45), "ZOA": (39.2, -120.6), "ZLA": (34.8, -116.8), "ZSE": (45.6, -120.4), "ZMA": (26.8, -81.0),
    "ZJX": (31.2, -82.6), "ZBW": (43.6, -71.8), "ZHU": (30.6, -93.8), "ZDC": (37.6, -77.8),
]

