import SwiftUI

/// Settings: this app (address, time format), and the add-on's own settings and alert rules (the same
/// ones as the web app's Settings page, saved in the add-on).
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let addFlight: () -> Void
    @AppStorage(API.serverKey) private var server = ""
    @AppStorage("h24") private var h24 = false
    @AppStorage("mapGlobe") private var globe = false
    @AppStorage("mapDark") private var dark = false
    @AppStorage("lowData") private var lowData = false
    @AppStorage("mapDays") private var mapDays = 0
    @State private var testMsg: String?
    @State private var testResult: String?
    @State private var testing = false
    @State private var checking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { addFlight() } label: { Label("Add a flight", systemImage: "plus.circle.fill") }
                    Button {
                        checking = true
                        Task { _ = try? await API.post("api/refresh"); try? await Task.sleep(for: .seconds(2)); await store.refresh(); checking = false }
                    } label: { Label(checking ? "Checking…" : "Check all flights now", systemImage: "arrow.clockwise") }
                    NavigationLink { RulesView() } label: { Label("Alerts", systemImage: "bell.badge") }
                    NavigationLink { AddonSettingsView() } label: { Label("Tracking", systemImage: "slider.horizontal.3") }
                    NavigationLink { BackupView() } label: { Label("Backup (Google Drive)", systemImage: "icloud") }
                    NavigationLink { SetupCheckView() } label: { Label("Setup check", systemImage: "stethoscope") }
                    Button {
                        testMsg = "Sending…"
                        Task { testMsg = (try? await API.post("api/test-notify")) != nil ? "Sent: check your phone." : "Couldn't send." }
                    } label: { Label("Send a test notification", systemImage: "paperplane") }
                    if let testMsg { Text(testMsg).font(.footnote).foregroundStyle(Th.muted) }
                }
                Section {
                    TextField("https://ericsflights.duckdns.org:8090", text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(testing ? "Checking…" : "Test connection") { Task { await test() } }
                        .disabled(testing || server.isEmpty)
                    if let testResult { Text(testResult).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("Add-on address")
                } footer: {
                    Text("The add-on's direct https address (the same one the web app uses outside Home Assistant).")
                }
                Section {
                    Text("In the web app: Settings → Notifications → turn on **Open alerts in the iPhone app**. Tapping a Home Assistant alert then opens the flight here.")
                        .font(.footnote)
                    LabeledContent("Link", value: "\(linkScheme)://leg/…")
                } header: {
                    Text("Notifications")
                }
                Section {
                    Toggle("24-hour time", isOn: $h24)
                    Toggle("Globe", isOn: $globe)
                    Toggle("Dark map (no satellite)", isOn: $dark)
                    Toggle("Data saver", isOn: $lowData)
                    Picker("Routes on the home map", selection: $mapDays) {
                        Text("All upcoming").tag(0)
                        Text("Next 3 days").tag(3)
                        Text("Next 7 days").tag(7)
                        Text("Next 14 days").tag(14)
                        Text("Next 30 days").tag(30)
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text("Globe looks like Flighty but has to zoom out further to fit your routes; flat frames them exactly. Data saver: live position every 15 s instead of 5.")
                }
                Section {
                    if let u = API.base { Link("Open the web app (backup, history import, everything else)", destination: u) }
                    LabeledContent("App", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                    LabeledContent("Add-on", value: store.stateJ["version"].string ?? "?")
                    if let u = store.updated { LabeledContent("Last update", value: u.formatted(date: .omitted, time: .shortened)) }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                        Task { await store.refresh() }
                    }
                }
            }
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        do {
            let r = try await API.get("api/state", keep: false)
            let n = r.0["legs"].array.count
            let v = r.0["version"].string ?? "?"
            testResult = "Connected: add-on \(v), \(n) flight\(n == 1 ? "" : "s")"
        } catch {
            testResult = "Couldn't connect: \(error.localizedDescription)"
        }
    }
}

/// The add-on's tracking settings (api/settings): numbers and switches, grouped like the web app.
private struct AddonSettingsView: View {
    @State private var items: [JSON] = []
    @State private var values: [String: Double] = [:]
    @State private var flags: [String: Bool] = [:]
    @State private var saved = ""

    var body: some View {
        Form {
            ForEach(groups, id: \.self) { g in
                Section(g) {
                    ForEach(Array(items.filter { ($0["group"].string ?? "Tracking") == g }.enumerated()), id: \.offset) { _, it in
                        row(it)
                    }
                }
            }
            if !saved.isEmpty { Text(saved).font(.footnote).foregroundStyle(Th.muted) }
        }
        .navigationTitle("Tracking")
        .task { await load() }
    }

    private var groups: [String] {
        var out: [String] = []
        for it in items { let g = it["group"].string ?? "Tracking"; if !out.contains(g) { out.append(g) } }
        return out
    }

    @ViewBuilder private func row(_ it: JSON) -> some View {
        let key = it["key"].string ?? ""
        VStack(alignment: .leading, spacing: 4) {
            if it["kind"].string == "bool" {
                Toggle(it["label"].string ?? key, isOn: Binding(get: { flags[key] ?? false }, set: { flags[key] = $0; Task { await save() } }))
            } else {
                let lo = it["min"].double ?? 0, hi = it["max"].double ?? 999
                Stepper(value: Binding(get: { values[key] ?? lo }, set: { values[key] = $0; Task { await save() } }), in: lo...hi, step: hi - lo > 100 ? 5 : 1) {
                    HStack {
                        Text(it["label"].string ?? key)
                        Spacer()
                        Text("\(Int(values[key] ?? lo))").foregroundStyle(Th.muted).monospacedDigit()
                    }
                }
            }
            if let h = it["help"].string { Text(h).font(.caption).foregroundStyle(Th.muted) }
        }
    }

    private func load() async {
        guard let r = try? await API.get("api/settings", keep: false) else { return }
        items = r.0["settings"].array
        for it in items {
            guard let k = it["key"].string else { continue }
            if it["kind"].string == "bool" { flags[k] = it["value"].bool } else { values[k] = it["value"].double ?? 0 }
        }
    }

    private func save() async {
        var body: [String: Any] = [:]
        for (k, v) in values { body[k] = Int(v) }
        for (k, v) in flags { body[k] = v }
        if (try? await API.post("api/settings", body: ["settings": body])) != nil { saved = "Saved" } else { saved = "Couldn't save" }
    }
}

/// Which alerts the add-on sends (api/rules), each with all of its options, like the web app:
/// on/off, from how many hours before departure, time-sensitive delivery, which kinds of flights, and
/// its thresholds.
private struct RulesView: View {
    @State private var rules: [JSON] = []

    var body: some View {
        Form {
            ForEach(groups, id: \.self) { g in
                Section(g) {
                    ForEach(rules.filter { ($0["group"].string ?? "") == g }, id: \.self) { r in
                        NavigationLink { RuleEditor(row: r, saved: { updated in replace(updated) }) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r["label"].string ?? "")
                                    Text(summary(r)).font(.caption).foregroundStyle(Th.muted)
                                }
                                Spacer()
                                Text(r["rule"]["on"].bool ? "On" : "Off").foregroundStyle(r["rule"]["on"].bool ? Th.green : Th.muted)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Alerts")
        .task {
            guard let r = try? await API.get("api/rules", keep: false) else { return }
            rules = r.0["rules"].array
        }
    }

    private func replace(_ list: [JSON]) { if !list.isEmpty { rules = list } }

    private func summary(_ r: JSON) -> String {
        let x = r["rule"]
        guard x["on"].bool else { return r["desc"].string ?? "" }
        var parts: [String] = []
        let kinds = [("calendar", "calendar"), ("manual", "mine"), ("friends", "friends'")].filter { x[$0.0].bool }.map(\.1)
        if !kinds.isEmpty { parts.append(kinds.joined(separator: ", ")) }
        if let h = x["hours"].double { parts.append("from \(h.formatted()) h out") }
        if x["ts"].bool { parts.append("time-sensitive") }
        for p in r["params"].array { if let n = p["name"].string, let v = x["params"][n].int { parts.append("\(v) \(p["unit"].string ?? "")") } }
        return parts.joined(separator: " · ")
    }

    private var groups: [String] {
        var out: [String] = []
        for r in rules { let g = r["group"].string ?? ""; if !out.contains(g) { out.append(g) } }
        return out
    }
}

private struct RuleEditor: View {
    let row: JSON
    let saved: ([JSON]) -> Void
    @State private var on = false
    @State private var ts = false
    @State private var anyTime = true
    @State private var hours: Double = 2
    @State private var kinds: [String: Bool] = [:]
    @State private var params: [String: Double] = [:]
    @State private var msg = ""

    var body: some View {
        let key = row["key"].string ?? ""
        Form {
            Section {
                Toggle("On", isOn: $on)
                Text(row["desc"].string ?? "").font(.footnote).foregroundStyle(Th.muted)
            }
            if on {
                Section("For") {
                    ForEach([("calendar", "Calendar flights"), ("manual", "Flights you added"), ("friends", "Friends' flights")], id: \.0) { k in
                        if !row["rule"][k.0].isNull {
                            Toggle(k.1, isOn: Binding(get: { kinds[k.0] ?? false }, set: { kinds[k.0] = $0 }))
                        }
                    }
                }
                Section {
                    Toggle("Any time", isOn: $anyTime)
                    if !anyTime {
                        Stepper(value: $hours, in: 0.5...48, step: 0.5) { Text("From \(hours.formatted()) h before departure") }
                    }
                } header: { Text("When") } footer: { Text("Held back until then, and sent when the window opens.") }
                Section {
                    Toggle("Time-sensitive", isOn: $ts)
                } footer: { Text("Breaks through Focus and stays on the lock screen.") }
                let ps = row["params"].array
                if !ps.isEmpty {
                    Section("Threshold") {
                        ForEach(ps, id: \.self) { p in
                            let n = p["name"].string ?? ""
                            Stepper(value: Binding(get: { params[n] ?? 0 }, set: { params[n] = $0 }), in: 0...600, step: 5) {
                                Text("\(p["label"].string ?? n): \(Int(params[n] ?? 0)) \(p["unit"].string ?? "")")
                            }
                        }
                    }
                }
            }
            if !msg.isEmpty { Text(msg).font(.footnote).foregroundStyle(Th.muted) }
        }
        .navigationTitle(row["label"].string ?? "Alert")
        .onAppear {
            let x = row["rule"]
            on = x["on"].bool; ts = x["ts"].bool
            if let h = x["hours"].double { anyTime = false; hours = h } else { anyTime = true }
            for k in ["calendar", "manual", "friends"] where !x[k].isNull { kinds[k] = x[k].bool }
            for (k, v) in x["params"].object { params[k] = v.double ?? 0 }
        }
        .onDisappear {
            var body: [String: Any] = ["on": on, "ts": ts, "hours": anyTime ? "" : String(hours)]
            for (k, v) in kinds { body[k] = v }
            var pv: [String: Any] = [:]
            for (k, v) in params { pv[k] = Int(v) }
            body["params"] = pv
            Task {
                if let r = try? await API.post("api/rules", body: ["rules": [key: body]]) { saved(r["rules"].array) }
            }
        }
    }
}

/// Google Drive backup: status, back up now, connect (a code to enter at google.com/device), restore.
private struct BackupView: View {
    @State private var b: JSON = .null
    @State private var msg = ""
    @State private var code: JSON = .null

    var body: some View {
        Form {
            if !b.isNull {
                Section {
                    LabeledContent("Status", value: b["connected"].bool ? "Connected" + (b["email"].string.map { " (\($0))" } ?? "") : b["configured"].bool ? "Not connected" : "Not set up")
                    LabeledContent("Last backup", value: b["last_backup"].date.map { Fmt.ago($0) } ?? "never")
                    LabeledContent("Folder", value: b["folder"].string ?? "")
                    if let e = b["last_error"].string { Text(e).foregroundStyle(Th.red) }
                    if let u = b["folder_url"].string.flatMap(URL.init(string:)) { Link("Open the folder in Drive", destination: u) }
                }
                Section {
                    if b["connected"].bool {
                        Button("Back up now") { act("api/backup/now", "Backing up…", "Backed up.") }
                        Button("Restore from Drive") { act("api/backup/restore", "Restoring…", "Restored.") }
                        Button("Disconnect", role: .destructive) { act("api/backup/disconnect", "Disconnecting…", "Disconnected.") }
                    } else if b["configured"].bool {
                        Button("Connect Google Drive") {
                            msg = "Asking Google…"
                            Task {
                                if let r = try? await API.post("api/backup/connect") { code = r; msg = "" } else { msg = "Couldn't start the connection." }
                            }
                        }
                    } else {
                        Text("Add a Google client ID and secret in the add-on's Configuration tab first.").font(.footnote).foregroundStyle(Th.muted)
                    }
                    if let c = code["user_code"].string {
                        Text("Enter this code at \(code["verification_url"].string ?? "google.com/device"):").font(.footnote)
                        Text(c).font(.system(size: 28, weight: .bold, design: .monospaced)).textSelection(.enabled)
                        if let u = (code["verification_url"].string).flatMap(URL.init(string:)) { Link("Open the Google page", destination: u) }
                    }
                    if !msg.isEmpty { Text(msg).font(.footnote).foregroundStyle(Th.muted) }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Backup")
        .task { await load() }
    }

    private func load() async { if let r = try? await API.get("api/backup", keep: false) { b = r.0 } }

    private func act(_ path: String, _ doing: String, _ done: String) {
        msg = doing
        Task {
            do { _ = try await API.post(path); msg = done } catch { msg = error.localizedDescription }
            await load()
        }
    }
}

/// The add-on's health: schedule, sources, worker (api/debug).
private struct SetupCheckView: View {
    @State private var d: JSON = .null

    var body: some View {
        Form {
            if !d.isNull {
                let sch = d["schedule"]
                Section("Schedule") {
                    LabeledContent("File", value: sch["path"].string ?? "?")
                    LabeledContent("Read", value: sch["checked"].date.map { Fmt.ago($0) } ?? "not yet")
                    if let n = sch["count"].int { LabeledContent("Flights", value: "\(n)") }
                    if let e = sch["error"].string { Text(e).foregroundStyle(Th.red) }
                }
                Section("Sources") {
                    LabeledContent("Airline", value: d["config"]["airline_icao"].string ?? "?")
                    LabeledContent("AeroAPI", value: d["aeroapi"]["enabled"].bool ? String(format: "$%.3f of $%.2f this month", d["aeroapi"]["spent"].double ?? 0, d["aeroapi"]["budget"].double ?? 0) : "off (no key)")
                    LabeledContent("FAA registry", value: d["faa"]["rows"].int.map { "\($0.formatted()) aircraft" } ?? "not loaded")
                    LabeledContent("Alerts go to", value: d["config"]["notify"].string ?? "?")
                }
                Section("Worker") {
                    LabeledContent("Now", value: d["worker"]["busy"].bool ? "checking a flight" : "idle")
                    if let e = d["worker"]["error"].string { Text(e).foregroundStyle(Th.red) }
                    LabeledContent("Version", value: d["version"].string ?? "?")
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Setup check")
        .task { if let r = try? await API.get("api/debug", keep: false) { d = r.0 } }
    }
}
