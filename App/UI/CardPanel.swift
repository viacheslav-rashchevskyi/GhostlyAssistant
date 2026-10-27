import AppKit

/// Floating card that stays above other windows and is excluded from screen capture where macOS allows it.
final class CardPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: Self.defaultFrame(),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        sharingType = .none
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        self.contentView = contentView
        setFrameAutosaveName("AssistantCard")
    }

    override var canBecomeKey: Bool { true }

    private static func defaultFrame() -> NSRect {
        let size = NSSize(width: 360, height: 220)
        guard let visible = NSScreen.main?.visibleFrame else { return NSRect(origin: .zero, size: size) }
        return NSRect(
            x: visible.maxX - size.width - 16,
            y: visible.maxY - size.height - 16,
            width: size.width,
            height: size.height
        )
    }
}
