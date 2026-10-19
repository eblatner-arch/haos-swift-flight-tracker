import SwiftUI

/// My Flights: upcoming and in progress, then recent.
struct FlightsList: View {
    @Environment(Store.self) private var store
    @Binding var showSettings: Bool

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
                        NavigationLink(value: leg.id) { FlightRow(leg: leg) }
                    }
                }
            }
            if !store.recent.isEmpty {
                Section("Recent") {
                    ForEach(store.recent.prefix(10)) { leg in
                        NavigationLink(value: leg.id) { FlightRow(leg: leg) }
                    }
                }
            }
            if store.legs.isEmpty && !store.loading && store.error == nil {
                Text("No flights in your schedule").foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("My Flights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            ToolbarItem(placement: .topBarLeading) {
                if store.loading { ProgressView() }
            }
        }
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
                Text(leg.status.isEmpty ? leg.phase.capitalized : leg.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let g = leg.depGate { Text("Gate \(g)").font(.caption.weight(.semibold)) }
            }
        }
        .padding(.vertical, 4)
    }
}
