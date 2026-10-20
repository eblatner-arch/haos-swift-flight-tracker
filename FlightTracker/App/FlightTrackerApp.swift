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
    case nas(String)             // an FAA program (ground stop, delay program) by its key
    case find(String)            // search your flights, with filters ("st=late15&sort=late")
    case stats(String)           // Flight Stats for a year ("" = all)
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
    @State private var nav = Nav()
    @State private var tab: Tab = .flights
    @State private var stop: SheetStop = .mid
    @State private var sheet = SheetState()
    @State private var showSettings = false
    @State private var showAdd = false

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height, inset = safeTop()
            let ys = stops(H, inset)
            // where routes are framed: the open map above the sheet's middle stop, clear of the buttons
            // follows the sheet: pulled down to the peek, the routes get the taller space (full keeps the middle's)
            let sheetY = (stop == .full ? ys[.mid] : ys[stop]) ?? H * 0.45
            let area = CGRect(x: 18, y: inset + 50, width: W - 18 - 74, height: max(120, sheetY - inset - 50 - 24))
            ZStack(alignment: .top) {
                FlightMap(route: nav.path.last, tab: tab, screen: geo.size, area: area, covered: stop == .full)
                MapButtons(route: nav.path.last, airports: { open(.airports) })
                    .padding(.top, inset + 8)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Telemetry(route: nav.path.last).padding(.top, inset)
                StatusPills(openSettings: { showSettings = true })
                    .padding(.top, inset + 6).padding(.leading, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // the sheet keeps its own drag state, so moving it doesn't redraw the map
                SheetHost(stop: $stop, ys: ys, height: H - ys[.full]!) {
                    pageContent
                }
                VStack {
                    Spacer()
                    TabBar(tab: Binding(get: { tab }, set: { t in tab = t; nav.path = []; setStop(.mid) }),
                           search: { nav.path = [.find("")]; setStop(.full) })
                        .padding(.bottom, max(8, safeBottom() - 14))
                }
            }
            .onAppear { sheet.fullTop = ys[.full]! + 16 }
            .onChange(of: H) { _, _ in sheet.fullTop = ys[.full]! + 16 }
        }
        .ignoresSafeArea()
        .environment(sheet)
        .environment(nav)
        .sheet(isPresented: $showSettings) { SettingsView(addFlight: { showSettings = false; showAdd = true }) }
        .sheet(isPresented: $showAdd) { AddFlightView(opened: { id in showAdd = false; tab = .flights; open(.leg(id), force: true) }) }
        .task {
            if API.base == nil { showSettings = true }
            // testing: launched with -openLeg <id> opens that flight
            if let id = UserDefaults.standard.string(forKey: "openLeg"), !id.isEmpty { nav.path = [.leg(id)] }
            if UserDefaults.standard.string(forKey: "openTab") == "passport" { tab = .passport }
            if let k = UserDefaults.standard.string(forKey: "openNas"), !k.isEmpty { nav.path = [.nas(k)] }
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
                open(.leg(id), force: true)
                Task { await store.refresh() }
            } else {
                nav.path = []
            }
        }
        .onChange(of: nav.path) { old, new in
            store.focus(.fit)
            if new.count > old.count || new.isEmpty != old.isEmpty { setStop(wantStop(new.last)) }
        }
        .onChange(of: tab) { _, _ in store.focus(.fit) }
    }

    @ViewBuilder private var pageContent: some View {
        if let r = nav.path.last {
            page(r).id(r)
        } else {
            HomeView(tab: $tab, showSettings: $showSettings, showAdd: $showAdd, open: { open($0) })
        }
    }

    /// open a page (ignored right after the sheet was dragged: the finger was moving it, not tapping)
    private func open(_ r: Route, force: Bool = false) {
        guard force || !nav.suppressed else { return }
        nav.path = [r]
        setStop(wantStop(r))
    }

    /// where a page opens: lists you came to read (search, stats) open all the way, the rest halfway
    private func wantStop(_ r: Route?) -> SheetStop {
        switch r {
        case .find?, .stats?: return .full
        default: return .mid
        }
    }

    private func setStop(_ s: SheetStop) {
        guard s != stop else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { stop = s }
    }

    @ViewBuilder private func page(_ r: Route) -> some View {
        switch r {
        case .leg(let id): FlightDetail(id: id)
        case .hist(let id): HistFlightView(id: id)
        case .aircraft(let id, let n): AircraftLegView(id: id, n: n)
        case .airports: AirportsView()
        case .nas(let key): NasProgramView(key: key)
        case .find(let f): FindView(preset: f)
        case .stats(let y): StatsView(year: y)
        }
    }

    /// where the sheet's top sits at each stop
    private func stops(_ H: CGFloat, _ inset: CGFloat) -> [SheetStop: CGFloat] {
        let midF: CGFloat = nav.path.isEmpty ? (tab == .passport ? 0.58 : 0.42) : 0.5
        return [.full: inset + 6, .mid: H * midF, .peek: H - 190]
    }

    private func safeTop() -> CGFloat { keyWindow()?.safeAreaInsets.top ?? 47 }
    private func safeBottom() -> CGFloat { keyWindow()?.safeAreaInsets.bottom ?? 34 }
    private func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
    }
}

/// The sheet itself: grabber and page, its position, and the drag that moves it.
struct SheetHost<Content: View>: View {
    @Environment(SheetState.self) private var sheet
    @Environment(Nav.self) private var nav
    @Binding var stop: SheetStop
    let ys: [SheetStop: CGFloat]
    let height: CGFloat
    @ViewBuilder var content: Content
    @State private var drag: CGFloat = 0
    @State private var dragging = false
    /// the keyboard's height over the sheet (the screen ignores the keyboard, so the page makes room itself)
    @State private var kb: CGFloat = 0

    var body: some View {
        let y = max(ys[.full]!, (ys[stop] ?? 300) + drag)
        VStack(spacing: 0) {
            Capsule().fill(Color.white.opacity(0.28)).frame(width: 40, height: 5).padding(.top, 8).padding(.bottom, 3)
                .frame(maxWidth: .infinity).contentShape(Rectangle())
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .scrollDisabled(stop != .full || dragging)
                .scrollDismissesKeyboard(.interactively)
                .padding(.bottom, kb)
        }
        .frame(height: height, alignment: .top)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { n in
            guard let f = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let h = max(0, UIScreen.main.bounds.height - f.minY)
            let dur = (n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
            let to = h > 0 ? max(0, h - 60) : 0
            guard abs(to - kb) > 1 || (h > 0 && stop != .full) else { return }
            // typing: the whole page, above the keyboard, moving with it
            withAnimation(.easeOut(duration: max(0.2, dur))) {
                kb = to
                if h > 0, stop != .full { stop = .full; drag = 0 }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            if kb > 0 { withAnimation(.easeOut(duration: 0.25)) { kb = 0 } }
        }
        .background(Th.sheet)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous))
        // a soft edge above the sheet, drawn once (a live shadow re-renders the whole sheet every frame it moves)
        .background(alignment: .top) {
            LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .top, endPoint: .bottom)
                .frame(height: 22).offset(y: -20).allowsHitTesting(false)
        }
        .offset(y: y)
        .simultaneousGesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { v in
                if !dragging {
                    guard abs(v.translation.height) > abs(v.translation.width) * 1.2 else { return }
                    // full: the page scrolls, unless it's at its top and you pull down
                    if stop == .full && !(sheet.atTop && v.translation.height > 0) { return }
                    dragging = true
                }
                nav.suppressUntil = Date().addingTimeInterval(0.4)   // this touch moved the sheet: not a tap
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { drag = v.translation.height }
            }
            .onEnded { v in
                guard dragging else { return }
                nav.suppressUntil = Date().addingTimeInterval(0.4)
                if v.translation.height > 0 { hideKeyboard() }
                let aim = (ys[stop] ?? 0) + v.predictedEndTranslation.height
                let target = [SheetStop.full, .mid, .peek].min { abs((ys[$0] ?? 0) - aim) < abs((ys[$1] ?? 0) - aim) } ?? stop
                let cur = (ys[stop] ?? 0) + v.translation.height
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { stop = target; drag = cur - (ys[target] ?? 0) }
                dragging = false
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { drag = 0 }
            }
    }
}

/// The sheet's pages: what you opened, on top of My Flights / Alerts / Passport.
@Observable
final class Nav {
    var path: [Route] = []
    /// taps are ignored until then (the finger that just moved the sheet lifted over a row)
    var suppressUntil: Date { get { Nav.blockUntil } set { Nav.blockUntil = newValue } }
    var suppressed: Bool { Nav.blocked }
    /// shared by every button in the sheet: a touch that moved the sheet isn't a tap
    static var blockUntil = Date.distantPast
    static var blocked: Bool { Date() < blockUntil }
    func push(_ r: Route) { if !suppressed { path.append(r) } }
    func back() { _ = path.popLast() }
}

enum SheetStop { case full, mid, peek }

/// Shared with the pages in the sheet: where their scrolling content's top is, so a pull down at
/// the top of a page moves the sheet instead.
@Observable
final class SheetState {
    // read only by the drag (never drawn), so scrolling doesn't redraw anything
    @ObservationIgnored var contentTop: CGFloat = 0
    @ObservationIgnored var fullTop: CGFloat = 0
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
            if let leg = pageLeg {
                if leg.position != nil || isFlying { button("airplane") { store.focus(.plane) } }
                if let c = leg.dep.coordinate { button("airplane.departure") { store.focus(.area(lat: c.latitude, lon: c.longitude, km: 2.2)) } }
                if let c = leg.arr.coordinate { button("airplane.arrival") { store.focus(.area(lat: c.latitude, lon: c.longitude, km: 2.2)) } }
            }
        }
        .padding(.trailing, 12)
    }

    /// the flight this page is about: yours, an earlier leg of its airplane, or one from your Passport
    private var pageLeg: Leg? {
        switch route {
        case .leg(let id)?: return store.leg(id)
        case .aircraft(let id, let n)?: return store.rotationLeg(id, n)
        case .hist(let id)?: return store.histDetails[id].map(HistFlightView.leg)
        default: return nil
        }
    }
    private var isFlying: Bool { ["airborne", "taxi_out"].contains(pageLeg?.phase ?? "") }

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
                HStack(spacing: 4) {
                    Image(systemName: "speedometer").font(.system(size: 11)).foregroundStyle(Th.muted)
                    Text("\(Int(gs * 1.15078).formatted())").font(.system(size: 13, weight: .bold))
                    Text("MPH").font(.system(size: 9, weight: .bold)).foregroundStyle(Th.muted)
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.to.line").font(.system(size: 11)).foregroundStyle(Th.muted)
                    Text(lv.altitude.map { Int($0).formatted() } ?? "—").font(.system(size: 13, weight: .bold))
                    Text("FT").font(.system(size: 9, weight: .bold)).foregroundStyle(Th.muted)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Color(hex: 0x26262A, alpha: 0.94), in: Capsule())
            // under the Live and Drive pills, clear of them and the round buttons
            .padding(.top, 40)
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


/// put the keyboard away (pulling the sheet down, or a tap outside the field)
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
