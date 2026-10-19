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

/// The map fills the screen; your flights sit in a sheet over it, like Flighty. Opening a flight
/// pushes its page in the sheet and puts its route on the map.
struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [String] = []
    @State private var detent: PresentationDetent = .fraction(0.45)
    @State private var showSettings = false

    var body: some View {
        FlightMap(selectedID: path.last)
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                NavigationStack(path: $path) {
                    FlightsList(showSettings: $showSettings)
                        .navigationDestination(for: String.self) { id in
                            FlightDetail(id: id)
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
                if let id = UserDefaults.standard.string(forKey: "openLeg"), !id.isEmpty { path = [id] }
                while !Task.isCancelled {
                    await store.refresh()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.refresh() } }
            }
            // flighttracker://leg/<id> (from a notification): open that flight
            .onOpenURL { url in
                guard url.scheme == "flighttracker" else { return }
                if url.host == "leg", let id = url.pathComponents.last, id != "/" {
                    path = [id]
                    detent = .fraction(0.45)
                } else {
                    path = []
                }
            }
            .onChange(of: path) { _, _ in store.focus(.fit) }
    }
}
