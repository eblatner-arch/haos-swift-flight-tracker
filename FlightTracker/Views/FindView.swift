import SwiftUI

/// Search everything you've flown, like the web app's Find: words (flight, airport, route, tail,
/// aircraft, month, weekday, gate...), ">30" for 30+ min late, "<-5" for 5+ early, status chips, and
/// more filters: year, month, from, to, either airport, route, aircraft, tail, departure hour, day,
/// how late, and sort.
struct FindView: View {
    @Environment(Store.self) private var store
    @Environment(Nav.self) private var nav
    /// filters to start with, as the web app's address has them: year, st, sort, hr, route, ap, ac, tail
    var preset: String = ""
    @State private var all: [JSON] = []
    @State private var q = ""
    @State private var chips: Set<String> = []
    @State private var more = false
    @State private var year = ""
    @State private var month = 0
    @State private var from = ""
    @State private var to = ""
    @State private var either = ""
    @State private var route = ""
    @State private var aircraft = ""
    @State private var tail = ""
    @State private var hour = -1
    @State private var dow = -1
    @State private var minLate = ""
    @State private var maxLate = ""
    @State private var sort = "new"
    @FocusState private var typing: Bool

    private let statusChips = [("late15", "Late 15+"), ("late30", "Late 30+"), ("late60", "Late 60+"), ("ontime", "On time"), ("early", "Early"),
                               ("diverted", "Diverted"), ("cancelled", "Cancelled"), ("notrack", "No track")]
    private static let dows = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    var body: some View {
        let res = results
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Find").font(.system(size: 32, weight: .bold)).tracking(-0.5)
                    Spacer()
                    RoundButton(symbol: "xmark") { nav.back() }
                }
                .padding(.top, 18)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Th.muted)
                    TextField("Flight, airport, tail, aircraft, month, >30…", text: $q)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled().focused($typing)
                    if !q.isEmpty { Button { if Nav.blocked { return }; q = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Th.muted) }.buttonStyle(.plain) }
                }
                .padding(.horizontal, 12).padding(.vertical, 11)
                .background(Th.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                FlowLayout(spacing: 7) {
                    ForEach(statusChips, id: \.0) { c in
                        let on = chips.contains(c.0)
                        Button { if Nav.blocked { return }; if on { chips.remove(c.0) } else { chips.insert(c.0) } } label: {
                            Text(c.1).font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(on ? .white : Th.muted)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(on ? Th.accent : Th.card, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Fold(title: "More filters" + (activeFilters > 0 ? " · \(activeFilters)" : "")) { filters }
                summary(res)
                ForEach(groups(res), id: \.0) { g in
                    if !g.0.isEmpty { Text(g.0).font(.system(size: 19, weight: .bold)).padding(.top, 8) }
                    LazyVStack(spacing: 0) {
                        ForEach(Array(g.1.enumerated()), id: \.offset) { _, f in
                            Button { if Nav.blocked { return }; if let id = f["id"].string { nav.push(.hist(id)) } } label: { FindRow(f: f) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(Th.card, in: RoundedRectangle(cornerRadius: Th.radius, style: .continuous))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 100)
            .sheetScroll()
        }
        .scrollDismissesKeyboard(.interactively)
        .task {
            // the saved copy right away, the fresh one when it comes
            if all.isEmpty, let d = Disk.load("api/history"), let j = try? JSON.parse(d) { all = j["flights"].array }
            if preset.isEmpty {
                Task { try? await Task.sleep(for: .milliseconds(380)); typing = true }   // after the sheet has opened
            } else { applyPreset() }
            if let r = try? await API.get("api/history") { all = r.0["flights"].array }
        }
    }

    private func applyPreset() {
        let items = URLComponents(string: "?" + preset)?.queryItems ?? []
        for it in items {
            guard let v = it.value, !v.isEmpty else { continue }
            switch it.name {
            case "year": year = v
            case "st": chips.insert(v)
            case "sort": sort = v
            case "hr": hour = (Int(v.prefix(2)) ?? -3) / 3
            case "route": route = v.replacingOccurrences(of: "–", with: "-")
            case "ap": either = v
            case "ac": aircraft = v
            case "tail": tail = v
            default: break
            }
        }
        more = true
    }

    private var filters: some View {
        let years = Array(Set(all.compactMap { $0["date"].string.map { String($0.prefix(4)) } })).sorted(by: >)
        let types = Array(Set(all.compactMap { $0["aircraft"].string ?? $0["type"].string })).sorted()
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                menu("Year", year.isEmpty ? "Any" : year, [("Any", "")] + years.map { ($0, $0) }) { year = $0 }
                menu("Month", month == 0 ? "Any" : Self.months[month - 1], [("Any", "0")] + (1...12).map { (Self.months[$0 - 1], "\($0)") }) { month = Int($0) ?? 0 }
            }
            HStack(spacing: 10) { box("From", "EWR", $from); box("To", "FLL", $to) }
            HStack(spacing: 10) { box("Either airport", "MCO", $either); box("Route", "EWR-FLL", $route) }
            HStack(spacing: 10) {
                menu("Aircraft", aircraft.isEmpty ? "Any" : aircraft, [("Any", "")] + types.map { ($0, $0) }) { aircraft = $0 }
                box("Tail", "N37413", $tail)
            }
            HStack(spacing: 10) {
                menu("Departs (local)", hour < 0 ? "Any" : String(format: "%02d–%02d", hour * 3, hour * 3 + 3), [("Any", "-1")] + (0..<8).map { (String(format: "%02d–%02d", $0 * 3, $0 * 3 + 3), "\($0)") }) { hour = Int($0) ?? -1 }
                menu("Day", dow < 0 ? "Any" : Self.dows[dow], [("Any", "-1")] + (0..<7).map { (Self.dows[$0], "\($0)") }) { dow = Int($0) ?? -1 }
            }
            HStack(spacing: 10) { box("Late at least", "min", $minLate, numbers: true); box("Late at most", "min (−5 = early)", $maxLate, numbers: true) }
            menu("Sort", ["new": "Newest", "old": "Oldest", "late": "Latest arrival", "early": "Earliest arrival", "long": "Longest distance", "block": "Longest gate to gate"][sort] ?? "Newest",
                 [("Newest", "new"), ("Oldest", "old"), ("Latest arrival", "late"), ("Earliest arrival", "early"), ("Longest distance", "long"), ("Longest gate to gate", "block")]) { sort = $0 }
            if activeFilters > 0 {
                Button("Clear all") { year = ""; month = 0; from = ""; to = ""; either = ""; route = ""; aircraft = ""; tail = ""; hour = -1; dow = -1; minLate = ""; maxLate = ""; sort = "new"; chips = []; q = "" }
                    .font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .card()
    }

    private var activeFilters: Int {
        [!year.isEmpty, month > 0, !from.isEmpty, !to.isEmpty, !either.isEmpty, !route.isEmpty, !aircraft.isEmpty, !tail.isEmpty, hour >= 0, dow >= 0, !minLate.isEmpty, !maxLate.isEmpty, sort != "new"].filter { $0 }.count
    }

    private func box(_ label: String, _ ph: String, _ t: Binding<String>, numbers: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Th.muted)
            TextField(ph, text: t).textInputAutocapitalization(.characters).autocorrectionDisabled()
                .keyboardType(numbers ? .numbersAndPunctuation : .default)
                .padding(.horizontal, 10).frame(minHeight: 40)
                .background(Th.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    private func menu(_ label: String, _ value: String, _ items: [(String, String)], _ pick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Th.muted)
            Menu {
                ForEach(items, id: \.1) { it in Button(it.0) { pick(it.1) } }
            } label: {
                HStack { Text(value).foregroundStyle(.white); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Th.muted) }
                    .padding(.horizontal, 10).frame(minHeight: 40)
                    .background(Th.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: matching

    private static func depTime(_ f: JSON) -> Double {
        let t = f["times"]
        return t["out"]["s"].double ?? t["out"]["a"].double ?? t["off"]["s"].double ?? t["off"]["a"].double ?? 0
    }

    /// worked out once per flight (a calendar per flight per keystroke was the slow part)
    @MainActor private static var localCache: [String: (hour: Int, dow: Int, month: String)] = [:]
    @MainActor private static var hayCache: [String: String] = [:]

    @MainActor private static func local(_ f: JSON) -> (hour: Int, dow: Int, month: String) {
        let key = f["id"].string ?? ""
        if let c = localCache[key] { return c }
        let v = localCalc(f)
        if !key.isEmpty { localCache[key] = v }
        return v
    }

    private static func localCalc(_ f: JSON) -> (hour: Int, dow: Int, month: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = f["dep_tz"].string.flatMap(TimeZone.init(identifier:)) ?? .current
        let d = Date(timeIntervalSince1970: depTime(f))
        let c = cal.dateComponents([.hour, .weekday, .month], from: d)
        let full = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        return (c.hour ?? 0, (c.weekday ?? 1) - 1, full[max(0, (c.month ?? 1) - 1)])
    }

    @MainActor private static func hay(_ f: JSON) -> String {
        let key = f["id"].string ?? ""
        if let h = hayCache[key] { return h }
        let v = hayCalc(f)
        if !key.isEmpty { hayCache[key] = v }
        return v
    }

    @MainActor private static func hayCalc(_ f: JSON) -> String {
        let l = local(f)
        let parts: [String?] = [f["ident"].string, f["display"].string, f["display"].string?.replacingOccurrences(of: " ", with: ""), f["flight_no"].string,
                                f["dep"].string, f["arr"].string, f["diverted_to"].string,
                                "\(f["dep"].string ?? "")-\(f["arr"].string ?? "")", "\(f["dep"].string ?? "")\(f["arr"].string ?? "")",
                                f["tail"].string, f["aircraft"].string, f["type"].string,
                                f["dep_gate"].string.map { "gate \($0)" }, f["arr_gate"].string.map { "gate \($0)" },
                                f["date"].string, l.month, dows[l.dow].lowercased(),
                                f["diverted_to"].string != nil ? "diverted divert" : nil, f["cancelled"].bool ? "cancelled" : nil, f["route"].string]
        return parts.compactMap { $0 }.joined(separator: " ").lowercased()
    }

    private func status(_ f: JSON, _ st: String) -> Bool {
        let d = f["arr_delay"].double
        switch st {
        case "late15": return (d ?? -1e9) >= 15
        case "late30": return (d ?? -1e9) >= 30
        case "late60": return (d ?? -1e9) >= 60
        case "ontime": return d != nil && d! < 15 && !f["cancelled"].bool
        case "early": return d != nil && d! <= -5
        case "diverted": return f["diverted_to"].string != nil
        case "cancelled": return f["cancelled"].bool
        case "notrack": return !f["has_track"].bool && !f["cancelled"].bool
        default: return true
        }
    }

    private var results: [JSON] {
        let toks = q.lowercased().split(separator: " ").map(String.init)
        let up = { (s: String) in s.trimmingCharacters(in: .whitespaces).uppercased() }
        let starts = { (x: String?, v: String) in x.map { $0.hasPrefix(up(v)) } ?? false }
        let r = up(route).replacingOccurrences(of: #"[^A-Z0-9]+"#, with: " ", options: .regularExpression)
        var rp = r.split(separator: " ").map(String.init)
        if rp.count == 1, rp[0].count == 6 { rp = [String(rp[0].prefix(3)), String(rp[0].suffix(3))] }
        let minD = Double(minLate), maxD = Double(maxLate)
        let out = all.filter { f in
            if !year.isEmpty && !(f["date"].string ?? "").hasPrefix(year) { return false }
            if month > 0 && Int((f["date"].string ?? "").dropFirst(5).prefix(2)) != month { return false }
            if let a = rp.first, !a.isEmpty {
                if !starts(f["dep"].string, a) { return false }
                if rp.count > 1, !starts(f["diverted_to"].string ?? f["arr"].string, rp[1]) && !starts(f["arr"].string, rp[1]) { return false }
            }
            if !from.isEmpty && !starts(f["dep"].string, from) { return false }
            if !to.isEmpty && !starts(f["arr"].string, to) && !starts(f["diverted_to"].string, to) { return false }
            if !either.isEmpty && ![f["dep"].string, f["arr"].string, f["diverted_to"].string].contains(where: { starts($0, either) }) { return false }
            if !tail.isEmpty {
                var t = up(tail); if let c = t.first, c.isNumber { t = "N" + t }
                if !(f["tail"].string ?? "").uppercased().contains(t) { return false }
            }
            if !aircraft.isEmpty && (f["aircraft"].string ?? f["type"].string ?? "") != aircraft { return false }
            if hour >= 0 || dow >= 0 {
                let l = Self.local(f)
                if hour >= 0 && l.hour / 3 != hour { return false }
                if dow >= 0 && l.dow != dow { return false }
            }
            for c in chips where !status(f, c) { return false }
            let d = f["arr_delay"].double
            if let minD, !(d.map { $0 >= minD } ?? false) { return false }
            if let maxD, !(d.map { $0 <= maxD } ?? false) { return false }
            if !toks.isEmpty {
                let h = Self.hay(f)
                for t in toks {
                    if let m = t.range(of: #"^([<>]=?)(-?\d+)m?$"#, options: .regularExpression) {
                        let s = String(t[m]), gt = s.hasPrefix(">")
                        let n = Double(s.trimmingCharacters(in: CharacterSet(charactersIn: "<>=m"))) ?? 0
                        guard let d, gt ? d >= n : d <= n else { return false }
                    } else if !h.contains(t) { return false }
                }
            }
            return true
        }
        let dep = { (f: JSON) in Self.depTime(f) }
        switch sort {
        case "old": return out.sorted { dep($0) < dep($1) }
        case "late": return out.sorted { ($0["arr_delay"].double ?? -1e9) > ($1["arr_delay"].double ?? -1e9) }
        case "early": return out.sorted { ($0["arr_delay"].double ?? 1e9) < ($1["arr_delay"].double ?? 1e9) }
        case "long": return out.sorted { ($0["distance_nm"].double ?? 0) > ($1["distance_nm"].double ?? 0) }
        case "block": return out.sorted { ($0["block_min"].double ?? 0) > ($1["block_min"].double ?? 0) }
        default: return out.sorted { dep($0) > dep($1) }
        }
    }

    private func summary(_ res: [JSON]) -> some View {
        let dl = res.compactMap { $0["arr_delay"].double }
        let ot = dl.isEmpty ? nil : Int((100 * Double(dl.filter { $0 < 15 }.count) / Double(dl.count)).rounded())
        let avg = dl.isEmpty ? nil : dl.reduce(0, +) / Double(dl.count)
        let dist = res.reduce(0.0) { $0 + ($1["cancelled"].bool ? 0 : ($1["distance_nm"].double ?? 0)) }
        var t = Text("\(res.count)").bold() + Text(" flight\(res.count == 1 ? "" : "s")")
        if let ot, let avg { t = t + Text(" · \(ot)% on time · " + (avg >= 1 ? "usually \(Int(avg.rounded())) min late" : "usually on time")) }
        if dist > 0 { t = t + Text(" · \(Int(dist).formatted()) nm") }
        return t.font(.system(size: 15)).foregroundStyle(Th.muted).padding(.top, 4)
    }

    /// by month when sorted by date, else one list
    private func groups(_ res: [JSON]) -> [(String, [JSON])] {
        let list = Array(res.prefix(600))
        guard sort == "new" || sort == "old" else { return list.isEmpty ? [] : [("", list)] }
        var order: [String] = [], by: [String: [JSON]] = [:]
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        for x in list {
            f.timeZone = x["dep_tz"].string.flatMap(TimeZone.init(identifier:)) ?? .current
            let k = f.string(from: Date(timeIntervalSince1970: Self.depTime(x)))
            if by[k] == nil { order.append(k) }
            by[k, default: []].append(x)
        }
        return order.map { ($0, by[$0] ?? []) }
    }
}

struct FindRow: View {
    let f: JSON
    var body: some View {
        let al = f["airline"].string == "UAL" ? "UA" : (f["airline"].string ?? "")
        let d = f["arr_delay"].int
        HStack(spacing: 12) {
            AirlineBadge(code: al, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text((f["display"].string ?? "Flight").replacingOccurrences(of: al, with: al + " ")).font(.system(size: 15, weight: .semibold))
                    Text("\(f["dep"].string ?? "?") → \(f["diverted_to"].string ?? f["arr"].string ?? "?")").font(.system(size: 15)).foregroundStyle(Th.muted)
                    if f["cancelled"].bool { Text("CANCELLED").font(.caption2.weight(.bold)).foregroundStyle(Th.red) }
                    else if f["diverted_to"].string != nil { Text("DIVERTED").font(.caption2.weight(.bold)).foregroundStyle(Th.red) }
                }
                Text([f["date"].string, f["aircraft"].string, f["tail"].string].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 13)).foregroundStyle(Th.muted).lineLimit(1)
            }
            Spacer()
            if let d, !f["cancelled"].bool {
                Text(Fmt.lateWord(d)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Th.tone(d) ?? Th.muted)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Th.line).frame(height: 0.5) }
        .contentShape(Rectangle())
    }
}

/// Lays its children out in rows, wrapping like text (chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > w { x = 0; y += rowH + spacing; rowH = 0 }
            x += z.width + spacing; rowH = max(rowH, z.height)
        }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + z.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + spacing; rowH = max(rowH, z.height)
        }
    }
}
