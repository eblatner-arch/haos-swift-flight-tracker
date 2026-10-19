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
    @State private var busy = false
    @State private var found: [JSON] = []
    @State private var lookup: JSON = .null

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = store.stateJ["home_tz"].string.flatMap(TimeZone.init(identifier:)) ?? .current
        return f.string(from: date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("", selection: $mine) {
                        Text("Mine").tag(true)
                        Text("A friend's").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Text(mine ? "Tracked like your calendar flights and kept in History." : "Live tracking and pushes only; not saved to History.")
                        .font(.footnote).foregroundStyle(Th.muted)
                }
                Section {
                    TextField("Flight (UA1234)", text: $ident)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .onChange(of: ident) { _, _ in found = []; if !far { askAirports = false } }
                    DatePicker("Date", selection: $date, in: Date().addingTimeInterval(-9 * 86400)..., displayedComponents: .date)
                        .onChange(of: date) { _, _ in found = []; askAirports = far }
                    if askAirports {
                        TextField("From (EWR)", text: $dep).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        TextField("To (SFO)", text: $arr).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    }
                }
                Section {
                    Button(busy ? "Working…" : askAirports ? "Add" : "Find flights") { Task { await go() } }
                        .disabled(busy || ident.trimmingCharacters(in: .whitespaces).isEmpty || (askAirports && (dep.isEmpty || arr.isEmpty)))
                    if let message { Text(message).font(.footnote).foregroundStyle(Th.muted) }
                }
                if !found.isEmpty {
                    Section("\(found[0]["display"].string ?? ident)") {
                        ForEach(Array(found.enumerated()), id: \.offset) { _, f in
                            Button { Task { await add(["ident": lookup["ident"].string ?? ident, "fa_id": f["fa_id"].string ?? "", "date": lookup["date"].string ?? dateString]) } } label: {
                                pickRow(f)
                            }
                            .buttonStyle(.plain)
                        }
                        Button("Not listed? Enter the airports") { askAirports = true; found = [] }.font(.footnote)
                    }
                }
                Section {
                    Text("Looking up a flight number is one AeroAPI query (the flight you pick reuses it). More than 2 days out, enter the airports: it's added right away.")
                        .font(.footnote).foregroundStyle(Th.muted)
                }
            }
            .navigationTitle("Add a Flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onAppear { askAirports = far }
    }

    private var far: Bool { date.timeIntervalSinceNow > 2 * 86400 }

    private func pickRow(_ f: JSON) -> some View {
        let otz = f["dep_tz"].string.flatMap(TimeZone.init(identifier:)) ?? .current
        let atz = f["arr_tz"].string.flatMap(TimeZone.init(identifier:)) ?? .current
        let so = Times(f["out"]).estimated ?? Times(f["out"]).scheduled, si = Times(f["in"]).estimated ?? Times(f["in"]).scheduled
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(f["dep_city"].string ?? f["dep"].string ?? "") to \(f["arr_city"].string ?? f["arr"].string ?? "")").font(.headline)
                Spacer()
                Text(f["cancelled"].bool ? "Cancelled" : (f["status"].string ?? "")).font(.caption).foregroundStyle(f["cancelled"].bool ? Th.red : Th.muted)
            }
            HStack(spacing: 14) {
                Text("\(f["dep"].string ?? "") \(Fmt.time(so, otz))")
                Text("\(f["arr"].string ?? "") \(Fmt.time(si, atz))")
            }
            .font(.subheadline)
            let ac = [f["aircraft_type"].string, f["tail"].string].compactMap { $0 }.joined(separator: " · ")
            if !ac.isEmpty { Text(ac).font(.caption).foregroundStyle(Th.muted) }
        }
        .contentShape(Rectangle())
    }

    private func go() async {
        let id = ident.uppercased().replacingOccurrences(of: " ", with: "")
        if askAirports {
            await add(["ident": id, "dep": dep.uppercased(), "arr": arr.uppercased(), "date": dateString])
            return
        }
        busy = true
        message = "Looking up…"
        defer { busy = false }
        do {
            let r = try await API.get("api/lookup?ident=\(id)&date=\(dateString)", keep: false)
            let d = r.0
            if let e = d["error"].string { message = e; return }
            if d["mode"].string != "list" { askAirports = true; message = d["reason"].string; return }
            let list = d["flights"].array
            if list.isEmpty { askAirports = true; message = "No \(id) flights found on \(dateString). Check the number, or enter the airports."; return }
            lookup = d
            found = list
            message = nil
        } catch {
            askAirports = true
            message = "Couldn't look it up (\(error.localizedDescription)). Enter the airports."
        }
    }

    private func add(_ body: [String: String]) async {
        busy = true
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
        }
    }
}
