import SwiftUI

/// The web app's colors (style.css :root), so both look the same.
enum Th {
    static let bg = Color.black
    static let sheet = Color(hex: 0x151517)
    static let card = Color(hex: 0x1F1F22)
    static let card2 = Color(hex: 0x2C2C2E)
    static let line = Color(hex: 0x2F2F33)
    static let muted = Color(hex: 0x8E8E93)
    static let faint = Color(hex: 0x5E5E63)
    static let accent = Color(hex: 0x0A84FF)
    static let green = Color(hex: 0x30D158)
    static let amber = Color(hex: 0xFFB340)
    static let red = Color(hex: 0xFF453A)
    static let orange = Color(hex: 0xFF8A3D)
    static let violet = Color(hex: 0xA78BFA)
    static let route = Color(hex: 0x4F8DFF)
    static let yellow = Color(hex: 0xF6C343)
    static let navy = Color(hex: 0x0B2E7A)
    static let radius: CGFloat = 18

    /// How late, as a color, everywhere (banner, times, rows, Passport): green early or on time (under 5
    /// min late), yellow delayed (5-29), orange very delayed (30+). Red is only for cancelled or diverted.
    /// nil when nothing's known yet.
    static func tone(_ m: Int?, known: Bool = true) -> Color? {
        guard known, let m else { return nil }
        return m >= 30 ? orange : m >= 5 ? amber : green
    }
    /// Times only turn red or amber (on time stays white).
    static func lateTone(_ m: Int?, known: Bool = true) -> Color? {
        guard let t = tone(m, known: known), t != green else { return nil }
        return t
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

extension View {
    /// The web app's card: dark rounded box.
    func card(_ pad: CGFloat = 14) -> some View {
        self.padding(pad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Th.card, in: RoundedRectangle(cornerRadius: Th.radius, style: .continuous))
    }
}

/// "UA" in the airline's badge.
struct AirlineBadge: View {
    let code: String
    var size: CGFloat = 18
    var body: some View {
        Text(code.isEmpty ? "✈︎" : code)
            .font(.system(size: size * 0.48, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Th.navy, in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

/// A small capsule tag: DH, FRIEND...
struct Tag: View {
    let text: String
    var color: Color = Th.violet
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .heavy)).tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
    }
}

/// The round arrow before a time: up-right for departure, down-right for arrival.
struct DepArrIcon: View {
    let departure: Bool
    var tone: Color? = nil
    var size: CGFloat = 18
    var body: some View {
        Image(systemName: departure ? "arrow.up.right" : "arrow.down.right")
            .font(.system(size: size * 0.5, weight: .heavy))
            .foregroundStyle(tone == nil ? Th.bg : .white)
            .frame(width: size, height: size)
            .background(tone ?? Th.muted, in: Circle())
    }
}
