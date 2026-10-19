import SwiftUI

/// Passport: everything you've flown, by year — the web app's cards, then the list.
struct PassportView: View {
    @Environment(Store.self) private var store
    @Binding var showSettings: Bool
    @State private var showAll = false
    @State private var query = ""
    @FocusState private var searching: Bool

    var body: some View {
        let d = store.passport, st = d["stats"]
        let all = d["flights"].array
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        let flights = q.isEmpty ? all : all.filter { f in
            [f["display"].string, f["dep"].string, f["arr"].string, f["diverted_to"].string, f["tail"].string, f["aircraft"].string, f["type"].string, f["date"].string]
                .compactMap { $0?.uppercased() }.contains { $0.contains(q) || $0.replacingOccurrences(of: " ", with: "").contains(q.replacingOccurrences(of: " ", with: "")) }
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetTitle(title: "Passport") { Avatar { showSettings = true } }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("All-Time", nil)
                        ForEach(d["years"].array.compactMap { $0.string }, id: \.self) { y in chip(y, y) }
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Th.muted)
                    TextField("Flight, airport, tail, aircraft, date", text: $query)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled().focused($searching)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Th.muted) }.buttonStyle(.plain) }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Th.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if !st.isNull && q.isEmpty {
                    PassCard(st: st, flights: flights, year: store.passYear)
                    DelayCard(flights: flights)
                    if let top = st["top_aircraft"][0][0].string { AircraftStatCard(name: top, count: st["top_aircraft"][0][1].int ?? 0) }
                }
                if !flights.isEmpty {
                    SectionHead(title: "Flights", trailing: "\(flights.count)")
                    VStack(spacing: 0) {
                        ForEach(Array(groups(flights).enumerated()), id: \.offset) { _, g in
                            HStack {
                                Text(g.0).font(.system(size: 17, weight: .bold))
                                Spacer()
                                Text("\(g.1.count) FLIGHT\(g.1.count == 1 ? "" : "S")").font(.caption.weight(.semibold)).foregroundStyle(Th.muted)
                            }
                            .padding(.top, 16).padding(.bottom, 6)
                            ForEach(Array(g.1.enumerated()), id: \.offset) { _, f in
                                if let id = f["id"].string {
                                    NavigationLink(value: Route.hist(id)) { PassRow(f: f) }.buttonStyle(.plain)
                                }
                            }
                        }
                        if !showAll && flights.count > 300 {
                            Button("Show all \(flights.count) flights") { showAll = true }
                                .font(.subheadline.weight(.semibold)).padding(.vertical, 12)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 90)
            .sheetScroll()
        }
        .task(id: store.passYear) { await store.loadPassport() }
        .onChange(of: store.searchRequest) { _, _ in searching = true }
        .onAppear { if store.searchRequest > 0 { searching = true } }
        .refreshable { await store.loadPassport() }
    }

    /// by year, newest first
    private func groups(_ fl: [JSON]) -> [(String, [JSON])] {
        let list = showAll ? fl : Array(fl.prefix(300))
        var order: [String] = [], by: [String: [JSON]] = [:]
        for f in list {
            let y = String((f["date"].string ?? "Undated").prefix(4))
            if by[y] == nil { order.append(y) }
            by[y, default: []].append(f)
        }
        return order.map { ($0, by[$0] ?? []) }
    }

    private func chip(_ label: String, _ year: String?) -> some View {
        Button(label) { store.passYear = year }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(store.passYear == year ? .white : Th.muted)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(store.passYear == year ? Th.card2 : .clear, in: Capsule())
            .buttonStyle(.plain)
    }
}

/// The blue Passport card: flights, distance, flight time, airports, airlines.
private struct PassCard: View {
    let st: JSON
    let flights: [JSON]
    let year: String?
    var body: some View {
        let n = st["flights"].int ?? 0
        let nm = st["distance_nm"].double ?? 0
        let hrs = st["block_hours"].double ?? st["air_hours"].double ?? 0
        let longHaul = flights.filter { ($0["distance_nm"].double ?? 0) * 1.15078 >= 3000 && !$0["cancelled"].bool }.count
        let airlines = Set(flights.compactMap { $0["airline"].string }).count
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(year ?? "All-Time") Passport".uppercased()).font(.system(size: 21, weight: .bold)).tracking(1.2)
                Text("PILOT LOGBOOK · \(n) FLIGHTS").font(.system(size: 12, weight: .semibold)).tracking(1).foregroundStyle(.white.opacity(0.6))
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                GridRow {
                    cell("Flights", n.formatted(), longHaul > 0 ? "\(longHaul) Long Haul" : "\(st["routes"].int ?? 0) routes")
                    cell("Distance", "\(Int(nm * 1.15078).formatted()) mi", String(format: "%.1fx around the world", nm / 21639))
                }
                GridRow {
                    cell("Flight Time", "\(Int(hrs) / 24)d \(Int(hrs.rounded()) % 24)h", "gate to gate")
                    HStack(alignment: .top, spacing: 18) {
                        cell("Airports", "\(st["airports"].int ?? 0)", nil)
                        cell("Airlines", "\(airlines)", nil)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: 0x0C1240), Color(hex: 0x1A2A8A), Color(hex: 0x3A5BD9)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func cell(_ k: String, _ v: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(0.8).foregroundStyle(.white.opacity(0.65))
            Text(v).font(.system(size: 25, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            if let sub { Text(sub).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7)) }
        }
    }
}

/// The red card: hours lost to delays.
private struct DelayCard: View {
    let flights: [JSON]
    var body: some View {
        let late = flights.filter { !$0["cancelled"].bool && ($0["arr_delay"].double ?? 0) >= 15 }
        let lost = late.reduce(0.0) { $0 + ($1["arr_delay"].double ?? 0) }
        if !late.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int((lost / 60).rounded()))").font(.system(size: 56, weight: .heavy))
                Text("hours lost from delays").font(.system(size: 20, weight: .semibold))
                Text("Delayed flights averaged \(Fmt.span(lost / Double(late.count) * 60)) late").font(.subheadline).foregroundStyle(Color(hex: 0xFF9C8F))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(hex: 0xB3261E), Color(hex: 0x5E0F0B)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

/// The light card: most flown aircraft, with its picture.
private struct AircraftStatCard: View {
    @Environment(Store.self) private var store
    let name: String
    let count: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Most flown aircraft").font(.system(size: 17, weight: .semibold))
            Text(name).font(.system(size: 26, weight: .regular)).lineLimit(1).minimumScaleFactor(0.7)
            Text("\(count) flights").font(.subheadline).opacity(0.7)
            if let key = acKey(nil, name), let first = store.liveries["types"][key][0].string, let u = API.url("api/livery/\(first).png") {
                AsyncImage(url: u) { $0.resizable().scaledToFit().shadow(color: Color(hex: 0x1D2A55).opacity(0.28), radius: 8, y: 6) } placeholder: { Color.clear.frame(height: 80) }
                    .padding(.top, 10)
            }
        }
        .foregroundStyle(Color(hex: 0x1D2A55))
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: 0xE3E6F6), Color(hex: 0xC5CAE8)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct PassRow: View {
    let f: JSON
    var body: some View {
        let al = f["airline"].string == "UAL" ? "UA" : (f["airline"].string ?? "")
        HStack(spacing: 12) {
            AirlineBadge(code: al, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text((f["display"].string ?? "Flight").replacingOccurrences(of: al, with: al + " ")).font(.system(size: 15, weight: .semibold))
                    Text("\(f["dep"].string ?? "?") → \(f["diverted_to"].string ?? f["arr"].string ?? "?")").font(.system(size: 15)).foregroundStyle(Th.muted)
                    if f["diverted_to"].string != nil { Text("DIVERTED").font(.caption2.weight(.bold)).foregroundStyle(Th.red) }
                    if f["cancelled"].bool { Text("CANCELLED").font(.caption2.weight(.bold)).foregroundStyle(Th.red) }
                }
                Text([f["aircraft"].string, f["tail"].string].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 13)).foregroundStyle(Th.muted).lineLimit(1)
            }
            Spacer()
            Text(f["date"].string.flatMap(shortDate) ?? "").font(.system(size: 13)).foregroundStyle(Th.muted)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Th.line).frame(height: 0.5).padding(.leading, 42) }
    }

    private func shortDate(_ s: String) -> String? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let d = Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return s }
        return d.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
