import SwiftUI

@main
struct FlightTrackerApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}

/// Where the sheet is: a flight of yours, or one from your Passport.
enum Route: Hashable {
    case leg(String)
    case hist(String)
    case aircraft(String, Int)   // your flight's id, and which earlier leg of its airplane (0 = the inbound)
    case airports
}

enum Tab: String, CaseIterable {
    case flights = "My Flights", alerts = "Alerts", passport = "Passport"
}

/// The link scheme Home Assistant notifications open: ericsflights://leg/<id>. Its own name, so it
/// never collides with Flighty (flighty://) or any other app.
let linkScheme = "ericsflights"

/// The map fills the screen; your flights sit in a sheet over it, like the web app (and Flighty):
/// three stops (peeking, middle, full). Swipe anywhere on the sheet to move it; once it's full, the
/// same swipe scrolls the page, and swiping down from the top of the page brings the sheet back down.
/// Opening a flight puts the sheet back at the middle and the flight's route on the map.
struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []
    @State private var tab: Tab = .flights
    @State private var stop: SheetStop = .mid
    @State private var drag: CGFloat = 0
    @State private var dragging = false
    @State private var sheet = SheetState()
    @State private var showSettings = false
    @State private var showAdd = false

    var body: some View {
        GeometryReader { geo in
            let H = geo.size.height, inset = safeTop()
            let ys = stops(H, inset)
            let y = max(ys[.full]!, (ys[stop] ?? H * 0.45) + drag)
            ZStack(alignment: .top) {
                FlightMap(route: path.last, tab: tab)
                MapButtons(route: path.last, airports: { open(.airports) })
                    .padding(.top, inset + 8)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Telemetry(route: path.last).padding(.top, inset)
                panel(height: H - ys[.full]!)
                    .offset(y: y)
                    .animation(dragging ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: stop)
                    .simultaneousGesture(dragGesture(ys))
                VStack {
                    Spacer()
                    TabBar(tab: Binding(get: { tab }, set: { t in tab = t; path = []; stop = .mid }),
                           search: { tab = .passport; path = []; stop = .full; store.searchRequest += 1 })
                        .padding(.bottom, max(8, safeBottom() - 14))
                }
            }
            .onAppear { sheet.fullTop = ys[.full]! + 16 }
            .onChange(of: H) { _, _ in sheet.fullTop = ys[.full]! + 16 }
        }
        .ignoresSafeArea()
        .environment(sheet)
        .sheet(isPresented: $showSettings) { SettingsView(addFlight: { showSettings = false; showAdd = true }) }
        .sheet(isPresented: $showAdd) { AddFlightView(opened: { id in showAdd = false; tab = .flights; open(.leg(id)) }) }
        .task {
            if API.base == nil { showSettings = true }
            // testing: launched with -openLeg <id> opens that flight
            if let id = UserDefaults.standard.string(forKey: "openLeg"), !id.isEmpty { path = [.leg(id)] }
            if UserDefaults.standard.string(forKey: "openTab") == "passport" { tab = .passport }
            if UserDefaults.standard.bool(forKey: "bigSheet") { stop = .full }
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
        // ericsflights://leg/<id> (a Home Assistant notification): open that flight
        .onOpenURL { url in
            guard url.scheme == linkScheme else { return }
            showSettings = false
            showAdd = false
            if url.host == "leg", let id = url.pathComponents.last, id != "/" {
                tab = .flights
                open(.leg(id))
                Task { await store.refresh() }
            } else {
                path = []
            }
        }
        .onChange(of: path) { _, _ in store.focus(.fit) }
        .onChange(of: tab) { _, _ in store.focus(.fit) }
    }

    private func open(_ r: Route) {
        path = [r]
        stop = .mid
    }

    private func panel(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.white.opacity(0.28)).frame(width: 40, height: 5).padding(.top, 8).padding(.bottom, 3)
            NavigationStack(path: $path) {
                HomeView(tab: $tab, showSettings: $showSettings, showAdd: $showAdd, open: { open($0) })
                    .navigationDestination(for: Route.self) { r in
                        Group {
                            switch r {
                            case .leg(let id): FlightDetail(id: id)
                            case .hist(let id): HistFlightView(id: id)
                            case .aircraft(let id, let n): AircraftLegView(id: id, n: n)
                            case .airports: AirportsView()
                            }
                        }
                        .background(Th.sheet)
                    }
                    .background(Th.sheet)
            }
            .scrollDisabled(stop != .full || dragging)
        }
        .frame(height: height, alignment: .top)
        .background(Th.sheet)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 10, y: -3)
    }

    /// where the sheet's top sits at each stop
    private func stops(_ H: CGFloat, _ inset: CGFloat) -> [SheetStop: CGFloat] {
        let midF: CGFloat = path.isEmpty ? (tab == .passport ? 0.58 : 0.42) : 0.5
        return [.full: inset + 6, .mid: H * midF, .peek: H - 190]
    }

    private func dragGesture(_ ys: [SheetStop: CGFloat]) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in
                if !dragging {
                    guard abs(v.translation.height) > abs(v.translation.width) else { return }
                    // full: the page scrolls, unless it's at its top and you pull down
                    if stop == .full && !(sheet.atTop && v.translation.height > 0) { return }
                    dragging = true
                }
                drag = v.translation.height
            }
            .onEnded { v in
                guard dragging else { return }
                let cur = (ys[stop] ?? 0) + v.translation.height
                let aim = (ys[stop] ?? 0) + v.predictedEndTranslation.height
                let target = [SheetStop.full, .mid, .peek].min { abs((ys[$0] ?? 0) - aim) < abs((ys[$1] ?? 0) - aim) } ?? stop
                // land from where it was let go, then spring to the stop
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { drag = cur - (ys[target] ?? 0); stop = target }
                dragging = false
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { drag = 0 }
            }
    }

    private func safeTop() -> CGFloat { keyWindow()?.safeAreaInsets.top ?? 47 }
    private func safeBottom() -> CGFloat { keyWindow()?.safeAreaInsets.bottom ?? 34 }
    private func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
    }
}

enum SheetStop { case full, mid, peek }

/// Shared with the pages in the sheet: where their scrolling content's top is, so a pull down at
/// the top of a page moves the sheet instead.
@Observable
final class SheetState {
    var contentTop: CGFloat = 0
    var fullTop: CGFloat = 0
    var atTop: Bool { contentTop >= fullTop - 6 }
}

extension View {
    /// Put on the content inside a sheet page's ScrollView.
    func sheetScroll() -> some View { modifier(SheetScrollReporter()) }
}

private struct SheetScrollReporter: ViewModifier {
    @Environment(SheetState.self) private var sheet
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { g in
                let y = g.frame(in: .global).minY
                Color.clear
                    .onAppear { sheet.contentTop = y }
                    .onChange(of: y) { _, v in sheet.contentTop = v }
            }
        )
    }
}

/// The round buttons on the right of the map, like the web app's: center on the routes, and on a
/// flight, zoom to the airplane or either airport.
struct MapButtons: View {
    @Environment(Store.self) private var store
    let route: Route?
    let airports: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            button("location.fill") { store.focus(.fit) }
            if route == nil {
                Button(action: airports) {
                    TowerShape().fill(towerColor).frame(width: 22, height: 22)
                        .frame(width: 46, height: 46)
                        .background(Color(hex: 0x24242A, alpha: 0.93), in: Circle())
                }
                .buttonStyle(.plain)
            }
            if case .leg(let id)? = route, let leg = store.leg(id) {
                if leg.position != nil { button("airplane") { store.focus(.plane) } }
                if let c = leg.dep.coordinate { button("airplane.departure") { store.focus(.area(lat: c.latitude, lon: c.longitude, km: 2.2)) } }
                if let c = leg.arr.coordinate { button("airplane.arrival") { store.focus(.area(lat: c.latitude, lon: c.longitude, km: 2.2)) } }
            }
        }
        .padding(.trailing, 12)
    }

    /// red: a ground stop or closure catches one of your flights; amber: a delay program does
    private var towerColor: Color {
        var lvl = 0
        for g in nasGroups(store.upcoming.filter { $0.watching }) where g.major && g.holds {
            lvl = max(lvl, g.kind == "gs" || g.kind == "closure" ? 2 : 1)
        }
        return lvl == 2 ? Th.red : lvl == 1 ? Th.amber : .white
    }

    private func button(_ sym: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: sym).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color(hex: 0x24242A, alpha: 0.93), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Speed and altitude on top of the map while your flight is in the air (like the web app's pill).
struct Telemetry: View {
    @Environment(Store.self) private var store
    let route: Route?
    var body: some View {
        if case .leg(let id)? = route, let leg = store.leg(id), leg.phase == "airborne", let lv = leg.live, let gs = lv.speed {
            HStack(spacing: 16) {
                HStack(spacing: 5) {
                    Image(systemName: "speedometer").foregroundStyle(Th.muted)
                    Text("\(Int(gs * 1.15078).formatted())").font(.system(size: 17, weight: .bold))
                    Text("MPH").font(.system(size: 11, weight: .bold)).foregroundStyle(Th.muted)
                }
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.to.line").foregroundStyle(Th.muted)
                    Text(lv.altitude.map { Int($0).formatted() } ?? "—").font(.system(size: 17, weight: .bold))
                    Text("FT").font(.system(size: 11, weight: .bold)).foregroundStyle(Th.muted)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Color(hex: 0x26262A, alpha: 0.94), in: Capsule())
            .padding(.top, 8)
        }
    }
}

/// The web app's control-tower icon (24x24 drawing).
struct TowerShape: Shape {
    func path(in r: CGRect) -> Path {
        let k = min(r.width, r.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * k, y: r.minY + y * k) }
        var path = Path()
        path.addLines([p(8, 3), p(16, 3), p(17.5, 7.5), p(6.5, 7.5)]); path.closeSubpath()
        path.addLines([p(5.8, 8.5), p(18.2, 8.5), p(16.8, 12.5), p(7.2, 12.5)]); path.closeSubpath()
        path.addLines([p(9, 13.5), p(15, 13.5), p(15.6, 21), p(8.4, 21)]); path.closeSubpath()
        path.addLines([p(11, 1), p(13, 1), p(13, 3), p(11, 3)]); path.closeSubpath()
        return path
    }
}

