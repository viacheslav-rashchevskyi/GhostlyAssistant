import AppKit
import CoreGraphics

enum ScreenPermission {
    static var granted: Bool { CGPreflightScreenCaptureAccess() }

    static func request() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
