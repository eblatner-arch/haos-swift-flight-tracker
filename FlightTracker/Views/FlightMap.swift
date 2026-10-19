import SwiftUI
import MapKit

/// Apple's map (satellite, a globe when zoomed out): your flights' routes, or one flight's route,
/// where it has flown and where the airplane is now.
struct FlightMap: View {
    @Environment(Store.self) private var store
    let selectedID: String?
    @State private var camera: MapCameraPosition = .automatic

    private struct Pin: Identifiable {
        let id: String
        let code: String
        let coordinate: CLLocationCoordinate2D
    }

    private var shown: [Leg] {
        if let id = selectedID, let leg = store.leg(id) { return [leg] }
        return Array(store.upcoming.prefix(15))
    }

    private var pins: [Pin] {
        var seen = Set<String>(), out: [Pin] = []
        for leg in shown {
            for ap in [leg.dep, leg.arr] {
                guard let c = ap.coordinate, !seen.contains(ap.code) else { continue }
                seen.insert(ap.code)
                out.append(Pin(id: ap.code, code: ap.code, coordinate: c))
            }
        }
        return out
    }

    /// The route still to fly: the filed route if there is one, else straight (great circle).
    private func route(_ leg: Leg) -> [CLLocationCoordinate2D] {
        let planned = leg.plannedRoute
        if planned.count > 1 { return planned }
        guard let a = leg.dep.coordinate, let b = leg.arr.coordinate else { return [] }
        return [a, b]
    }

    var body: some View {
        let one = selectedID != nil
        Map(position: $camera) {
            ForEach(shown) { leg in
                MapPolyline(coordinates: route(leg), contourStyle: .geodesic)
                    .stroke(Color.route.opacity(one ? 0.85 : 0.7), lineWidth: one ? 3 : 2)
                if one {
                    let flown = leg.track.map(\.coordinate)
                    if flown.count > 1 {
                        MapPolyline(coordinates: flown + (leg.live.map { [$0.coordinate] } ?? []))
                            .stroke(Color.yellow, lineWidth: 3)
                    }
                }
                if let pos = leg.position {
                    Annotation(leg.display, coordinate: pos.0, anchor: .center) {
                        Image(systemName: "airplane")
                            .font(.system(size: one ? 26 : 18, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                            .rotationEffect(.degrees(pos.1 - 90))
                    }
                    .annotationTitles(.hidden)
                }
            }
            ForEach(pins) { p in
                Annotation(p.code, coordinate: p.coordinate, anchor: .center) {
                    Text(p.code)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.route, in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.white)
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
        .onChange(of: shown.map(\.id)) { _, _ in apply(.fit) }
        .onAppear { apply(.fit) }
    }

    private func apply(_ f: Store.MapFocus) {
        let target: MapCameraPosition?
        switch f {
        case .fit:
            var pts: [CLLocationCoordinate2D] = []
            for leg in shown {
                pts += route(leg)
                if let c = leg.dep.coordinate { pts.append(c) }
                if let c = leg.arr.coordinate { pts.append(c) }
            }
            target = pts.isEmpty ? nil : .rect(fitRect(pts))
        case .area(let la, let lo, let km):
            let d = km / 111.0
            let pts = [CLLocationCoordinate2D(latitude: la - d, longitude: lo - d), CLLocationCoordinate2D(latitude: la + d, longitude: lo + d)]
            target = .rect(fitRect(pts, margin: 0.05))
        case .plane:
            if let id = selectedID, let leg = store.leg(id), let here = leg.position?.0 {
                let d = 0.6
                target = .rect(fitRect([CLLocationCoordinate2D(latitude: here.latitude - d, longitude: here.longitude - d),
                                        CLLocationCoordinate2D(latitude: here.latitude + d, longitude: here.longitude + d)], margin: 0.05))
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
