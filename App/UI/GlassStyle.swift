import AppKit

/// One glass look for every window of the app.
enum GlassStyle {
    static let tint = NSColor.black.withAlphaComponent(0.65)

    /// System glass with the shared tint around `content`.
    static func make(_ content: NSView, cornerRadius: CGFloat) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.tintColor = tint
        glass.contentView = content
        return glass
    }
}
