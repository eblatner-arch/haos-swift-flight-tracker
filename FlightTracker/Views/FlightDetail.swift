import SwiftUI

/// One flight, laid out like the web app's flight page: header, status banner, FAA programs, both
/// ends with the time between them, Good to Know, the inbound aircraft, times, the airplane, more.
/// Live position every 5 s while it's open, the whole flight every minute.
struct FlightDetail: View {
    @Environment(Store.self) private var store
    let id: String

    var body: some View {
        Group {
            if let leg = store.leg(id) {
                FlightPage(leg: leg, sub: "\(leg.display.replacingOccurrences(of: leg.airlineCode, with: leg.airlineCode + " ")) • \(Fmt.day(leg.out.best, leg.dep.timeZone).uppercased())\(leg.deadhead ? " • DH" : "")",
                           refreshID: leg.finished ? nil : id, inboundBase: (id, 0))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { store.seedDetail(id); store.openDetail = id }
        .onDisappear { if store.openDetail == id { store.openDetail = nil } }
        .task(id: id) {
            await store.loadDetail(id)
            var n = 0
            while !Task.isCancelled {
                let low = UserDefaults.standard.bool(forKey: "lowData")
                try? await Task.sleep(for: .seconds(low ? 15 : 5))
                if Task.isCancelled { break }
                n += 1
                if n % (low ? 4 : 12) == 0 { await store.loadDetail(id) } else { await store.pollLive(id) }
            }
        }
    }
}

/// An earlier leg of your airplane (your inbound, or the one before it), as a flight page.
struct AircraftLegView: View {
    @Environment(Store.self) private var store
    let id: String
    let n: Int

    var body: some View {
        Group {
            if let leg = store.rotationLeg(id, n) {
                FlightPage(leg: leg, sub: "\(leg.display) • \(n == 0 ? "YOUR INBOUND" : "\(n + 1) LEGS BACK")", refreshID: nil, inboundBase: (id, n + 1))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: id) {
            await store.loadRotation(id)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { break }
                await store.loadRotation(id)
            }
        }
    }
}

/// The flight page itself (your flight, or one of its airplane's earlier legs).
struct FlightPage: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav
    let leg: Leg
    let sub: String
    let refreshID: String?
    let inboundBase: (String, Int)
    @State private var refreshing = false
    @State private var confirmRemove = false
    @State private var askAero = false
    @State private var aeroText: String?
    private var isAircraft: Bool { leg.id.contains("~") }

    var body: some View {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        DetailHeader(badge: leg.airlineCode, sub: sub, title: "\(leg.dep.city) to \(leg.arr.city)") { nav.back() }
                        StatusBanner(status: StatusLine(leg).withEDCT(leg).withTrend(leg)).padding(.horizontal, -14)
                        ForEach(nasGroups([leg]).filter { $0.major }) { NasAlertCard(g: $0) }
                        EndpointView(leg: leg, departure: true)
                        MidLine(leg: leg)
                        EndpointView(leg: leg, departure: false)
                        GoodToKnow(leg: leg)
                        if !leg.inbound.isNull { InboundCard(leg: leg, base: inboundBase) }
                        TimesCard(leg: leg)
                        AircraftCard(leg: leg)
                        HStack(spacing: 8) {
                            if let id = refreshID {
                                pill(refreshing ? "Refreshing…" : "Refresh this flight") {
                                    refreshing = true
                                    Task {
                                        await store.refreshLeg(id)
                                        try? await Task.sleep(for: .seconds(20))
                                        await store.loadDetail(id)
                                        refreshing = false
                                    }
                                }
                            }
                            if let u = faURL(leg) { Link(destination: u) { pillLabel("FlightAware ↗") } }
                        }
                        .padding(.top, 4)
                        if !isAircraft {
                            FlowLayout(spacing: 8) {
                                if store.stateJ["aeroapi"].bool {
                                    pill(aeroText ?? "Check AeroAPI now") { askAero = true }
                                }
                                if leg.j["manual"].bool || leg.extra {
                                    let mine = leg.j["kind"].string == "manual"
                                    pill(mine ? "Make it a friend's flight" : "It's my flight") {
                                        Task { await store.setKind(leg.id, mine ? "friend" : "manual") }
                                    }
                                    Button { if Nav.blocked { return }; confirmRemove = true } label: {
                                        Text("Remove").font(.system(size: 16, weight: .semibold)).foregroundStyle(Th.red)
                                            .padding(.horizontal, 15).padding(.vertical, 10)
                                            .background(Th.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Fold(title: "Flight Details") { DetailsKV(leg: leg) }
                        let metars = [leg.dep, leg.arr].compactMap { ap in leg.weather(ap)["raw"].string.map { (ap.code, $0) } }
                        if !metars.isEmpty {
                            Fold(title: "METARs") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(metars, id: \.0) { m in Text(m.1).font(.system(.footnote, design: .monospaced)) }
                                }
                                .card()
                            }
                        }
                        let minor = nasGroups([leg]).filter { !$0.major }
                        if !minor.isEmpty {
                            Fold(title: "Other NAS Items") { VStack(spacing: 10) { ForEach(minor) { NasAlertCard(g: $0) } } }
                        }
                        let al = leg.j["alerts"].array
                        if !al.isEmpty { Fold(title: "Alerts for This Flight") { AlertsCard(list: al, open: { _ in }) } }
                        if isAircraft {
                            let parts = leg.id.split(separator: "~"), pid = String(parts[0]), n = Int(parts.last ?? "0") ?? 0
                            let log = LogEntry.inbound(raw: store.rotations[pid]?[safe: n] ?? .null, n: n, parent: store.leg(pid))
                            if !log.isEmpty { LookupLog(entries: log) }
                        } else {
                            let log = LogEntry.of(leg)
                            if !log.isEmpty {
                                LookupLog(entries: log, more: leg.j["history_more"].int ?? 0) {
                                    store.logAll.insert(leg.id)
                                    await store.loadDetail(leg.id)
                                }
                            }
                            if leg.j["shot"].bool || leg.j["shot"].string != nil, let u = API.url("api/shot/\(leg.id).png?t=\(Int(leg.j["updated"].double ?? 0))") {
                                Fold(title: "Latest Screenshot") {
                                    AsyncImage(url: u) { img in img.resizable().scaledToFit() } placeholder: { ProgressView().frame(maxWidth: .infinity, minHeight: 120) }
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                        if let u = store.updated {
                            Text("Updated \(Fmt.ago(u)) · \(leg.j["source"].string ?? "")").font(.caption).foregroundStyle(Th.faint)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 100)
            .sheetScroll()
                }
                .confirmationDialog("Remove \(leg.display)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                    Button("Remove", role: .destructive) { Task { await store.removeFlight(leg.id); nav.back() } }
                }
                .alert("Ask AeroAPI now?", isPresented: $askAero) {
                    Button("Ask") { Task { await aero() } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("It's one paid query (about half a cent), counted in your monthly budget.")
                }
    }

    private func aero() async {
        aeroText = "Asking AeroAPI…"
        do {
            let d = try await API.post("api/aero/\(leg.id)")
            aeroText = "AeroAPI: " + (d["status"].string ?? "answered") + (d["tail"].string.map { " · " + $0 } ?? "")
            try? await Task.sleep(for: .seconds(1.5))
            await store.loadDetail(leg.id)
        } catch {
            aeroText = "AeroAPI: \(error.localizedDescription)"
        }
    }

    private func faURL(_ leg: Leg) -> URL? {
        if let fa = leg.j["fa_id"].string { return URL(string: "https://www.flightaware.com/live/flight/id/\(fa)") }
        if let i = leg.j["ident"].string { return URL(string: "https://www.flightaware.com/live/flight/\(i)") }
        return nil
    }

    private func pill(_ t: String, _ action: @escaping () -> Void) -> some View {
        Button(action: { if !Nav.blocked { action() } }) { pillLabel(t) }.buttonStyle(.plain)
    }
    private func pillLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 15).padding(.vertical, 10)
            .background(Th.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The page header: airline badge, "UA 2677 • MON, OCT 19", the cities, and a close button.
struct DetailHeader: View {
    let badge: String
    let sub: String
    let title: String
    let close: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            AirlineBadge(code: badge, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(sub).font(.system(size: 14, weight: .semibold)).tracking(0.3).foregroundStyle(Th.muted).lineLimit(1)
                Text(title).font(.system(size: 21, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            RoundButton(symbol: "xmark", action: close)
        }
        .padding(.top, 16)
    }
}

/// The full-width colored band: "Departs in 48m" and what it means.
struct StatusBanner: View {
    let status: StatusLine
    var body: some View {
        let c = status.tone
        VStack(alignment: .leading, spacing: 3) {
            Text(status.head).font(.system(size: 19, weight: .bold)).foregroundStyle(c ?? .white)
            if !status.sub.isEmpty { Text(status.sub).font(.system(size: 15)).foregroundStyle((c ?? .white).opacity(0.85)) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(c.map { $0.opacity(0.16) } ?? Th.card)
    }
}

/// One end: airport, big time (red/amber when late), the scheduled time struck out, how late and
/// when, EDCT, gate (yellow) and bags, terminal.
struct EndpointView: View {
    let leg: Leg
    let departure: Bool

    var body: some View {
        let ap = departure ? leg.dep : leg.arr
        let t = departure ? leg.out : leg.inn
        let known = departure ? leg.outKnown : leg.inKnown
        let m = t.lateMinutes
        let tone = Th.lateTone(m, known: known)
        let gate = departure ? leg.depGate : leg.arrGate
        let term = departure ? leg.depTerminal : leg.arrTerminal
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: departure ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(.black)
                    .frame(width: 20, height: 20).background(.white, in: Circle())
                Text(ap.code).font(.system(size: 17, weight: .bold))
                Text("•").foregroundStyle(Th.muted)
                Text(ap.short).font(.system(size: 17)).lineLimit(1)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(leg.notFound ? "—" : Fmt.time(t.best, ap.timeZone))
                            .font(.system(size: 38, weight: .bold)).foregroundStyle(tone ?? .white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if !leg.notFound, let s = t.scheduled, let b = t.best, abs(b.timeIntervalSince(s)) >= 60 {
                            Text(Fmt.time(s, ap.timeZone)).font(.system(size: 17)).strikethrough().foregroundStyle(Th.muted)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(Fmt.lateWord(m, known: known)).foregroundStyle(Th.tone(m, known: known) ?? Th.muted)
                        if let b = t.best {
                            Text("• " + (b > Date() ? "\(departure ? "Departs" : "Arrives") in \(Fmt.span(b.timeIntervalSinceNow))" : "\(Fmt.span(-b.timeIntervalSinceNow)) ago"))
                                .foregroundStyle(Th.muted)
                            Text(Fmt.zone(b, ap.timeZone)).font(.system(size: 13)).foregroundStyle(Th.faint)
                        }
                    }
                    .font(.system(size: 15)).lineLimit(1).minimumScaleFactor(0.8)
                    if departure, let e = leg.edct {
                        (Text("EDCT ") + Text(Fmt.time(e.at, ap.timeZone)).bold() + Text(e.program.map { " · \($0)" } ?? ""))
                            .font(.system(size: 15)).foregroundStyle(Th.amber)
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 6) {
                        if !departure, let bag = leg.baggage { badge("suitcase.fill", bag) }
                        if let gate { badge(departure ? "arrow.up.right" : "arrow.down.right", gate) }
                        else { Text("—").font(.system(size: 20, weight: .bold)).foregroundStyle(Th.muted) }
                    }
                    if let term { (Text("Terminal ").foregroundColor(Th.muted) + Text(term)).font(.system(size: 14)) }
                    else if gate == nil { Text("Gate not set").font(.system(size: 13)).foregroundStyle(Th.muted) }
                }
                .padding(.top, 6)
            }
        }
        .padding(.top, 8)
    }

    private func badge(_ sym: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: sym).font(.system(size: 12, weight: .heavy))
            Text(text).font(.system(size: 20, weight: .heavy))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(Th.yellow, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Between the two ends: gate-to-gate time, distance, and how far along it is.
struct MidLine: View {
    let leg: Leg
    var body: some View {
        let block = (leg.inn.best ?? Date()).timeIntervalSince(leg.out.best ?? Date())
        let nm = leg.distanceNM
        let pct = progress
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "clock").font(.system(size: 12))
                Text([block > 0 ? Fmt.span(block) : nil, nm.map { "\(Int($0 * 1.15078).formatted()) mi" }].compactMap { $0 }.joined(separator: " • "))
            }
            .font(.system(size: 14)).foregroundStyle(Th.muted).fixedSize()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Th.line).frame(height: 3)
                    if let pct {
                        Capsule().fill(Th.route).frame(width: geo.size.width * pct, height: 3)
                        Image(systemName: "airplane").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            .offset(x: max(0, geo.size.width * pct - 7))
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 16)
        }
        .padding(.vertical, 6)
    }

    private var progress: Double? {
        if leg.phase == "airborne", let offA = leg.off.actual, let end = leg.on.best ?? leg.inn.best, end > offA {
            return min(1, max(0, Date().timeIntervalSince(offA) / end.timeIntervalSince(offA)))
        }
        return ["landed", "arrived"].contains(leg.phase) ? 1 : nil
    }
}

/// Weather at both ends, FAA programs and delays, a time zone change, your record on the route.
struct GoodToKnow: View {
    let leg: Leg
    var body: some View {
        let cards = items
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Good to Know").font(.system(size: 21, weight: .bold)).padding(.top, 10)
                ForEach(Array(cards.enumerated()), id: \.offset) { _, c in
                    HStack(spacing: 14) {
                        Group {
                            if let sym = c.icon { Image(systemName: sym).symbolRenderingMode(.multicolor).font(.system(size: 22)) }
                            else { Text(c.badgeIcon ?? "").font(.system(size: 13, weight: .bold)).frame(width: 30, height: 30).background(Th.card2, in: Circle()) }
                        }
                        .frame(width: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.title).font(.system(size: 17, weight: .semibold))
                            if !c.text.isEmpty { Text(c.text).font(.system(size: 15)).foregroundStyle(c.tone ?? Th.muted) }
                        }
                        Spacer()
                        if let b = c.badge {
                            Text(b).font(.system(size: 11, weight: .heavy)).foregroundStyle(Th.green)
                                .padding(.horizontal, 6).padding(.vertical, 3).background(Th.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                    .card()
                }
            }
        }
    }

    private struct Item {
        var icon: String?
        var badgeIcon: String? = nil
        let title: String
        let text: String
        var tone: Color? = nil
        var badge: String? = nil
    }

    private var items: [Item] {
        var out: [Item] = []
        for ap in [leg.dep, leg.arr] {
            if let w = WeatherSummary(leg.weather(ap)) {
                out.append(Item(icon: w.symbol, title: "Current \(ap.code) Weather", text: w.text, badge: w.category))
            }
        }
        var byAirport: [String: [JSON]] = [:]
        for n in leg.nas { byAirport[n["airport"].string ?? "?", default: []].append(n) }
        for code in [leg.dep.code, leg.arr.code] {
            for n in byAirport[code] ?? [] {
                let major = majorKinds.contains(n["kind"].string ?? "")
                let sub = [n["detail"].string, n["reason"].string].compactMap { $0 }.joined(separator: " · ")
                out.append(Item(icon: n["dir"].string == "dep" ? "airplane.departure" : "airplane.arrival", title: "\(code): \(n["label"].string ?? "FAA")", text: sub, tone: major ? Th.red : Th.amber))
            }
        }
        if byAirport.isEmpty && leg.watching {
            out.append(Item(icon: "sun.max.fill", title: "No FAA delays", text: "No ground stops, delay programs or closures at \(leg.dep.code) or \(leg.arr.code)."))
        }
        if let t = leg.inn.best {
            let a = leg.arr.timeZone.secondsFromGMT(for: t), d = leg.dep.timeZone.secondsFromGMT(for: t)
            if a != d {
                let h = (a - d) / 3600, hs = "\(h > 0 ? "+" : "−")\(abs(h))"
                out.append(Item(icon: nil, badgeIcon: hs, title: "\(hs) Hour\(abs(h) == 1 ? "" : "s") Timezone Change",
                                text: "\(Fmt.time(t, leg.arr.timeZone)) arrival is \(Fmt.time(t, leg.dep.timeZone)) \(leg.dep.city) time"))
            }
        }
        let rs = leg.routeStats
        if let n = rs["flights"].int, n > 0 {
            let avg = rs["avg_arr_delay"].double
            var txt = "No delay record yet"
            if let p = rs["on_time_pct"].int {
                txt = "\(p)% on time"
                if let avg { txt += avg >= 1 ? " · usually \(Int(avg.rounded())) min late" : " · usually on time" }
            }
            out.append(Item(icon: nil, badgeIcon: "\(n)×", title: "You've flown \(leg.dep.code)–\(leg.arr.code) \(n) time\(n == 1 ? "" : "s")", text: txt))
        }
        return out
    }
}

/// The airplane bringing you in, and the legs before it, as a timeline.
struct InboundCard: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav
    let leg: Leg
    /// (your flight's id, the index of this card's first leg in its airplane's rotation)
    let base: (String, Int)

    private var rot: [JSON] { leg.j["rotation"].array.isEmpty ? [leg.inbound] : leg.j["rotation"].array }

    var body: some View {
        let i0 = rot[0], it = i0["times"]
        let ph = i0["phase"].string ?? (it["in"]["actual"].isNull ? "scheduled" : "arrived")
        let inT = Times(it["in"])
        let s = summary(ph: ph, i0: i0, inT: inT, am: inT.lateMinutes, from: Airport(j: i0["origin"]).city)
        let dm = leg.out.lateMinutes
        let me = leg.phase == "scheduled" ? "Departs \(Fmt.lateLower(dm))" : "Departed \(Fmt.lateLower(dm))"
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Inbound Aircraft").font(.system(size: 20, weight: .bold))
                Spacer()
                Text([i0["tail"].string, i0["aircraft_type"].string].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 14)).foregroundStyle(Th.muted)
            }
            Text(s.pill.uppercased()).font(.system(size: 13, weight: .heavy)).tracking(0.5)
                .foregroundStyle(s.tone == nil ? .white : .black)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(s.tone ?? Th.card2, in: RoundedRectangle(cornerRadius: 7))
            Text(s.line).font(.system(size: 16))
            if let turn = leg.turnMinutes, leg.phase == "scheduled" { TurnBar(turn: turn, minTurn: store.minTurn, landed: !it["in"]["actual"].isNull) }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold))
                    Text("This Flight").font(.system(size: 16, weight: .bold))
                    Spacer()
                    Text(me).font(.system(size: 15)).foregroundStyle(Th.lateTone(dm, known: leg.outKnown) ?? Th.green)
                }
                .padding(12)
                .background(Th.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rot.prefix(3).enumerated()), id: \.offset) { i, r in
                        Button { if Nav.blocked { return }; nav.push(.aircraft(base.0, base.1 + i)) } label: { InboundLegRow(r: r).contentShape(Rectangle()) }.buttonStyle(.plain)
                    }
                    if let last = rot.prefix(3).last { TimelineNode(code: Airport(j: last["origin"]).code, color: phaseColor(last["phase"].string)) }
                }
                // the line joining the stops, from this flight down through the airplane's day
                .background(alignment: .topLeading) {
                    GeometryReader { g in
                        Rectangle().fill(Th.muted.opacity(0.55)).frame(width: 2, height: max(0, g.size.height - 30))
                            .offset(x: 12.5, y: 15)
                    }
                }
                if rot.count > 3 {
                    Button { if Nav.blocked { return }; nav.push(.aircraft(base.0, base.1 + 3)) } label: {
                        HStack(spacing: 10) {
                            Text("\(rot.count - 3)").font(.system(size: 12, weight: .bold)).frame(width: 20, height: 20).overlay(Circle().stroke(Th.muted))
                            Text("Show More Flights").font(.system(size: 15)).foregroundStyle(Th.muted)
                        }
                        .padding(.leading, 8).padding(.top, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
    }

    private struct Summary { let pill: String; let tone: Color?; let line: String }

    private func summary(ph: String, i0: JSON, inT: Times, am: Int?, from: String) -> Summary {
        let tz = leg.dep.timeZone
        switch ph {
        case "arrived":
            return Summary(pill: "Arrived \(Fmt.lateLower(am))", tone: Th.tone(am), line: "The inbound aircraft arrived \(Fmt.lateLower(am)).")
        case "airborne", "landed":
            let at = inT.best.map { ", at the gate ~\(Fmt.time($0, tz))" } ?? ""
            return Summary(pill: ph == "landed" ? "Landed" : "En route · \(Fmt.lateLower(am))", tone: Th.tone(am),
                           line: "Your aircraft is \(ph == "landed" ? "on the ground here" : "flying in from \(from)")\(at).")
        case "taxi_out":
            var pill = "Taxiing"
            if let outA = Times(i0["times"]["out"]).actual, -outA.timeIntervalSinceNow >= 60 { pill = "Taxiing · \(Fmt.span(-outA.timeIntervalSinceNow))" }
            return Summary(pill: pill, tone: Th.tone(am), line: "Your aircraft is taxiing at \(from) and hasn't taken off yet.")
        case "cancelled", "diverted":
            return Summary(pill: ph == "cancelled" ? "Cancelled" : "Diverted", tone: Th.red, line: "The inbound flight was \(ph).")
        default:
            if let e = i0["edct"]["at"].date {
                let oz = Airport(j: i0["origin"]).timeZone
                return Summary(pill: "EDCT \(Fmt.time(e, oz))", tone: Th.amber, line: "Your aircraft is due from \(from). It has an EDCT of \(Fmt.time(e, oz)) \(Fmt.zone(e, oz)).")
            }
            let o = Times(i0["times"]["out"])
            let due = inT.best.map { " at \(Fmt.time($0, tz))" } ?? ""
            return Summary(pill: "Not departed", tone: Th.tone(o.lateMinutes, known: o.estimated != nil || o.actual != nil), line: "Your aircraft is due from \(from)\(due).")
        }
    }
}

private struct TurnBar: View {
    let turn: Int
    let minTurn: Int
    let landed: Bool
    var body: some View {
        let frac = landed || turn < 0 ? 1.0 : max(0.04, min(1, Double(turn) / Double(max(minTurn * 2, 60))))
        let c = turn < 0 ? Th.red : turn < minTurn ? Th.amber : Th.green
        HStack(spacing: 10) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Th.line)
                    Capsule().fill(c).frame(width: g.size.width * frac)
                }
            }
            .frame(height: 6)
            Text(turn < 0 ? "lands \(Fmt.span(Double(-turn * 60))) after you're due out" : "\(Fmt.span(Double(turn * 60))) turn")
                .font(.system(size: 16, weight: .bold)).fixedSize()
        }
    }
}

/// green while that leg is flying or done, grey before it leaves
func phaseColor(_ ph: String?) -> Color {
    switch ph ?? "" {
    case "airborne", "landed", "arrived", "taxi_out": return Th.green
    case "cancelled", "diverted": return Th.red
    default: return Th.muted
    }
}

private struct TimelineNode: View {
    let code: String
    var color: Color = Th.muted
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 11, height: 11).overlay(Circle().stroke(Th.card, lineWidth: 2.5))
            Text(code).font(.system(size: 14, weight: .semibold)).foregroundStyle(Th.muted)
        }
        .padding(.leading, 8).padding(.vertical, 6)
    }
}

private struct InboundLegRow: View {
    let r: JSON
    var body: some View {
        let o = Airport(j: r["origin"]), d = Airport(j: r["destination"]), rt = r["times"]
        let rin = Times(rt["in"]), rm = rin.lateMinutes
        let rk = !rt["in"]["actual"].isNull || !rt["in"]["estimated"].isNull
        VStack(alignment: .leading, spacing: 0) {
            TimelineNode(code: d.code, color: ["arrived", "landed"].contains(r["phase"].string ?? "") ? Th.green : Th.muted)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(o.city) to \(d.city)").font(.system(size: 16, weight: .semibold))
                    Text("\(r["display_ident"].string ?? "") · \(sub(o, d, rin))").font(.system(size: 14)).foregroundStyle(Th.muted)
                }
                Spacer()
                Text(r["phase"].string == "cancelled" ? "Cancelled" : Fmt.lateWord(rm, known: rk))
                    .font(.system(size: 15)).foregroundStyle(Th.tone(rm, known: rk) ?? Th.muted)
            }
            .padding(.leading, 34).padding(.vertical, 6)
        }
    }

    private func sub(_ o: Airport, _ d: Airport, _ rin: Times) -> String {
        switch r["phase"].string ?? "" {
        case "arrived": return "Arrived \(Fmt.time(rin.best, d.timeZone))"
        case "airborne", "landed": return "Arrives \(Fmt.time(rin.best, d.timeZone))"
        case "taxi_out": return "Taxiing · arrives \(Fmt.time(rin.best, d.timeZone))"
        case "cancelled": return "Cancelled"
        default:
            let out = Times(r["times"]["out"])
            let edct = r["edct"]["at"].date.map { " · EDCT \(Fmt.time($0, o.timeZone))" } ?? ""
            return "Departs \(Fmt.time(out.best, o.timeZone))\(edct)"
        }
    }
}

/// Each of the four times: actual, estimate or schedule, and who it's from.
struct TimesCard: View {
    let leg: Leg

    private struct RowData: Identifiable { let id: String; let label: String; let value: String; let tone: Color?; let src: String }

    private var rows: [RowData] {
        let f = leg.flight, src = f["time_src"]
        var out: [RowData] = []
        for (label, k, tz) in [("Gate out", "out", leg.dep.timeZone), ("Takeoff", "off", leg.dep.timeZone), ("Landing", "on", leg.arr.timeZone), ("Gate in", "in", leg.arr.timeZone)] {
            let x = Times(f["times"][k])
            guard let v = x.best else { continue }
            let kind = x.actual != nil ? "Actual" : x.estimated != nil ? "Estimate" : "Scheduled"
            let who = kind == "Scheduled" ? "" : (src[k][kind == "Actual" ? "actual" : "estimated"].string ?? leg.j["source"].string ?? "FlightAware")
            out.append(RowData(id: k, label: label, value: Fmt.time(v, tz), tone: kind == "Scheduled" ? nil : Th.lateTone(x.lateMinutes), src: kind + (who.isEmpty ? "" : " · \(who)")))
            if k == "off", let e = leg.edct {
                out.append(RowData(id: "edct", label: "EDCT", value: Fmt.time(e.at, leg.dep.timeZone), tone: Th.amber, src: "FAA" + (e.program.map { " · \($0) program" } ?? "")))
            }
        }
        return out
    }

    var body: some View {
        let list = rows
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Times").font(.system(size: 20, weight: .bold)).padding(.bottom, 8)
                ForEach(list) { r in
                    HStack {
                        Text(r.label).foregroundStyle(Th.muted).frame(width: 90, alignment: .leading)
                        Text(r.value).fontWeight(.bold).foregroundStyle(r.tone ?? .white)
                        Spacer()
                        Text(r.src).foregroundStyle(Th.muted).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.system(size: 15))
                    .padding(.vertical, 9)
                    .overlay(alignment: .top) { Rectangle().fill(Th.line).frame(height: 0.5) }
                }
            }
            .card()
        }
    }
}

struct AircraftCard: View {
    @Environment(Store.self) private var store
    let leg: Leg

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Aircraft").font(.system(size: 14)).foregroundStyle(Th.muted)
            Text(leg.aircraftName ?? "Aircraft").font(.system(size: 22, weight: .bold))
            Text([leg.tail, leg.aircraftType].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 14)).foregroundStyle(Th.muted)
            if let u = store.liveryURL(leg) {
                AsyncImage(url: u) { img in
                    img.resizable().scaledToFit().shadow(color: .black.opacity(0.45), radius: 10, y: 6)
                } placeholder: {
                    Color.clear.frame(height: 90)
                }
                .padding(.vertical, 10)
            } else {
                Image(systemName: "airplane").font(.system(size: 64)).foregroundStyle(Th.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            if let t = leg.tail, let age = store.ageText(t, type: leg.aircraftType) {
                Text(age).font(.system(size: 14)).foregroundStyle(Th.muted)
            }
            if let t = leg.tail, let n = leg.tailCount {
                let txt = n > 0 ? Text("You've flown ") + Text(t).bold().foregroundColor(.white) + Text(" \(n) time\(n == 1 ? "" : "s") before.")
                                : Text("First time on ") + Text(t).bold().foregroundColor(.white) + Text(".")
                txt.font(.system(size: 14)).foregroundStyle(Th.muted)
            }
        }
        .card()
        .task(id: leg.tail) {
            if let t = leg.tail, t.hasPrefix("N") { await store.loadTail(t, type: leg.aircraftType) }
        }
    }
}

/// A section that opens and closes, like the web app's.
struct Fold<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { if Nav.blocked { return }; withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } } label: {
                HStack {
                    Text(title).font(.system(size: 18, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Th.muted).rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(.vertical, 12).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { content }
        }
    }
}

private struct DetailsKV: View {
    let leg: Leg

    private var rows: [(String, String)] {
        let f = leg.flight
        let all: [(String, String?)] = [
            ("Aircraft", [leg.aircraftName, leg.tail].compactMap { $0 }.joined(separator: " · ")),
            ("Filed altitude", f["filed_altitude"].double.map { "FL" + String(format: "%03d", Int($0 > 1000 ? $0 / 100 : $0)) }),
            ("Filed speed", f["filed_speed"].double.map { "\(Int($0)) kt" }),
            ("Distance", f["distance_nm"].double.map { "\(Int($0)) nm" }),
            ("Live", leg.live.map { "\(Int($0.altitude ?? 0)) ft · \(Int($0.speed ?? 0)) kt · \($0.source ?? "adsb.lol")" }),
            ("Metering (TBFM)", tbfm),
            ("EDCT from", ["TBFM": "TBFM (metering)", "flight plan": "the refiled flight plan (a slot swap)", "clearance": "the datalink clearance"][f["swim"]["edct_src"].string ?? ""]),
            ("Data from", leg.j["source"].string),
            ("Updated", leg.j["updated"].date.map { Fmt.ago($0) }),
            ("Calendar", leg.j["summary"].string),
        ]
        return all.compactMap { r in r.1.flatMap { $0.isEmpty ? nil : (r.0, $0) } }
    }

    /// what the metering system says: release time, its EDCT, meter fix, runway, scheduled landing
    private var tbfm: String? {
        let t = leg.flight["swim"]["tbfm"]
        guard !t.isNull else { return nil }
        let iso = { (k: String) -> Date? in t[k].string.flatMap { ISO8601DateFormatter().date(from: $0) } }
        let parts: [String?] = [
            iso("ctm").map { "release \(Fmt.time($0, leg.dep.timeZone))" },
            iso("etm").map { "EDCT \(Fmt.time($0, leg.dep.timeZone))" },
            t["mfx"].string.map { "meter fix \($0)" },
            (t["trw"].string ?? t["rwy"].string).map { "runway \($0)" },
            (iso("sta_rwy") ?? iso("sta")).map { "scheduled landing \(Fmt.time($0, leg.arr.timeZone))" },
            iso("sta_mfx").map { "meter fix at \(Fmt.time($0, leg.arr.timeZone))" } ?? iso("eta_mfx").map { "meter fix ~\(Fmt.time($0, leg.arr.timeZone))" },
        ]
        let s = parts.compactMap { $0 }.joined(separator: " · ")
        return s.isEmpty ? nil : s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.0) { r in
                HStack(alignment: .top) {
                    Text(r.0).foregroundStyle(Th.muted).frame(width: 120, alignment: .leading)
                    Text(r.1)
                }
                .font(.system(size: 15))
            }
        }
        .card()
    }
}
