import SwiftUI

/// One lookup of a flight and what it changed (the web app's Lookup Log).
struct LogEntry: Identifiable {
    let id: Int
    let at: Date?
    let last: Date?
    let quiet: Int
    let sources: [String]
    let seen: [(src: String, tail: String?, note: String?)]
    let changes: [(field: String, from: String?, to: String, via: String?)]
    let error: String?
    let note: String?

    init(_ i: Int, _ h: JSON) {
        id = i
        at = h["at"].date
        last = h["last"].date
        quiet = h["quiet"].int ?? 0
        sources = h["sources"].array.compactMap { $0.string }
        seen = h["seen"].array.map { (src: $0["src"].string ?? "", tail: $0["tail"].string, note: $0["note"].string) }
        changes = h["changes"].array.map { (field: $0["field"].string ?? "", from: $0["from"].string, to: $0["to"].string ?? "", via: $0["via"].string) }
        error = h["error"].string
        note = h["note"].string
    }

    init(_ i: Int, at: Date?, sources: [String], seen: [(src: String, tail: String?, note: String?)], changes: [(field: String, from: String?, to: String, via: String?)]) {
        id = i; self.at = at; last = nil; quiet = 0; self.sources = sources; self.seen = seen; self.changes = changes; error = nil; note = nil
    }

    /// your flight's log
    static func of(_ leg: Leg) -> [LogEntry] {
        leg.j["history"].array.enumerated().map { LogEntry($0.offset, $0.element) }
    }

    /// an earlier leg of your airplane: what the FAA and towers said about it, and for your inbound,
    /// its lookups from your flight's log (its FlightAware page, its transponder) and what they changed
    static func inbound(raw: JSON, n: Int, parent: Leg?) -> [LogEntry] {
        var out: [LogEntry] = raw["log"].array.enumerated().map { i, x in
            let src = x["src"].string ?? "FAA SWIM"
            return LogEntry(i, at: x["at"].date, sources: [src], seen: [(src: src, tail: nil, note: x["text"].string)], changes: [])
        }
        guard n == 0, let parent else { return out }
        var k = out.count
        for h in parent.j["history"].array {
            let srcs = h["sources"].array.compactMap { $0.string }
            let seen = h["seen"].array.filter { ($0["src"].string ?? "").contains(" · inbound ") }
            let ch = h["changes"].array.filter { c in let f = c["field"].string ?? ""; return f.hasPrefix("Inbound") || f == "Tail" }
            let inb = { (s: String) in s.contains("(inbound)") }
            if seen.isEmpty && ch.isEmpty && !srcs.contains(where: inb) { continue }
            let keep = srcs.filter { inb($0) || (!seen.isEmpty && $0.range(of: "adsb|ADS-B|radar|Transponder", options: [.regularExpression, .caseInsensitive]) != nil) }
            out.append(LogEntry(k, at: h["at"].date, sources: keep,
                                seen: seen.map { (src: $0["src"].string ?? "", tail: $0["tail"].string, note: $0["note"].string) },
                                changes: ch.map { (field: $0["field"].string ?? "", from: $0["from"].string, to: $0["to"].string ?? "", via: $0["via"].string) }))
            k += 1
        }
        return out.sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }
    }
}

struct LookupLog: View {
    let entries: [LogEntry]
    var more: Int = 0
    var loadMore: (() async -> Void)?
    @State private var loading = false

    private static let stamp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d HH:mm"; return f }()
    private static let hm: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    var body: some View {
        Fold(title: "Lookup Log") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { h in row(h) }
                if more > 0, let loadMore {
                    Button {
                        loading = true
                        Task { await loadMore(); loading = false }
                    } label: {
                        Text(loading ? "Loading…" : "Show \(more) older").font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Th.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain).padding(.top, 10).disabled(loading)
                }
            }
            .card()
        }
    }

    private func row(_ h: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            FlowLayout(spacing: 6) {
                Text((h.at.map { Self.stamp.string(from: $0) } ?? "") + (h.quiet > 0 ? h.last.map { "–" + Self.hm.string(from: $0) } ?? "" : ""))
                    .font(.system(size: 13, design: .monospaced)).foregroundStyle(Th.muted).padding(.vertical, 2)
                ForEach(Array(h.sources.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.system(size: 12, weight: .semibold)).foregroundStyle(srcColor(s))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(srcColor(s).opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            ForEach(Array(h.seen.enumerated()), id: \.offset) { _, x in
                (Text(x.src + " ").foregroundStyle(Th.faint)
                 + (x.tail.map { Text($0).bold() + Text(x.note.map { " · " + $0 } ?? "").foregroundStyle(Th.faint) } ?? Text(x.note ?? "no tail").foregroundStyle(Th.faint)))
                    .font(.system(size: 13))
            }
            if h.changes.isEmpty {
                Text("No changes" + (h.quiet > 0 ? " · \(h.quiet) checks" : "")).font(.system(size: 13)).foregroundStyle(Th.faint)
            } else {
                ForEach(Array(h.changes.enumerated()), id: \.offset) { _, c in
                    (Text(c.field + " ").foregroundStyle(Th.faint)
                     + (c.from.map { Text($0).strikethrough().foregroundStyle(Th.muted) + Text(" → ") } ?? Text(""))
                     + Text(c.to).bold()
                     + Text(c.via.map { "  via " + $0 } ?? "").foregroundStyle(Th.faint))
                        .font(.system(size: 14))
                }
            }
            if let e = h.error { Text(e).font(.system(size: 13)).foregroundStyle(Th.red) }
            else if let n = h.note, h.changes.isEmpty { Text(n).font(.system(size: 13)).foregroundStyle(Th.faint) }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Th.line).frame(height: 0.5) }
    }

    private func srcColor(_ s: String) -> Color {
        if s.contains("AeroAPI") { return Th.amber }
        if s.contains("Gemini") { return Th.violet }
        if s.range(of: "ADS-B|adsb", options: .regularExpression) != nil { return Th.green }
        return Th.accent
    }
}
