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

    /// "1h 9m"
    static func span(_ seconds: Double) -> String {
        let m = Int((abs(seconds) / 60).rounded())
        if m < 60 { return "\(m)m" }
        return "\(m / 60)h \(m % 60)m"
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
