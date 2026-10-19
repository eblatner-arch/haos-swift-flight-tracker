import SwiftUI

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(API.serverKey) private var server = ""
    @AppStorage("h24") private var h24 = false
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
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
                    Text("In the web app: Settings → Notifications → turn on **Open alerts in the iPhone app**. Tapping a Home Assistant alert then opens the flight here (Home Assistant shows for a moment first, iOS opens the app a notification belongs to).")
                        .font(.footnote)
                    LabeledContent("Link", value: "\(linkScheme)://leg/…")
                } header: {
                    Text("Notifications")
                }
                Section("Display") {
                    Toggle("24-hour time", isOn: $h24)
                }
                Section {
                    LabeledContent("App", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
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
