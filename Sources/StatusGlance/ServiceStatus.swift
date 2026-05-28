import AppKit
import SwiftUI

/// Overall status page indicator. Lenient: unknown raw strings decode to `.unknown`.
enum Indicator: String, Codable, Sendable {
    case none
    case minor
    case major
    case critical
    case maintenance
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Indicator(rawValue: raw) ?? .unknown
    }

    /// Human-readable fallback label (the API usually supplies its own description).
    var fallbackDescription: String {
        switch self {
        case .none: return "All Systems Operational"
        case .minor: return "Minor Service Issue"
        case .major: return "Major Outage"
        case .critical: return "Critical Outage"
        case .maintenance: return "Under Maintenance"
        case .unknown: return "Status Unknown"
        }
    }
}

/// Per-component status. Lenient: unknown raw strings decode to `.unknown`.
enum ComponentStatus: String, Codable, Sendable {
    case operational
    case degradedPerformance = "degraded_performance"
    case partialOutage = "partial_outage"
    case majorOutage = "major_outage"
    case underMaintenance = "under_maintenance"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // NOTE: `convertFromSnakeCase` only affects KEYS, not VALUES, so raw values
        // arrive in snake_case form here and we match the explicit rawValues above.
        self = ComponentStatus(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .operational: return "Operational"
        case .degradedPerformance: return "Degraded Performance"
        case .partialOutage: return "Partial Outage"
        case .majorOutage: return "Major Outage"
        case .underMaintenance: return "Under Maintenance"
        case .unknown: return "Unknown"
        }
    }
}

/// The single source of truth for status → color. Used by both the menu-bar glyph
/// tint and the popover dots. Hex values per SPEC.md.
enum StatusColor {
    static let green = StatusHex(0x3FB950)
    static let yellow = StatusHex(0xF0B429)
    static let orange = StatusHex(0xF0883E)
    static let red = StatusHex(0xE5484D)
    static let blue = StatusHex(0x3B82F6)
    static let gray = StatusHex(0x8B949E)

    static func hex(for indicator: Indicator) -> StatusHex {
        switch indicator {
        case .none: return green
        case .minor: return yellow
        case .major: return orange
        case .critical: return red
        case .maintenance: return blue
        case .unknown: return gray
        }
    }

    static func hex(for status: ComponentStatus) -> StatusHex {
        switch status {
        case .operational: return green
        case .degradedPerformance: return yellow
        case .partialOutage: return orange
        case .majorOutage: return red
        case .underMaintenance: return blue
        case .unknown: return gray
        }
    }

    static func nsColor(for indicator: Indicator) -> NSColor { hex(for: indicator).nsColor }
    static func nsColor(for status: ComponentStatus) -> NSColor { hex(for: status).nsColor }
    static func color(for indicator: Indicator) -> Color { hex(for: indicator).color }
    static func color(for status: ComponentStatus) -> Color { hex(for: status).color }
}

/// A 24-bit RGB hex value that vends both NSColor and SwiftUI Color.
struct StatusHex: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init(_ hex: UInt32) {
        self.red = Double((hex >> 16) & 0xFF) / 255.0
        self.green = Double((hex >> 8) & 0xFF) / 255.0
        self.blue = Double(hex & 0xFF) / 255.0
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1.0)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }
}
