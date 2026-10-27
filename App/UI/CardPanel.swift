import AppKit

/// Floating, resizable card that stays above other windows and is excluded from screen capture where macOS allows it.
/// Borderless, so the only visible edge is the rounded glass drawn by the SwiftUI content; edges still resize it.
final class CardPanel: NSPanel {
    static let cornerRadius: CGFloat = 22

    /// Wraps `contentView` in rounded system glass; the rounding clips the backdrop blur too.
    init(contentView: NSView) {
        let glass = NSGlassEffectView()
        glass.cornerRadius = Self.cornerRadius
        glass.tintColor = NSColor.black.withAlphaComponent(0.65)
        glass.contentView = contentView
        super.init(
            contentRect: Self.defaultFrame(),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        excludeFromCapture()
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false // the window shadow is rectangular; the glass has its own rounded edge
        hidesOnDeactivate = false
        minSize = NSSize(width: 300, height: 220)
        self.contentView = glass
        setFrameAutosaveName("AssistantChat")
    }

    override var canBecomeKey: Bool { true }

    /// No clamping to the visible area: the card may sit over the menu bar, the Dock or straddle displays.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Brings the card back to the default corner if it was dragged entirely off every display.
    func ensureOnScreen() {
        let visible = NSScreen.screens.contains { $0.frame.intersection(frame).width >= 40 && $0.frame.intersection(frame).height >= 40 }
        if !visible { setFrame(Self.defaultFrame(), display: true) }
    }

    private static func defaultFrame() -> NSRect {
        let size = NSSize(width: 340, height: 600)
        guard let visible = NSScreen.main?.visibleFrame else { return NSRect(origin: .zero, size: size) }
        return NSRect(
            x: visible.maxX - size.width - 16,
            y: visible.maxY - size.height - 16,
            width: size.width,
            height: size.height
        )
    }
}
