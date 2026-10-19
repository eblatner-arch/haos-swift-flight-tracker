import SwiftUI

/// The sheet's first page: My Flights, Alerts or Passport.
struct HomeView: View {
    @Environment(Store.self) private var store
    @Binding var tab: Tab
    @Binding var showSettings: Bool
    let open: (Route) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            switch tab {
            case .flights: FlightsList()
            case .alerts: AlertsView(open: open)
            case .passport: PassportView()
            }
        }
        .navigationTitle(tab.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            ToolbarItem(placement: .topBarLeading) {
                if store.loading { ProgressView() }
            }
        }
    }
}

/// My Flights: upcoming and in progress, then recent.
struct FlightsList: View {
    @Environment(Store.self) private var store

    var body: some View {
        List {
            if store.offline || store.error != nil {
                Section {
                    Label(store.error ?? "Offline: showing the last copy on this phone", systemImage: store.offline ? "wifi.slash" : "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(store.offline ? Color.secondary : Color.orange)
                }
            }
            if !store.upcoming.isEmpty {
                Section("Upcoming") {
                    ForEach(store.upcoming) { leg in
                        NavigationLink(value: Route.leg(leg.id)) { FlightRow(leg: leg) }
                    }
                }
            }
            if !store.recent.isEmpty {
                Section("Recent") {
                    ForEach(store.recent.prefix(10)) { leg in
                        NavigationLink(value: Route.leg(leg.id)) { FlightRow(leg: leg) }
                    }
                }
            }
            if store.legs.isEmpty && !store.loading && store.error == nil {
                Text("No flights in your schedule").foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.refresh() }
    }
}

struct FlightRow: View {
    let leg: Leg

    var body: some View {
        let late = leg.out.lateMinutes
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(leg.display).font(.subheadline.weight(.semibold))
                if leg.deadhead { Text("DH").font(.caption2.weight(.bold)).padding(.horizontal, 5).background(.gray.opacity(0.3), in: Capsule()) }
                Spacer()
                Text(Fmt.day(leg.out.best, leg.dep.timeZone)).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(leg.dep.code).font(.title2.weight(.bold))
                    Text(Fmt.time(leg.out.best, leg.dep.timeZone)).font(.caption).foregroundStyle(Fmt.lateColor(late))
                }
                Spacer()
                Image(systemName: "airplane").foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(leg.arr.code).font(.title2.weight(.bold))
                    Text(Fmt.time(leg.inn.best, leg.arr.timeZone)).font(.caption).foregroundStyle(Fmt.lateColor(leg.inn.lateMinutes))
                }
            }
            HStack {
                Text(StatusLine(leg).head).font(.caption).foregroundStyle(StatusLine(leg).tone ?? .secondary)
                Spacer()
                if let g = leg.depGate { Text("Gate \(g)").font(.caption.weight(.semibold)) }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Alerts the add-on sent (gate changes, delays, departures...), newest first.
struct AlertsView: View {
    @Environment(Store.self) private var store
    let open: (Route) -> Void

    var body: some View {
        List {
            if store.alerts.isEmpty {
                Text("No alerts yet").foregroundStyle(.secondary)
            }
            ForEach(Array(store.alerts.prefix(150).enumerated()), id: \.offset) { _, a in
                let leg = a["leg"].string
                Button {
                    if let leg { open(.leg(leg)) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(color(a["level"].string)).frame(width: 9, height: 9).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(a["title"].string ?? "Alert").font(.subheadline.weight(.semibold))
                            if let m = a["message"].string { Text(m).font(.subheadline).foregroundStyle(.secondary) }
                            Text(Fmt.relative(a["at"].date)).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .task { await store.loadAlerts() }
        .refreshable { await store.loadAlerts() }
    }

    private func color(_ level: String?) -> Color {
        switch level {
        case "critical": return .red
        case "warn": return .orange
        default: return .blue
        }
    }
}

/// Passport: everything you've flown, by year.
struct PassportView: View {
    @Environment(Store.self) private var store

    var body: some View {
        let d = store.passport, st = d["stats"]
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        chip("All-Time", nil)
                        ForEach(d["years"].array.compactMap { $0.string }, id: \.self) { y in chip(y, y) }
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            if !st.isNull {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                        stat("Flights", st["flights"].int.map { $0.formatted() } ?? "–", st["routes"].int.map { "\($0) routes" })
                        stat("Distance", st["distance_nm"].double.map { "\(Int($0 * 1.15078).formatted()) mi" } ?? "–",
                             st["distance_nm"].double.map { String(format: "%.1fx around the world", $0 / 21639) })
                        stat("Flight time", st["block_hours"].double.map { "\(Int($0) / 24)d \(Int($0) % 24)h" } ?? "–", "gate to gate")
                        stat("Airports", st["airports"].int.map { "\($0)" } ?? "–", st["tails"].int.map { "\($0) tails" })
                        stat("On time", st["on_time_pct"].int.map { "\($0)%" } ?? "–", st["avg_arr_delay"].double.map { String(format: "avg %.0f min late", $0) })
                        if let top = st["top_aircraft"][0][0].string {
                            stat("Most flown", top, st["top_aircraft"][0][1].int.map { "\($0) flights" })
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            Section("Flights") {
                ForEach(Array(d["flights"].array.prefix(300).enumerated()), id: \.offset) { _, f in
                    if let id = f["id"].string {
                        NavigationLink(value: Route.hist(id)) { PassRow(f: f) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .task(id: store.passYear) { await store.loadPassport() }
        .refreshable { await store.loadPassport() }
    }

    private func chip(_ label: String, _ year: String?) -> some View {
        Button(label) { store.passYear = year }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(store.passYear == year ? Color.route : Color.card, in: Capsule())
            .buttonStyle(.plain)
    }

    private func stat(_ k: String, _ v: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(v).font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
            if let sub { Text(sub).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct PassRow: View {
    let f: JSON
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(f["display"].string ?? "Flight").font(.subheadline.weight(.semibold))
                    Text("\(f["dep"].string ?? "?") → \(f["diverted_to"].string ?? f["arr"].string ?? "?")").font(.subheadline).foregroundStyle(.secondary)
                    if f["cancelled"].bool { Text("CANCELLED").font(.caption2.weight(.bold)).foregroundStyle(.red) }
                }
                Text([f["aircraft"].string, f["tail"].string].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(f["date"].string ?? "").font(.caption).foregroundStyle(.secondary)
        }
    }
}
