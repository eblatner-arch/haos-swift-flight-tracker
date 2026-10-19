import SwiftUI

/// Flight Stats, like the web app's: totals, delays (by departure hour, worst routes), most flown
/// routes, airports, aircraft and tails, and records. Every row opens Find with that filter.
struct StatsView: View {
    @Environment(Nav.self) private var nav
    let year: String
    @State private var y: String = ""
    @State private var d: JSON = .null

    var body: some View {
        let st = d["stats"]
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Flight Stats").font(.system(size: 32, weight: .bold)).tracking(-0.5)
                    Spacer()
                    RoundButton(symbol: "xmark") { nav.back() }
                }
                .padding(.top, 18)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([""] + d["years"].array.compactMap { $0.string }, id: \.self) { v in
                            Button { if Nav.blocked { return }; y = v } label: {
                                Text(v.isEmpty ? "All" : v).font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(v == y ? .white : Th.muted)
                                    .padding(.horizontal, 16).padding(.vertical, 8)
                                    .background(v == y ? Th.accent : .clear, in: Capsule())
                                    .overlay(Capsule().stroke(v == y ? .clear : Th.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if d.isNull {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                } else if (st["flights"].int ?? 0) == 0 {
                    Text("No flights yet.").foregroundStyle(Th.muted).card()
                } else {
                    content(st)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 100)
            .sheetScroll()
        }
        .onAppear { if y.isEmpty { y = year } }
        .task(id: y) {
            if let r = try? await API.get("api/history" + (y.isEmpty ? "" : "?year=\(y)")) { d = r.0 }
        }
    }

    @ViewBuilder private func content(_ st: JSON) -> some View {
        let n = { (k: String) in st[k].double }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            tile("Flights", "\(st["flights"].int ?? 0)", (st["diverted"].int ?? 0) > 0 ? "\(st["diverted"].int!) diverted" : nil, (st["diverted"].int ?? 0) > 0 ? "st=diverted" : nil)
            tile("Distance", "\(Int(n("distance_nm") ?? 0).formatted()) nm", String(format: "%.1f× around the world", (n("distance_nm") ?? 0) / 21639), nil)
            tile("In the air", "\(Int(n("air_hours") ?? 0).formatted()) h", "\(Int(n("block_hours") ?? 0).formatted()) h gate to gate", nil)
            tile("Airports", "\(st["airports"].int ?? 0)", "\(st["routes"].int ?? 0) routes · \(st["tails"].int ?? 0) tails", nil)
        }
        Text("Delays").font(.system(size: 24, weight: .bold)).padding(.top, 10)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            tile("On time", st["on_time_pct"].int.map { "\($0)%" } ?? "—", "at the gate, under 15 min late", "st=ontime")
            tile("Avg arrival", n("avg_arr_delay").map { "\(mins($0)) min" } ?? "—", "vs schedule (− is early) · departure \(n("avg_dep_delay").map(mins) ?? "—") min", "sort=late")
            tile("Early", st["early_pct"].int.map { "\($0)%" } ?? "—", "5+ min early", "st=early")
            tile("30+ late", st["late_30_pct"].int.map { "\($0)%" } ?? "—", nil, "st=late30")
        }
        barCard("Average arrival delay by scheduled departure time", signed: true,
                st["by_hour"].array.map { r in (r[0].string ?? "", r[2].double ?? 0, " · \(r[1].int ?? 0)", "hr=\(r[0].string ?? "")&sort=late") })
        let lr = st["late_routes"].array
        if !lr.isEmpty {
            barCard("Most delayed routes (3+ flights)", signed: true, lr.map { r in
                let k = r[0].string ?? ""
                return (k, r[2].double ?? 0, " · \(r[1].int ?? 0) · \(Int(((r[3].double ?? 0) * 100).rounded()))% on time", "route=\(k.replacingOccurrences(of: "–", with: "-"))&sort=late")
            })
        }
        Text("Most flown").font(.system(size: 24, weight: .bold)).padding(.top, 10)
        barCard("Routes", signed: false, top(st["top_routes"]) { "route=" + $0.replacingOccurrences(of: "–", with: "-") })
        barCard("Airports", signed: false, top(st["top_airports"]) { "ap=" + $0 })
        barCard("Aircraft", signed: false, top(st["top_aircraft"]) { "ac=" + $0 })
        barCard("Tails", signed: false, top(st["top_tails"]) { "tail=" + $0 })
        if !st["longest"].isNull || !st["worst_delay"].isNull {
            Text("Records").font(.system(size: 24, weight: .bold)).padding(.top, 10)
            VStack(alignment: .leading, spacing: 4) {
                if !st["longest"].isNull {
                    Text("Longest · \(Int(st["longest"]["distance_nm"].double ?? 0).formatted()) nm").font(.subheadline).foregroundStyle(Th.muted)
                    record(st["longest"])
                }
                if !st["worst_delay"].isNull {
                    Text("Latest arrival · \(st["worst_delay"]["arr_delay"].int ?? 0) min").font(.subheadline).foregroundStyle(Th.muted).padding(.top, 8)
                    record(st["worst_delay"])
                }
            }
            .card()
        }
    }

    private func mins(_ m: Double) -> String { let r = Int(m.rounded()); return r > 0 ? "+\(r)" : "\(r)" }

    private func top(_ j: JSON, _ link: (String) -> String) -> [(String, Double, String, String?)] {
        j.array.map { r in let k = r[0].string ?? ""; return (k, r[1].double ?? 0, "", link(k)) }
    }

    /// a Find link with the year being viewed
    private func find(_ q: String) {
        let enc = q.split(separator: "&").map { part -> String in
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { return String(part) }
            return "\(kv[0])=\(String(kv[1]).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? String(kv[1]))"
        }.joined(separator: "&")
        nav.push(.find((y.isEmpty ? "" : "year=\(y)&") + enc))
    }

    private func tile(_ k: String, _ v: String, _ sub: String?, _ link: String?) -> some View {
        Button { if Nav.blocked { return }; if let link { find(link) } } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(k.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(1).foregroundStyle(Th.muted)
                Text(v).font(.system(size: 26, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                if let sub { Text(sub).font(.system(size: 14)).foregroundStyle(Th.muted).fixedSize(horizontal: false, vertical: true) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(14)
            .background(Th.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(link == nil)
    }

    private func barCard(_ title: String, signed: Bool, _ rows: [(String, Double, String, String?)]) -> some View {
        let mx = max(1, rows.map { abs($0.1) }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 15)).foregroundStyle(Th.muted)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                Button { if Nav.blocked { return }; if let l = r.3 { find(l) } } label: {
                    HStack(spacing: 10) {
                        Text(r.0 + (r.3 != nil ? " ›" : "")).font(.system(size: 15, weight: .bold)).lineLimit(1).truncationMode(.tail)
                            .frame(width: 110, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Th.card2)
                                Capsule().fill(signed ? (r.1 >= 1 ? Th.amber : r.1 <= -1 ? Th.green : Th.muted) : Th.accent)
                                    .frame(width: max(8, g.size.width * abs(r.1) / mx))
                            }
                        }
                        .frame(height: 8)
                        (Text(signed ? mins(r.1) + "m" : "\(Int(r.1))").font(.system(size: 15, weight: .bold))
                         + Text(r.2).font(.system(size: 12)).foregroundColor(Th.faint))
                            .lineLimit(1).fixedSize()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func record(_ f: JSON) -> some View {
        Button { if Nav.blocked { return }; if let id = f["id"].string { nav.push(.hist(id)) } } label: { FindRow(f: f) }.buttonStyle(.plain)
    }
}
