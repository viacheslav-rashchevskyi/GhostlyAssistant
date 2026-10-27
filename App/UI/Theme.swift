import SwiftUI

/// The app's one accent, "moonlight ice", used flat: on actions, the live status and the selected item only.
enum Theme {
    static let accent = Color(red: 0xA8 / 255, green: 0xC7 / 255, blue: 0xFF / 255)
    /// Text and icons placed on an accent fill.
    static let onAccent = Color(red: 0x0D / 255, green: 0x1E / 255, blue: 0x3A / 255)
    /// A quiet wash of the accent for selected rows and the active pipeline step.
    static let accentSoft = accent.opacity(0.16)
    /// One tone step above the glass, for bubbles and tiles.
    static let raised = Color.white.opacity(0.07)
}
