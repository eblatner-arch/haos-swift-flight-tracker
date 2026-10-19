import SwiftUI

/// The sheet's first page: My Flights, Alerts or Passport, chosen with the tab bar at the bottom.
struct HomeView: View {
    @Environment(Store.self) private var store
    @Binding var tab: Tab
    @Binding var showSettings: Bool
    @Binding var showAdd: Bool
    let open: (Route) -> Void

    var body: some View {
        Group {
            switch tab {
            case .flights: FlightsHome(showSettings: $showSettings, showAdd: $showAdd, open: open)
            case .alerts: AlertsView(open: open)
            case .passport: PassportView(showSettings: $showSettings)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The page title row: big title, then round buttons.
struct SheetTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .center) {
            Text(title).font(.system(size: 32, weight: .bold)).tracking(-0.5).accessibilityIdentifier("sheetTitle")
            Spacer()
            trailing
        }
        .padding(.top, 18).padding(.bottom, 8)
    }
}

/// A round dark button (settings, close...).
struct RoundButton: View {
    let symbol: String
    var label: String? = nil
    var fill: Color = Th.card2
    let action: () -> Void
    var body: some View {
        Button(action: { if !Nav.blocked { action() } }) {
            Group {
                if let label { Text(label).font(.system(size: 17, weight: .bold)).foregroundStyle(.black) }
                else { Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(.white) }
            }
            .frame(width: 38, height: 38)
            .background(fill, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// The avatar: the first letter of where alerts go (notify.mobile_app_erics_iphone → E), gold.
struct Avatar: View {
    @Environment(Store.self) private var store
    let action: () -> Void
    var body: some View {
        let t = store.stateJ["notify_target"].string ?? ""
        let letter = t.range(of: #"mobile_app_([a-z])"#, options: [.regularExpression, .caseInsensitive]).map { String(t[$0].last!).uppercased() }
        if let letter {
            RoundButton(symbol: "", label: letter, fill: Color(hex: 0xE9C46A), action: action)
        } else {
            RoundButton(symbol: "gearshape.fill", action: action)
        }
    }
}

/// The floating tab bar: My Flights, Alerts, Passport.
struct TabBar: View {
    @Binding var tab: Tab
    let search: () -> Void
    var body: some View {
        HStack(spacing: 10) {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { if Nav.blocked { return }; tab = t } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 19, weight: .semibold))
                        Text(t.rawValue).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(tab == t ? Th.accent : .white)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(tab == t ? Color.white.opacity(0.12) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Color(hex: 0x26262A, alpha: 0.94), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
            Button(action: search) {
                Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Color(hex: 0x26262A, alpha: 0.94), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .padding(.horizontal, 14).padding(.bottom, 6)
    }
}

extension Tab {
    var icon: String {
        switch self {
        case .flights: return "airplane"
        case .alerts: return "bell.fill"
        case .passport: return "person.text.rectangle.fill"
        }
    }
}

// MARK: - My Flights

struct FlightsHome: View {
    @Environment(Store.self) private var store
    @Binding var showSettings: Bool
    @Binding var showAdd: Bool
    let open: (Route) -> Void

    var body: some View {
        let live = store.upcoming
        let watching = live.filter { $0.watching }
        let groups = nasGroups(watching)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SheetTitle(title: "My Flights") {
                    HStack(spacing: 10) {
                        RoundButton(symbol: "plus") { showAdd = true }
                        Avatar { showSettings = true }
                    }
                }
                if store.offline || store.error != nil {
                    Label(store.error ?? "Offline: showing the last copy on this phone", systemImage: store.offline ? "wifi.slash" : "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(store.offline ? Th.muted : Th.amber)
                }
                ForEach(groups.filter { $0.major }) { NasAlertCard(g: $0) }
                ForEach(groups.filter { $0.kind == "delay" }) { NasTrendCard(g: $0, many: watching.count > 1) }
                if live.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No upcoming flights").font(.headline)
                        Text("Nothing coming up in your calendar.").foregroundStyle(Th.muted)
                    }
                    .card()
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(live.enumerated()), id: \.element.id) { i, leg in
                            if i > 0, let lay = layover(live[i - 1], leg) { lay }
                            Button { if Nav.blocked { return }; open(.leg(leg.id)) } label: { FlightRowView(leg: leg) }.buttonStyle(.plain)
                        }
                    }
                }
                let airports = Array(Set(watching.flatMap { [$0.dep.code, $0.arr.code] })).sorted()
                if !airports.isEmpty {
                    SectionHead(title: "FAA Status", trailing: airports.joined(separator: " · "))
                    let minor = groups.filter { !$0.major && $0.kind != "delay" }
                    if minor.isEmpty {
                        Text(groups.isEmpty ? "No ground stops, delay programs or closures at your airports." : "Shown at the top.")
                            .font(.subheadline).foregroundStyle(Th.muted).card()
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(minor) { g in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(g.airport).font(.headline)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(g.n["label"].string ?? "").font(.subheadline.weight(.semibold))
                                        Text([g.n["detail"].string, g.n["reason"].string].compactMap { $0 }.joined(separator: " · ")).font(.footnote).foregroundStyle(Th.muted)
                                    }
                                }
                            }
                        }
                        .card()
                    }
                }
                let recent = store.recent.filter { ($0.inn.best ?? .distantPast).timeIntervalSinceNow > -18 * 3600 }.prefix(3)
                if !recent.isEmpty {
                    SectionHead(title: "Recent", trailing: nil)
                    VStack(spacing: 0) {
                        ForEach(Array(recent)) { leg in
                            Button { if Nav.blocked { return }; open(.leg(leg.id)) } label: { FlightRowView(leg: leg) }.buttonStyle(.plain)
                        }
                    }
                }
                let fresh = store.stateJ["alerts"].array.filter { ($0["at"].date ?? .distantPast).timeIntervalSinceNow > -12 * 3600 }.prefix(5)
                if !fresh.isEmpty {
                    SectionHead(title: "Latest Alerts", trailing: nil)
                    AlertsCard(list: Array(fresh), open: open)
                }
                Text("v\(store.stateJ["version"].string ?? "?") · alerts go to \(store.stateJ["notify_target"].string ?? "?") · watching \(store.stateJ["settings"]["watch_hours"].int ?? 0) h before departure")
                    .font(.footnote).foregroundStyle(Th.faint).padding(.vertical, 20)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 90)
            .sheetScroll()
        }
        .refreshable { await store.refresh() }
    }

    /// "1h 12m at FLL" between two legs that connect
    private func layover(_ a: Leg, _ b: Leg) -> AnyView? {
        guard a.arr.code == b.dep.code, !a.extra, !b.extra, let i = a.inn.best, let o = b.out.best else { return nil }
        let gap = o.timeIntervalSince(i)
        guard gap > 0, gap < 14 * 3600 else { return nil }
        let tight = gap < Double(store.minTurn * 60)
        return AnyView(
            HStack(spacing: 4) {
                Text(Fmt.span(gap)).fontWeight(.bold).foregroundStyle(tight ? Th.amber : .white)
                Text("at \(b.dep.code)").foregroundStyle(Th.muted)
            }
            .font(.subheadline)
            .padding(.leading, 66).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Th.line).frame(height: 0.5).padding(.leading, 66) }
        )
    }
}

struct SectionHead: View {
    let title: String
    let trailing: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 21, weight: .bold))
            Spacer()
            if let trailing { Text(trailing).font(.subheadline).foregroundStyle(Th.muted).lineLimit(1) }
        }
        .padding(.top, 14)
    }
}

/// A flight in the list, like the web app's: when, airline and number, status, cities, both times.
struct FlightRowView: View {
    let leg: Leg

    var body: some View {
        let rs = leg.rowStatus
        let dt = Th.lateTone(leg.out.lateMinutes, known: leg.outKnown), at = Th.lateTone(leg.inn.lateMinutes, known: leg.inKnown)
        HStack(alignment: .top, spacing: 0) {
            WhenColumn(when: leg.when).frame(width: 66)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    AirlineBadge(code: leg.airlineCode)
                    Text(leg.display.replacingOccurrences(of: leg.airlineCode, with: leg.airlineCode + " ")).foregroundStyle(Th.muted).lineLimit(1).layoutPriority(1)
                    if leg.deadhead { Tag(text: "DH", color: Th.muted) }
                    if let k = leg.kindTag { Tag(text: k) }
                    Spacer(minLength: 6)
                    Text(rs.0).foregroundStyle(rs.1 ?? Th.muted).lineLimit(1)
                }
                .font(.system(size: 14))
                Text("\(leg.dep.city) to \(leg.arr.city)")
                    .font(.system(size: 18, weight: .semibold)).lineLimit(1)
                    .padding(.top, 2).padding(.bottom, 5)
                HStack(spacing: 14) {
                    timePair(true, leg.dep.code, Fmt.time(leg.out.best, leg.dep.timeZone), dt)
                    timePair(false, leg.arr.code, Fmt.time(leg.inn.best, leg.arr.timeZone), at)
                }
                if let w = leg.warning, !leg.finished, let t = w["text"].string {
                    Text(t).font(.system(size: 13)).foregroundStyle(w["level"].string == "critical" ? Th.red : Th.amber).padding(.top, 6)
                }
            }
            .padding(.vertical, 12).padding(.trailing, 2)
            .overlay(alignment: .bottom) { Rectangle().fill(Th.line).frame(height: 0.5) }
        }
        .contentShape(Rectangle())
        .opacity(leg.finished ? 0.75 : 1)
    }

    private func timePair(_ dep: Bool, _ code: String, _ time: String, _ tone: Color?) -> some View {
        HStack(spacing: 5) {
            DepArrIcon(departure: dep, tone: tone)
            Text(code).foregroundStyle(Th.muted)
            Text(time).fontWeight(.semibold).foregroundStyle(tone ?? .white)
        }
        .font(.system(size: 15))
    }
}

struct WhenColumn: View {
    let when: Leg.When
    var body: some View {
        VStack(spacing: 3) {
            switch when {
            case .icon(let sym, let label, let color):
                Image(systemName: sym).font(.system(size: 15, weight: .bold)).foregroundStyle(color)
                    .frame(width: 38, height: 38).background(color.opacity(0.18), in: Circle())
                Text(label).font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(Th.muted)
            case .count(let n, let unit):
                Text("\(n)").font(.system(size: 30, weight: .bold))
                Text(unit).font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(Th.muted)
            }
        }
        .padding(.top, 14)
    }
}

/// A ground stop, delay program or closure: amber (or red) card, whether it catches your flight.
struct NasAlertCard: View {
    @Environment(Nav.self) private var nav
    let g: NasGroup
    var startOpen = false
    var showMapLink = true
    @State private var expanded = false

    var body: some View {
        let n = g.n
        let color = g.kind == "gs" || g.kind == "closure" ? Th.red : Th.amber
        let label = g.kind == "gdp" && (n["label"].string ?? "").lowercased() == "ground delay program" ? "GDP" : (n["label"].string ?? "")
        let end = n["end"].date, start = n["start"].date
        let when = end.map { e in (start.map { $0 > Date() ? Fmt.time($0, g.tz) + "–" : "until " } ?? "until ") + Fmt.time(e, g.tz) + " " + Fmt.zone(e, g.tz) } ?? ""
        VStack(alignment: .leading, spacing: 8) {
            Button { if Nav.blocked { return }; withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 10) {
                    Text(g.airport).font(.system(size: 17, weight: .heavy))
                    Text(label).font(.system(size: 16, weight: .bold)).foregroundStyle(color)
                    Spacer()
                    Text(when).font(.system(size: 14, weight: .semibold))
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Th.muted).rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            ForEach(Array(hitLines.enumerated()), id: \.offset) { _, l in
                HStack(spacing: 8) {
                    Circle().fill(l.1 == true ? Th.red : l.1 == false ? Th.green : Th.muted).frame(width: 7, height: 7)
                    Text(l.0).font(.system(size: 15, weight: .semibold))
                }
            }
            if expanded {
                let sub = [n["reason"].string?.capitalized, n["detail"].string].compactMap { $0 }.joined(separator: " · ")
                if !sub.isEmpty { Text(sub).font(.subheadline).foregroundStyle(Th.muted) }
                let scope = n["scope"].array.compactMap { $0.string }
                if !scope.isEmpty {
                    // the centers (and airports) whose departures it holds; yours in red
                    let hits = Set(g.uses.flatMap { u in u.impact.filter { !$0["airborne"].bool }.flatMap { [$0["center"].string, $0["from"].string].compactMap { $0 } } })
                    FlowLayout(spacing: 6) {
                        Text("Departures from").font(.system(size: 14)).foregroundStyle(Th.faint).padding(.vertical, 5)
                        ForEach(scope, id: \.self) { c in
                            Text(c).font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(hits.contains(c) ? Th.red : Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
                HStack(spacing: 16) {
                    if showMapLink && ["gs", "gdp"].contains(g.kind) && !n["scope"].array.isEmpty {
                        Button("Map ›") { nav.push(.nas(g.id)) }.font(.footnote.weight(.semibold))
                    }
                    if let adv = n["advisory"].string, let u = URL(string: adv) {
                        Link("FAA advisory ↗", destination: u).font(.footnote.weight(.semibold))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { if startOpen { expanded = true } }
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: Th.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Th.radius, style: .continuous).stroke(color.opacity(0.55), lineWidth: 1))
    }

    /// "Includes UA2677 from BNA (ZME)", true = held, false = not, nil = can't tell
    private var hitLines: [(String, Bool?)] {
        var out: [(String, Bool?)] = []
        for u in g.uses {
            for i in u.impact where !i["airborne"].bool {
                let from = i["from"].string ?? "?"
                let who = i["who"].string == "you" ? "\(u.leg.display) from \(from)" : "\(u.leg.display)'s inbound from \(from)"
                let where_ = i["center"].string.map { " (\($0))" } ?? ""
                if i["hit"].isNull { out.append(("Can't tell if it includes \(who)", nil)) }
                else if i["hit"].bool { out.append(("Includes \(who)\(where_)", true)) }
                else { out.append(("Doesn't include \(who)\(where_) — yet", false)) }
            }
        }
        if out.isEmpty { out = g.uses.map { ("\($0.leg.display) \($0.leg.dep.code)→\($0.leg.arr.code)", nil) } }
        return out
    }
}

/// An FAA delay trend at one of your airports: card with an amber bar on the left.
struct NasTrendCard: View {
    let g: NasGroup
    let many: Bool
    var body: some View {
        let n = g.n
        let sub = [n["detail"].string, n["reason"].string?.capitalized].compactMap { $0 }.joined(separator: " · ")
        HStack(alignment: .top, spacing: 14) {
            Text(g.airport).font(.system(size: 17, weight: .heavy)).padding(.top, 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(n["label"].string ?? "").font(.system(size: 16, weight: .bold))
                if !sub.isEmpty { Text(sub).font(.subheadline).foregroundStyle(Th.muted) }
                if many { Text(g.uses.map { "\($0.leg.display) \($0.leg.dep.code)→\($0.leg.arr.code)" }.joined(separator: " · ")).font(.caption).foregroundStyle(Th.faint) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Th.card, in: RoundedRectangle(cornerRadius: Th.radius, style: .continuous))
        .overlay(alignment: .leading) { UnevenRoundedRectangle(topLeadingRadius: Th.radius, bottomLeadingRadius: Th.radius).fill(Th.amber).frame(width: 4) }
        .overlay(RoundedRectangle(cornerRadius: Th.radius, style: .continuous).stroke(Th.line, lineWidth: 1))
    }
}

/// Alerts as the web app lists them: a colored dot, title and message, time on the right.
struct AlertsCard: View {
    let list: [JSON]
    let open: (Route) -> Void
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, a in
                Button { if Nav.blocked { return }; if let l = a["leg"].string { open(.leg(l)) } } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(color(a["level"].string)).frame(width: 9, height: 9).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a["title"].string ?? "Alert").font(.system(size: 16, weight: .semibold))
                            if let m = a["message"].string { Text(m).font(.system(size: 14)).foregroundStyle(Th.muted) }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Fmt.time(a["at"].date, .current))
                            Text(a["at"].date.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "")
                        }
                        .font(.system(size: 13)).foregroundStyle(Th.faint)
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Th.line).frame(height: 0.5) } }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Th.card, in: RoundedRectangle(cornerRadius: Th.radius, style: .continuous))
    }

    private func color(_ level: String?) -> Color {
        switch level {
        case "critical": return Th.red
        case "warn": return Th.amber
        default: return Th.accent
        }
    }
}

// MARK: - Alerts

struct AlertsView: View {
    @Environment(Store.self) private var store
    let open: (Route) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SheetTitle(title: "Alerts") { EmptyView() }
                if store.alerts.isEmpty {
                    Text("No alerts yet").foregroundStyle(Th.muted).card()
                } else {
                    AlertsCard(list: Array(store.alerts.prefix(200)), open: open)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 90)
            .sheetScroll()
        }
        .task { await store.loadAlerts() }
        .refreshable { await store.loadAlerts() }
    }
}

/// Top left of the map, like the web app: Live (green when the add-on answers, gray on the phone's
/// copy) and Drive backup (green backed up, amber changes waiting, blue uploading, red a problem).
struct StatusPills: View {
    @Environment(Store.self) private var store
    let openSettings: () -> Void
    var body: some View {
        let b = store.stateJ["backup"]
        let st = b["state"].string ?? "off"
        HStack(spacing: 6) {
            // Live once the add-on has answered; Offline showing the saved copy; Connecting until then
            let live = store.connected && !store.offline
            let c: Color = live ? Th.green : store.offline ? Th.muted : Th.amber
            pill(color: c) {
                Circle().fill(c).frame(width: 7, height: 7)
                Text(live ? "Live" : store.offline ? "Offline" : "Connecting").font(.system(size: 12, weight: .bold))
            }
            if st != "off" {
                let c: Color = st == "synced" ? Th.green : st == "waiting" ? Th.amber : st == "syncing" ? Th.accent : Th.red
                Button(action: openSettings) {
                    pill(color: c) {
                        Image(systemName: "icloud.fill").font(.system(size: 11, weight: .bold))
                        Text(st == "syncing" ? "Syncing" : st == "error" ? "Drive !" : st == "disconnected" ? "Drive off" : "Drive").font(.system(size: 12, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func pill<C: View>(color: Color, @ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 5) { c() }
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Color(hex: 0x1C1C1F, alpha: 0.88), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }
}
