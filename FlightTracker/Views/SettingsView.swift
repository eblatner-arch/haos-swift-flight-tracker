import SwiftUI

/// Settings: this app (address, time format), and the add-on's own settings and alert rules (the same
/// ones as the web app's Settings page, saved in the add-on).
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let addFlight: () -> Void
    @AppStorage(API.serverKey) private var server = ""
    @AppStorage("h24") private var h24 = false
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
                    NavigationLink { SetupCheckView() } label: { Label("Setup check", systemImage: "stethoscope") }
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
                Section("Display") {
                    Toggle("24-hour time", isOn: $h24)
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
                Stepper(value: Binding(get: { values[key] ?? lo }, set: { values[key] = $0; Task { await save() } }), in: lo...hi) {
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

/// Which alerts the add-on sends (api/rules): on or off, by group.
private struct RulesView: View {
    @State private var rules: [JSON] = []
    @State private var on: [String: Bool] = [:]

    var body: some View {
        Form {
            ForEach(groups, id: \.self) { g in
                Section(g) {
                    ForEach(Array(rules.filter { ($0["group"].string ?? "") == g }.enumerated()), id: \.offset) { _, r in
                        let key = r["key"].string ?? ""
                        VStack(alignment: .leading, spacing: 3) {
                            Toggle(r["label"].string ?? key, isOn: Binding(get: { on[key] ?? false }, set: { v in on[key] = v; Task { _ = try? await API.post("api/rules", body: ["rules": [key: ["on": v]]]) } }))
                            if let d = r["desc"].string { Text(d).font(.caption).foregroundStyle(Th.muted) }
                        }
                    }
                }
            }
            Section { Text("Timing, time-sensitive delivery and which kinds of flights each alert covers are in the web app's Settings.").font(.footnote).foregroundStyle(Th.muted) }
        }
        .navigationTitle("Alerts")
        .task {
            guard let r = try? await API.get("api/rules", keep: false) else { return }
            rules = r.0["rules"].array
            for x in rules { if let k = x["key"].string { on[k] = x["rule"]["on"].bool } }
        }
    }

    private var groups: [String] {
        var out: [String] = []
        for r in rules { let g = r["group"].string ?? ""; if !out.contains(g) { out.append(g) } }
        return out
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
