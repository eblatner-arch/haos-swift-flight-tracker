import SwiftUI

/// A flight from your Passport, laid out like a flight page: both ends, the four times and where each
/// came from, the airplane, the route's record, where the record came from, and Delete.
struct HistFlightView: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav
    let id: String
    @State private var confirmDelete = false
    @State private var failed = false

    var body: some View {
        Group {
            if let f = store.histDetails[id] {
                let P = Self.leg(f)
                let am = f["arr_delay"].int
                let cont = !f["continuation_of"].isNull
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        DetailHeader(badge: P.airlineCode, sub: "\(P.display.replacingOccurrences(of: P.airlineCode, with: P.airlineCode + " ")) • \(Fmt.day(P.out.best, P.dep.timeZone).uppercased())",
                                     title: "\(P.dep.city) to \(P.arr.city)") { nav.back() }
                        StatusBanner(status: banner(f, am, cont)).padding(.horizontal, -14)
                        if let c = f["continued_by"].string {
                            Button { if Nav.blocked { return }; nav.push(.hist(c)) } label: { Text((f["continued_by_label"].string ?? "Continuation") + " ›").foregroundStyle(Th.accent) }.buttonStyle(.plain)
                        }
                        if let c = f["continuation_of"].string {
                            Button { if Nav.blocked { return }; nav.push(.hist(c)) } label: { Text((f["continuation_of_label"].string ?? "Original flight") + " ›").foregroundStyle(Th.accent) }.buttonStyle(.plain)
                        }
                        EndpointView(leg: P, departure: true)
                        MidLine(leg: P)
                        EndpointView(leg: P, departure: false)
                        TimesCard(leg: P)
                        AircraftCard(leg: P)
                        details(f)
                        Button { if Nav.blocked { return }; confirmDelete = true } label: {
                            Text(failed ? "Couldn't delete it. Try again" : "Delete from History").font(.system(size: 16, weight: .semibold)).foregroundStyle(Th.red)
                                .padding(.horizontal, 15).padding(.vertical, 10)
                                .background(Th.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 100)
                    .sheetScroll()
                }
                .confirmationDialog("Delete this flight from History?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        Task { if await store.deleteHist(id) { nav.back() } else { failed = true } }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: id) { await store.loadHist(id) }
    }

    private func banner(_ f: JSON, _ am: Int?, _ cont: Bool) -> StatusLine {
        let head = f["cancelled"].bool ? "Cancelled" : f["diverted_to"].string.map { "Diverted to \($0)" } ?? (am == nil ? "Completed" : "Arrived \(Fmt.lateLower(am))")
        let tone: Color? = f["cancelled"].bool || f["diverted_to"].string != nil ? Th.red : am == nil ? nil : ((am ?? 0) >= 5 ? Th.amber : Th.green)
        var sub: [String] = []
        if f["diverted_to"].string != nil, let a = f["arr"].string { sub.append("Planned to \(a).") }
        if f["continued_by"].string != nil {
            let tz = f["arr_tz"].string.flatMap(TimeZone.init(identifier:)) ?? .current
            sub.append("Reached \(f["final_ap"].string ?? f["arr"].string ?? "") at \(Fmt.time(f["final_arrival"].date, tz))" + (am.map { ", \(Fmt.span(Double($0 * 60))) after the original schedule" } ?? "") + ".")
        }
        if cont { sub.append("Continuation of a diverted flight; its lateness is counted on that flight.") }
        return StatusLine(head: head, sub: sub.joined(separator: " "), tone: tone)
    }

    private func details(_ f: JSON) -> some View {
        let rs = f["route_stats"]
        var rows: [(String, String)] = []
        if let nm = f["distance_nm"].double { rows.append(("Distance", "\(Int(nm).formatted()) nm · \(Int(nm * 1.15078).formatted()) mi")) }
        if let bm = f["block_min"].double { rows.append(("Gate to gate", Fmt.span(bm * 60))) }
        rows.append(("In the air", f["air_min"].double.map { Fmt.span($0 * 60) } ?? "—"))
        if let n = rs["flights"].int {
            rows.append(("This route", "\(n) flight\(n == 1 ? "" : "s")" + (rs["on_time_pct"].int.map { " · \($0)% on time" } ?? "")
                         + (rs["avg_arr_delay"].double.map { " · avg \(Fmt.lateLower(Int($0.rounded())))" } ?? "")))
        }
        if let r = f["route"].string { rows.append(("Filed route", r)) }
        let src = f["source"].string == "flighty" ? "Flighty import" : "Tracked here" + (f["source"].string.map { " · \($0)" } ?? "")
        rows.append(("Source", src + (f["has_track"].bool ? " · flown track saved" : "")))
        if let a = f["added"].date { rows.append(("Saved", a.formatted(date: .abbreviated, time: .shortened))) }
        if let u = f["updated"].date { rows.append(("Updated", u.formatted(date: .abbreviated, time: .shortened))) }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .top) {
                    Text(r.0).foregroundStyle(Th.muted).frame(width: 110, alignment: .leading)
                    Text(r.1).font(r.0 == "Filed route" ? .system(size: 13, design: .monospaced) : .system(size: 15))
                }
                .font(.system(size: 15))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// The saved record as a finished flight, so it draws with the same cards as a live one.
    static func leg(_ f: JSON) -> Leg {
        let t = f["times"], cont = !f["continuation_of"].isNull
        func conv(_ x: JSON) -> JSON {
            x.isNull ? .object([:]) : .object(["scheduled": cont ? .null : x["s"], "actual": x["a"], "estimated": .null])
        }
        var src: [String: JSON] = [:]
        for k in ["out", "off", "on", "in"] where !t[k]["src"].isNull { src[k] = .object(["actual": t[k]["src"]]) }
        var dep = f["dep_ap"], arr = f["arr_ap"]
        if dep.isNull { dep = .object(["iata": f["dep"]]) }
        if arr.isNull { arr = .object(["iata": f["diverted_to"].isNull ? f["arr"] : f["diverted_to"]]) }
        if dep["tz"].isNull { dep.set("tz", f["dep_tz"]) }
        if arr["tz"].isNull { arr.set("tz", f["arr_tz"]) }
        let flight: JSON = .object([
            "times": .object(["out": conv(t["out"]), "off": conv(t["off"]), "on": conv(t["on"]), "in": conv(t["in"])]),
            "distance_nm": f["distance_nm"], "aircraft_name": f["aircraft"], "aircraft_type": f["type"], "tail": f["tail"],
            "origin": .object(["gate": f["dep_gate"], "terminal": f["dep_terminal"]]),
            "destination": .object(["gate": f["arr_gate"], "terminal": f["arr_terminal"]]),
            "time_src": .object(src), "track": f["track"],
        ])
        return Leg(j: .object([
            "id": f["id"], "dep_ap": dep, "arr_ap": arr, "phase": .string(f["cancelled"].bool ? "cancelled" : "arrived"),
            "finished": .bool(true), "source": .string(f["source"].string == "flighty" ? "Flighty import" : "FlightAware"),
            "sched_out": t["out"]["s"], "sched_in": t["in"]["s"], "display": f["display"], "ident": f["ident"],
            "airline": f["airline"], "flight": flight, "tail_count": f["tail_count"],
        ]))
    }
}

extension StatusLine {
    static func fixed(_ head: String, _ sub: String, _ tone: Color?) -> StatusLine { StatusLine(head: head, sub: sub, tone: tone) }
}
