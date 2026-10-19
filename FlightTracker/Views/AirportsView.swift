import SwiftUI

/// FAA status for every US airport with a ground stop, delay program, closure or delay trend.
struct AirportsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let d = store.airportsStatus
        let list = d["airports"].array.sorted { rank($0) != rank($1) ? rank($0) < rank($1) : ($0["mine"].bool != $1["mine"].bool ? $0["mine"].bool : ($0["code"].string ?? "") < ($1["code"].string ?? "")) }
        let major = list.filter { rank($0) < 2 }, minor = list.filter { rank($0) == 2 }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Airports").font(.system(size: 32, weight: .bold))
                    Spacer()
                    RoundButton(symbol: "xmark") { dismiss() }
                }
                .padding(.top, 18)
                Text("FAA status for every US airport with a ground stop, delay program, closure or delay trend" + (d["at"].date.map { " · updated \(Fmt.ago($0))" } ?? "") + ".")
                    .font(.subheadline).foregroundStyle(Th.muted)
                if !major.isEmpty {
                    Text("Major Issues").font(.system(size: 21, weight: .bold)).padding(.top, 10)
                    ForEach(Array(major.enumerated()), id: \.offset) { _, a in row(a) }
                }
                if !minor.isEmpty {
                    Text("Minor Issues").font(.system(size: 21, weight: .bold)).padding(.top, 10)
                    ForEach(Array(minor.enumerated()), id: \.offset) { _, a in row(a) }
                }
                if list.isEmpty && !d.isNull {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("All clear").font(.headline)
                        Text("No FAA ground stops, delay programs, closures or delay trends right now.").foregroundStyle(Th.muted)
                    }
                    .card()
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 100)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await store.loadAirports()
        }
        .refreshable { await store.loadAirports() }
    }

    private func rank(_ a: JSON) -> Int {
        let kinds = a["items"].array.compactMap { $0["kind"].string }
        return kinds.contains { $0 == "gs" || $0 == "closure" } ? 0 : kinds.contains("gdp") ? 1 : 2
    }

    private func row(_ a: JSON) -> some View {
        let r = rank(a), c = r < 2 ? Th.red : Th.amber
        let ap = Airport(j: a)
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Circle().fill(c).frame(width: 12, height: 12)
                Text(a["code"].string ?? "").font(.system(size: 13, weight: .heavy))
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(ap.short).font(.system(size: 17, weight: .semibold))
                    if a["mine"].bool { Tag(text: "YOUR FLIGHT", color: Th.accent) }
                }
                ForEach(Array(a["items"].array.enumerated()), id: \.offset) { _, n in
                    let when = n["end"].date.map { e in (n["start"].date.map { $0 > Date() ? Fmt.time($0, ap.timeZone) + "–" : "until " } ?? "until ") + Fmt.time(e, ap.timeZone) } ?? ""
                    let sub = [n["detail"].string, n["reason"].string?.capitalized, when.isEmpty ? nil : when].compactMap { $0 }.joined(separator: " · ")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(n["label"].string ?? "").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(["gs", "closure"].contains(n["kind"].string ?? "") ? Th.red : n["kind"].string == "gdp" ? Color(hex: 0xFF8A5C) : .white)
                        if !sub.isEmpty { Text(sub).font(.system(size: 13)).foregroundStyle(Th.muted) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Th.line).frame(height: 0.5) }
    }
}
