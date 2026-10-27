import AppKit
import SwiftUI

/// Light, dark or whatever macOS is set to; chosen in settings and applied to the whole app.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L("Как в системе")
        case .light: L("Светлая")
        case .dark: L("Тёмная")
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Flat, minimal palette. Every color resolves per appearance, so one set of names serves both themes.
/// The accent, "moonlight ice", is used flat: on actions, the live status and the selected item only.
enum Theme {
    static let accent = adaptive(light: 0x2F5FD0, dark: 0xA8C7FF)
    /// Text and icons placed on an accent fill.
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x0D1E3A)
    /// A quiet wash of the accent for selected rows and the active pipeline step.
    static let accentSoft = accent.opacity(0.16)
    /// The window surface.
    static let windowNS = adaptiveNS(light: 0xF6F7F9, dark: 0x16181F)
    static let window = Color(nsColor: windowNS)
    /// One tone step above the window, for bubbles, cards and tiles.
    static let raised = Color.primary.opacity(0.06)
    /// The one-pixel edge around the floating card, so it holds its shape on a background of the same tone.
    static let hairline = Color.primary.opacity(0.12)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: adaptiveNS(light: light, dark: dark))
    }

    private static func adaptiveNS(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255,
                           green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        }
    }
}

/// A secondary action: a raised tile, no border, no material.
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.08)))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// The primary action: a flat accent fill.
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

extension ButtonStyle where Self == AccentButtonStyle {
    static var accent: AccentButtonStyle { AccentButtonStyle() }
}
