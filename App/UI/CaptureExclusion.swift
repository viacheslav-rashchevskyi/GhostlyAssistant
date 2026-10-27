import AppKit

extension NSWindow {
    /// Hides the window from screen capture. Launching with GHOSTLY_CAPTURABLE=1 keeps it capturable,
    /// so the UI can be screenshotted while developing.
    func excludeFromCapture() {
        sharingType = ProcessInfo.processInfo.environment["GHOSTLY_CAPTURABLE"] == "1" ? .readOnly : .none
    }
}
