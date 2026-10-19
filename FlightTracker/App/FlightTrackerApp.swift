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

/// The map fills the screen; your flights sit in a sheet over it, like Flighty. Opening a flight
/// pushes its page in the sheet and puts its route on the map.
struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []
    @State private var tab: Tab = .flights
    @State private var detent: PresentationDetent = .fraction(0.45)
    @State private var showSettings = false

    var body: some View {
        FlightMap(route: path.last, tab: tab)
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) { MapButtons(route: path.last, airports: { path = [.airports] }) }
            .overlay(alignment: .top) { Telemetry(route: path.last) }
            .sheet(isPresented: .constant(true)) {
                NavigationStack(path: $path) {
                    HomeView(tab: $tab, showSettings: $showSettings, open: { path = [$0] })
                        .navigationDestination(for: Route.self) { r in
                            switch r {
                            case .leg(let id): FlightDetail(id: id)
                            case .hist(let id): HistFlightView(id: id)
                            case .aircraft(let id, let n): AircraftLegView(id: id, n: n)
                            case .airports: AirportsView()
                            }
                        }
                }
                .overlay(alignment: .bottom) {
                    TabBar(tab: Binding(get: { tab }, set: { t in tab = t; path = [] }),
                           search: { tab = .passport; path = []; detent = .large; store.searchRequest += 1 })
                }
                .presentationBackground(Th.sheet)
                .presentationContentInteraction(.resizes)   // swiping anywhere moves the sheet first, then scrolls
                .presentationDetents([.height(96), .fraction(0.45), .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
                .presentationCornerRadius(26)
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                }
            }
            .task {
                if API.base == nil { showSettings = true }
                // testing: launched with -openLeg <id> opens that flight
                if let id = UserDefaults.standard.string(forKey: "openLeg"), !id.isEmpty { path = [.leg(id)] }
                if UserDefaults.standard.string(forKey: "openTab") == "passport" { tab = .passport }
                if UserDefaults.standard.bool(forKey: "bigSheet") { detent = .large }
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
                if url.host == "leg", let id = url.pathComponents.last, id != "/" {
                    tab = .flights
                    path = [.leg(id)]
                    detent = .fraction(0.45)
                    Task { await store.refresh() }
                } else {
                    path = []
                }
            }
            .onChange(of: path) { _, _ in store.focus(.fit) }
            .onChange(of: tab) { _, _ in store.focus(.fit) }
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
            if route == nil { button("building.columns.fill") { airports() } }
            if case .leg(let id)? = route, let leg = store.leg(id) {
                if leg.position != nil { button("airplane") { store.focus(.plane) } }
                if let c = leg.dep.coordinate { button("airplane.departure") { store.focus(.area(lat: c.latitude, lon: c.longitude, km: 2.2)) } }
                if let c = leg.arr.coordinate { button("airplane.arrival") { store.focus(.area(lat: c.latitude, lon: c.longitude, km: 2.2)) } }
            }
        }
        .padding(.trailing, 12)
        .padding(.top, 60)
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
            .padding(.top, 54)
        }
    }
}

