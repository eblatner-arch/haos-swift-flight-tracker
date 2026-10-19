import SwiftUI

/// One flight: status, both ends with times and gates, the four times, the airplane, the inbound.
/// Live position every 5 s while it's open, the whole flight every minute.
struct FlightDetail: View {
    @Environment(Store.self) private var store
    let id: String

    var body: some View {
        Group {
            if let leg = store.leg(id) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Header(leg: leg)
                        MapButtons(leg: leg)
                        if !leg.problems.isEmpty { Problems(texts: leg.problems) }
                        Endpoint(leg: leg, departure: true)
                        Endpoint(leg: leg, departure: false)
                        TimesCard(leg: leg)
                        AircraftCard(leg: leg)
                        if !leg.inbound.isNull { InboundCard(leg: leg) }
                        if let u = store.updated {
                            Text("Updated \(Fmt.relative(u)) · \(leg.j["source"].string ?? "")")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: id) {
            await store.loadDetail(id)
            var n = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                n += 1
                if n % 12 == 0 { await store.loadDetail(id) } else { await store.pollLive(id) }
            }
        }
    }
}

private struct Header: View {
    let leg: Leg
    var body: some View {
        HStack(spacing: 12) {
            Text(leg.airlineCode)
                .font(.system(size: 15, weight: .heavy))
                .frame(width: 44, height: 44)
                .background(Color(red: 0.0, green: 0.15, blue: 0.45), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(leg.display) · \(Fmt.day(leg.out.best, leg.dep.timeZone).uppercased())")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(leg.dep.city) to \(leg.arr.city)").font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(.top, 6)
    }
}

/// Zoom the map: the whole flight, the airplane, either airport.
private struct MapButtons: View {
    @Environment(Store.self) private var store
    let leg: Leg
    var body: some View {
        HStack(spacing: 8) {
            chip("Route", "point.topleft.down.to.point.bottomright.curvepath") { store.focus(.fit) }
            if leg.position != nil { chip("Plane", "airplane") { store.focus(.plane) } }
            if let c = leg.dep.coordinate {
                chip(leg.dep.code, "airplane.departure") { store.focus(.area(lat: c.latitude, lon: c.longitude, km: 2.2)) }
            }
            if let c = leg.arr.coordinate {
                chip(leg.arr.code, "airplane.arrival") { store.focus(.area(lat: c.latitude, lon: c.longitude, km: 2.2)) }
            }
        }
    }

    private func chip(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color.card, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct Problems: View {
    let texts: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(texts, id: \.self) { t in
                Label(t, systemImage: "exclamationmark.triangle.fill").font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct Endpoint: View {
    let leg: Leg
    let departure: Bool

    var body: some View {
        let ap = departure ? leg.dep : leg.arr
        let t = departure ? leg.out : leg.inn
        let late = t.lateMinutes
        let gate = departure ? leg.depGate : leg.arrGate
        let term = departure ? leg.depTerminal : leg.arrTerminal
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: departure ? "airplane.departure" : "airplane.arrival")
                Text(ap.code).font(.headline)
                Text("· \(ap.name)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.time(t.best, ap.timeZone))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(Fmt.lateColor(late))
                if let s = t.scheduled, let b = t.best, abs(b.timeIntervalSince(s)) >= 60 {
                    Text(Fmt.time(s, ap.timeZone)).strikethrough().foregroundStyle(.secondary)
                }
                Spacer()
                if let gate {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(gate).font(.title2.weight(.heavy)).foregroundStyle(.black)
                            .padding(.horizontal, 10).padding(.vertical, 2)
                            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
                        if let term { Text("Terminal \(term)").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
            HStack {
                Text(Fmt.late(late)).foregroundStyle(Fmt.lateColor(late))
                Text("· \(departure ? "Departs" : "Arrives") \(Fmt.relative(t.best)) \(Fmt.zone(t.best, ap.timeZone))")
                    .foregroundStyle(.secondary)
                Spacer()
                if !departure, let bag = leg.baggage { Text("Bags \(bag)").foregroundStyle(.secondary) }
            }
            .font(.subheadline)
        }
        .padding(14)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct TimesCard: View {
    let leg: Leg
    var body: some View {
        let rows: [(String, Times, TimeZone)] = [
            ("Gate departure", leg.out, leg.dep.timeZone), ("Takeoff", leg.off, leg.dep.timeZone),
            ("Landing", leg.on, leg.arr.timeZone), ("Gate arrival", leg.inn, leg.arr.timeZone),
        ]
        VStack(spacing: 8) {
            HStack {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                Text("Scheduled").frame(width: 78, alignment: .trailing)
                Text("Actual").frame(width: 78, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(rows, id: \.0) { r in
                HStack {
                    Text(r.0).frame(maxWidth: .infinity, alignment: .leading)
                    Text(Fmt.time(r.1.scheduled, r.2)).foregroundStyle(.secondary).frame(width: 78, alignment: .trailing)
                    Text(r.1.actual != nil ? Fmt.time(r.1.actual, r.2) : r.1.estimated != nil ? Fmt.time(r.1.estimated, r.2) : "--")
                        .foregroundStyle(r.1.actual != nil ? Fmt.lateColor(r.1.lateMinutes) : Color.secondary)
                        .italic(r.1.actual == nil)
                        .frame(width: 78, alignment: .trailing)
                }
                .font(.subheadline.monospacedDigit())
            }
        }
        .padding(14)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct AircraftCard: View {
    @Environment(Store.self) private var store
    let leg: Leg

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Aircraft").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(leg.aircraftName ?? "Aircraft").font(.title3.weight(.bold))
            Text([leg.tail, leg.aircraftType].compactMap { $0 }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
            if let u = store.liveryURL(leg) {
                AsyncImage(url: u) { img in
                    img.resizable().scaledToFit().shadow(color: .black.opacity(0.5), radius: 8, y: 6)
                } placeholder: {
                    Color.clear.frame(height: 90)
                }
                .padding(.vertical, 8)
            } else {
                Image(systemName: "airplane").font(.system(size: 60)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            if let t = leg.tail, let age = store.ageText(t, type: leg.aircraftType) {
                Text(age).font(.subheadline).foregroundStyle(.secondary)
            }
            if let t = leg.tail, let n = leg.tailCount {
                Text(n > 0 ? "You've flown \(t) \(n) time\(n == 1 ? "" : "s") before." : "First time on \(t).")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .task(id: leg.tail) {
            if let t = leg.tail, t.hasPrefix("N") { await store.loadTail(t, type: leg.aircraftType) }
        }
    }
}

private struct InboundCard: View {
    let leg: Leg
    var body: some View {
        let ib = leg.inbound
        let o = Airport(j: ib["origin"]), d = Airport(j: ib["destination"])
        VStack(alignment: .leading, spacing: 6) {
            Text("Inbound aircraft").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                Text(ib["display_ident"].string ?? ib["ident"].string ?? "Inbound").font(.headline)
                Text("\(o.code) → \(d.code)").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Text(ib["status"].string ?? (ib["phase"].string ?? "").capitalized).font(.subheadline)
            }
            let inT = Times(ib["times"]["in"])
            if inT.best != nil {
                Text("Arrives \(Fmt.time(inT.best, d.timeZone)) · \(Fmt.late(inT.lateMinutes))")
                    .font(.subheadline).foregroundStyle(Fmt.lateColor(inT.lateMinutes))
            }
            if let turn = leg.turnMinutes {
                Text("\(Fmt.span(Double(turn * 60))) to turn").font(.subheadline).foregroundStyle(turn < 30 ? Color.orange : Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
