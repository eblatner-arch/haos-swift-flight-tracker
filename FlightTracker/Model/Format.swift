import SwiftUI

enum Fmt {
    /// "2:51 PM" in the airport's own time zone.
    static func time(_ d: Date?, _ tz: TimeZone) -> String {
        guard let d else { return "--:--" }
        let f = DateFormatter()
        f.timeZone = tz
        f.dateFormat = UserDefaults.standard.bool(forKey: "h24") ? "HH:mm" : "h:mm a"
        return f.string(from: d)
    }

    /// "CDT"
    static func zone(_ d: Date?, _ tz: TimeZone) -> String {
        tz.abbreviation(for: d ?? Date()) ?? ""
    }

    /// "Mon, Oct 19"
    static func day(_ d: Date?, _ tz: TimeZone) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        f.timeZone = tz
        f.dateFormat = "EEE, MMM d"
        return f.string(from: d)
    }

    /// "1h 9m", "2d 3h"
    static func span(_ seconds: Double) -> String {
        var m = Int((abs(seconds) / 60).rounded())
        let d = m / 1440; m -= d * 1440
        let h = m / 60; m -= h * 60
        return d > 0 ? "\(d)d \(h)h" : h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// "On Time", "40m Late", "5m Early", or "Scheduled" when nothing is known yet
    static func lateWord(_ m: Int?, known: Bool = true) -> String {
        guard known, let m else { return "Scheduled" }
        if abs(m) < 5 { return "On Time" }
        return m > 0 ? "\(span(Double(m * 60))) Late" : "\(span(Double(-m * 60))) Early"
    }

    static func lateLower(_ m: Int?) -> String {
        guard let m, abs(m) >= 5 else { return "on time" }
        return m > 0 ? "\(span(Double(m * 60))) late" : "\(span(Double(-m * 60))) early"
    }

    /// "Thu, Oct 22" in a time zone
    static func dateShort(_ d: Date?, _ tz: TimeZone) -> String { day(d, tz) }

    /// "3 min ago", "2 h ago"
    static func ago(_ d: Date?) -> String {
        guard let d else { return "" }
        let s = -d.timeIntervalSinceNow
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60)) min ago" }
        if s < 86400 { return "\(Int(s / 3600)) h ago" }
        return "\(Int(s / 86400)) d ago"
    }

    /// "40m late" / "On time" / "5m early"
    static func late(_ minutes: Int?) -> String {
        guard let m = minutes else { return "" }
        if abs(m) < 5 { return "On time" }
        return m > 0 ? "\(span(Double(m * 60))) late" : "\(span(Double(-m * 60))) early"
    }

    static func lateColor(_ minutes: Int?) -> Color {
        guard let m = minutes else { return .secondary }
        if m >= 15 { return .red }
        if m >= 5 { return .orange }
        return .green
    }

    /// "in 1h 9m" / "1h 9m ago"
    static func relative(_ d: Date?) -> String {
        guard let d else { return "" }
        let s = d.timeIntervalSinceNow
        return s >= 0 ? "in \(span(s))" : "\(span(s)) ago"
    }
}

extension Color {
    static let route = Color(red: 0.25, green: 0.55, blue: 1.0)
    static let card = Color(white: 0.11)
}
