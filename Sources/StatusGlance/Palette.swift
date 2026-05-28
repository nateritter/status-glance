import SwiftUI
import AppKit

/// Dark-navy popover palette per SPEC.md. SwiftUI Color constants in one place.
enum Palette {
    /// Background dark navy (#0F1420-ish).
    static let background = Color(hex: 0x0F1420)
    /// Slightly raised surface for cards/rows.
    static let surface = Color(hex: 0x161C2C)
    /// Hairline separators.
    static let separator = Color(hex: 0x232B3D)

    /// Section headers — muted blue.
    static let sectionHeader = Color(hex: 0x7AA2F7)
    /// Accent / link blue.
    static let accent = Color(hex: 0x5B8DEF)

    /// Primary near-white text.
    static let textPrimary = Color(hex: 0xE6EDF3)
    /// Secondary muted text.
    static let textSecondary = Color(hex: 0x8B949E)

    // Convenience pass-throughs to the single status-color source of truth.
    static func color(for indicator: Indicator) -> Color { StatusColor.color(for: indicator) }
    static func color(for status: ComponentStatus) -> Color { StatusColor.color(for: status) }
}

extension Color {
    /// Build a Color from a 24-bit RGB hex literal in sRGB.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
