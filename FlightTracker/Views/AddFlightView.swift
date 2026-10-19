import SwiftUI

/// Add a flight, like the web app: yours or a friend's; look the number up (AeroAPI, past 9 days to 2
/// days ahead) and pick one, or enter the airports.
struct AddFlightView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let opened: (String) -> Void

    @State private var mine = true
    @State private var ident = ""
    @State private var date = Date()
    @State private var dep = ""
    @State private var arr = ""
    @State private var askAirports = false
    @State private var message: String?
    @State private var messageIsError = false
    @State private var busy = false
    @State private var found: [JSON] = []
    @State private var lookup: JSON = .null
    @FocusState private var focus: Field?
    enum Field { case ident, dep, arr }

    private var homeTZ: TimeZone { store.stateJ["home_tz"].string.flatMap(TimeZone.init(identifier:)) ?? .current }
    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = homeTZ
        return f.string(from: date)
    }
    private var far: Bool { date.timeIntervalSinceNow > 2 * 86400 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Add a Flight").font(.system(size: 32, weight: .bold)).tracking(-0.5)
                    Spacer()
                    RoundButton(symbol: "xmark") { dismiss() }
                }
                .padding(.top, 22)
                VStack(alignment: .leading, spacing: 12) {
                    Segmented(options: ["Mine", "A friend's"], selected: mine ? 0 : 1) { mine = $0 == 0 }
                    Text(mine ? "Tracked like your calendar flights and kept in History." : "Live tracking and pushes only; not saved to History.")
                        .font(.system(size: 14)).foregroundStyle(Th.faint)
                    HStack(spacing: 10) {
                        field("Flight", "UA1234", $ident, .ident)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Date").font(.system(size: 13, weight: .semibold)).foregroundStyle(Th.muted)
                            DatePicker("", selection: $date, in: Date().addingTimeInterval(-9 * 86400)..., displayedComponents: .date)
                                .labelsHidden().environment(\.timeZone, homeTZ)
                                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                                .padding(.horizontal, 8)
                                .background(Th.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    if askAirports {
                        HStack(spacing: 10) {
                            field("From", "EWR", $dep, .dep)
                            field("To", "SFO", $arr, .arr)
                        }
                    }
                    Button { Task { await go() } } label: {
                        Text(busy ? "Working…" : askAirports ? "Add" : "Find flights")
                            .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(canGo ? Th.accent : Th.card2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGo)
                    if let message {
                        Text(message).font(.system(size: 14)).foregroundStyle(messageIsError ? Th.red : Th.muted)
                    }
                }
                .card(16)
                if !found.isEmpty {
                    SectionHead(title: "\(found[0]["display"].string ?? ident) · \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))", trailing: nil)
                    VStack(spacing: 0) {
                        ForEach(Array(found.enumerated()), id: \.offset) { _, f in
                            Button { Task { await add(["ident": lookup["ident"].string ?? ident, "fa_id": f["fa_id"].string ?? "", "date": lookup["date"].string ?? dateString]) } } label: {
                                PickRow(f: f)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("Not listed? Enter the airports") { askAirports = true; found = [] }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Th.accent)
                }
                let manual = store.legs.filter { $0.j["manual"].bool || $0.extra }
                if !manual.isEmpty {
                    SectionHead(title: "Added in the App", trailing: nil)
                    VStack(spacing: 0) { ForEach(manual) { FlightRowView(leg: $0) } }
                }
                Text("Looking up a flight number is one AeroAPI query (the flight you pick reuses it, so tracking doesn't spend another). Your own flights are saved to History when they finish; friends' aren't.")
                    .font(.system(size: 13)).foregroundStyle(Th.faint).padding(.vertical, 10)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Th.sheet.ignoresSafeArea())
        .presentationBackground(Th.sheet)
        .onAppear { askAirports = far; focus = .ident }
        .onChange(of: date) { _, _ in found = []; askAirports = far; message = far ? "More than 2 days out: enter the airports (added right away)." : nil; messageIsError = false }
        .onChange(of: ident) { _, _ in found = []; if !far { askAirports = false } }
    }

    private var canGo: Bool {
        !busy && !ident.trimmingCharacters(in: .whitespaces).isEmpty && (!askAirports || (!dep.isEmpty && !arr.isEmpty))
    }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>, _ f: Field) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Th.muted)
            TextField(placeholder, text: text)
                .font(.system(size: 17, weight: .semibold))
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .focused($focus, equals: f)
                .submitLabel(.go)
                .onSubmit { Task { await go() } }
                .padding(.horizontal, 12).frame(minHeight: 46)
                .background(Th.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func go() async {
        guard canGo else { return }
        let id = ident.uppercased().replacingOccurrences(of: " ", with: "")
        if askAirports {
            await add(["ident": id, "dep": dep.uppercased(), "arr": arr.uppercased(), "date": dateString])
            return
        }
        busy = true
        messageIsError = false
        message = "Looking up…"
        defer { busy = false }
        do {
            let r = try await API.get("api/lookup?ident=\(id)&date=\(dateString)", keep: false)
            let d = r.0
            if let e = d["error"].string { message = e; messageIsError = true; return }
            if d["mode"].string != "list" { askAirports = true; message = d["reason"].string; return }
            let list = d["flights"].array
            if list.isEmpty { askAirports = true; message = "No \(id) flights found on \(dateString). Check the number, or enter the airports."; return }
            lookup = d
            found = list
            message = nil
            focus = nil
        } catch {
            askAirports = true
            message = "Couldn't look it up (\(error.localizedDescription)). Enter the airports."
        }
    }

    private func add(_ body: [String: String]) async {
        busy = true
        messageIsError = false
        message = "Adding…"
        defer { busy = false }
        var b: [String: Any] = body
        b["kind"] = mine ? "manual" : "friend"
        do {
            let d = try await API.post("api/flights", body: b)
            await store.refresh()
            if let id = d["id"].string { opened(id) } else { dismiss() }
        } catch {
            message = "Couldn't add it: \(error.localizedDescription)"
            messageIsError = true
        }
    }
}

/// A flight found by the lookup, drawn like a row in My Flights, with a + where the countdown goes.
private struct PickRow: View {
    let f: JSON
    var body: some View {
        let otz = f["dep_tz"].string.flatMap(TimeZone.init(identifier:)) ?? .current
        let atz = f["arr_tz"].string.flatMap(TimeZone.init(identifier:)) ?? .current
        let out = Times(f["out"]), inn = Times(f["in"])
        let so = out.estimated ?? out.scheduled, si = inn.estimated ?? inn.scheduled
        let late = (out.scheduled.flatMap { s in so.map { $0.timeIntervalSince(s) } } ?? 0) >= 300
        let disp = f["display"].string ?? ""
        let al = String(disp.prefix(2))
        HStack(alignment: .top, spacing: 0) {
            Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(Th.accent)
                .frame(width: 38, height: 38).background(Th.accent.opacity(0.18), in: Circle())
                .frame(width: 66).padding(.top, 14)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    AirlineBadge(code: al)
                    Text(disp.replacingOccurrences(of: al, with: al + " ")).foregroundStyle(Th.muted)
                    Spacer()
                    Text(f["cancelled"].bool ? "Cancelled" : (f["status"].string ?? "")).foregroundStyle(f["cancelled"].bool ? Th.red : late ? Th.amber : Th.muted).lineLimit(1)
                }
                .font(.system(size: 14))
                Text("\(f["dep_city"].string ?? f["dep"].string ?? "") to \(f["arr_city"].string ?? f["arr"].string ?? "")")
                    .font(.system(size: 18, weight: .semibold)).lineLimit(1).padding(.top, 2).padding(.bottom, 5)
                HStack(spacing: 14) {
                    HStack(spacing: 5) { DepArrIcon(departure: true, tone: late ? Th.amber : nil); Text(f["dep"].string ?? "").foregroundStyle(Th.muted); Text(Fmt.time(so, otz)).fontWeight(.semibold).foregroundStyle(late ? Th.amber : .white) }
                    HStack(spacing: 5) { DepArrIcon(departure: false); Text(f["arr"].string ?? "").foregroundStyle(Th.muted); Text(Fmt.time(si, atz)).fontWeight(.semibold) }
                }
                .font(.system(size: 15))
                let ac = [f["aircraft_type"].string, f["tail"].string].compactMap { $0 }.joined(separator: " · ")
                if !ac.isEmpty { Text(ac).font(.system(size: 13)).foregroundStyle(Th.muted).padding(.top, 6) }
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(Th.line).frame(height: 0.5) }
        }
        .contentShape(Rectangle())
    }
}

/// The web app's two- or three-way switch.
struct Segmented: View {
    let options: [String]
    let selected: Int
    let pick: (Int) -> Void
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                Button { pick(i) } label: {
                    Text(o).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(i == selected ? .white : Th.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(i == selected ? Th.card2.opacity(1) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
