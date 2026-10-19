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
            .sheet(isPresented: .constant(true)) {
                NavigationStack(path: $path) {
                    HomeView(tab: $tab, showSettings: $showSettings, open: { path = [$0] })
                        .navigationDestination(for: Route.self) { r in
                            switch r {
                            case .leg(let id): FlightDetail(id: id)
                            case .hist(let id): HistFlightView(id: id)
                            }
                        }
                }
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
