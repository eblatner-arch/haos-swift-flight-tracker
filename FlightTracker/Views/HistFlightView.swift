import SwiftUI

/// A flight from your Passport: the route flown, the four times, the airplane.
struct HistFlightView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: String

    var body: some View {
        Group {
            if let f = store.histDetails[id] {
                let a = Airport(j: f["dep_ap"]), b = Airport(j: f["arr_ap"])
                let t = f["times"]
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        DetailHeader(badge: f["airline"].string == "UAL" ? "UA" : (f["airline"].string ?? ""),
                                     sub: "\(f["display"].string ?? "Flight") • \(f["date"].string ?? "")", title: "\(a.city) to \(b.city)") { dismiss() }
                        if f["cancelled"].bool { StatusBanner(status: StatusLine.fixed("Cancelled", "", .red)) }
                        else if let d = f["diverted_to"].string { StatusBanner(status: StatusLine.fixed("Diverted to \(d)", "", .red)) }
                        else if let m = f["arr_delay"].int {
                            StatusBanner(status: StatusLine.fixed(abs(m) < 5 ? "Arrived on time" : m > 0 ? "Arrived \(Fmt.span(Double(m * 60))) late" : "Arrived \(Fmt.span(Double(-m * 60))) early", "", Fmt.lateColor(m)))
                        }
                        VStack(spacing: 8) {
                            row("Gate departure", t["out"], a.timeZone)
                            row("Takeoff", t["off"], a.timeZone)
                            row("Landing", t["on"], b.timeZone)
                            row("Gate arrival", t["in"], b.timeZone)
                        }
                        .padding(14)
                        .background(Th.card, in: RoundedRectangle(cornerRadius: Th.radius, style: .continuous))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Details").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            kv("Gates", [f["dep_gate"].string, f["arr_gate"].string].map { $0 ?? "–" }.joined(separator: " → "))
                            kv("Aircraft", [f["aircraft"].string, f["tail"].string].compactMap { $0 }.joined(separator: " · "))
                            if let nm = f["distance_nm"].double { kv("Distance", "\(Int(nm * 1.15078).formatted()) mi") }
                            if let bm = f["block_min"].double { kv("Gate to gate", Fmt.span(bm * 60)) }
                            if let am = f["air_min"].double { kv("In the air", Fmt.span(am * 60)) }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Th.card, in: RoundedRectangle(cornerRadius: Th.radius, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
            .sheetScroll()
                }
            } else {
                ProgressView()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: id) { await store.loadHist(id) }
    }

    private func row(_ label: String, _ x: JSON, _ tz: TimeZone) -> some View {
        let s = x["s"].date, act = x["a"].date
        let late = s.flatMap { s in act.map { Int(($0.timeIntervalSince(s) / 60).rounded()) } }
        return HStack {
            Text(label).frame(maxWidth: .infinity, alignment: .leading)
            Text(Fmt.time(s, tz)).foregroundStyle(.secondary).frame(width: 78, alignment: .trailing)
            Text(act != nil ? Fmt.time(act, tz) : "--").foregroundStyle(Fmt.lateColor(late)).frame(width: 78, alignment: .trailing)
        }
        .font(.subheadline.monospacedDigit())
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v)
        }
        .font(.subheadline)
    }
}

extension StatusLine {
    static func fixed(_ head: String, _ sub: String, _ tone: Color?) -> StatusLine { StatusLine(head: head, sub: sub, tone: tone) }
}
