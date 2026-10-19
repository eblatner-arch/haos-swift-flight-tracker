import SwiftUI

/// A ground stop or delay program on its own page, with its map: the en-route centers whose
/// departures it holds (shaded), the program's airport, and where your flights depart.
struct NasProgramView: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav
    let key: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let g = store.nasGroup(key) {
                    let n = g.n
                    DetailHeader(badge: "FAA", sub: "FAA", title: "\(g.airport) \(n["label"].string ?? "")") { nav.back() }
                    NasAlertCard(g: g, startOpen: true, showMapLink: false)
                    let scope = n["scope"].array.compactMap { $0.string }
                    let other = scope.filter { $0.range(of: #"^Z[A-Z]{2}$"#, options: .regularExpression) == nil }
                    Text("Shaded: the en-route centers whose departures this \(g.kind == "gs" ? "ground stop" : "program") holds."
                         + (other.isEmpty ? "" : " Also: \(other.joined(separator: ", ")).")
                         + (store.artcc.isNull ? " (Center boundaries are loading.)" : ""))
                        .font(.subheadline).foregroundStyle(Th.muted).card()
                } else {
                    DetailHeader(badge: "FAA", sub: "FAA", title: "Program ended") { nav.back() }
                    Text("It's no longer in the FAA's list.").foregroundStyle(Th.muted).card()
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 100)
            .sheetScroll()
        }
        .task {
            await store.loadArtcc()
            if store.nasGroup(key) == nil { await store.loadAirports() }
            store.focus(.fit)
        }
    }
}
