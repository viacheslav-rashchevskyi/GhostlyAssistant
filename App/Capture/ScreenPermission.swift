import AppKit
import CoreGraphics
import os
import ScreenCaptureKit

enum ScreenPermission {
    private static let log = Logger(subsystem: "local.ghostlyassistant.app", category: "permission")

    /// CGPreflightScreenCaptureAccess can report false on recent macOS even when access is granted,
    /// so a failed preflight is confirmed by actually asking ScreenCaptureKit for shareable content.
    static func check() async -> Bool {
        let preflight = CGPreflightScreenCaptureAccess()
        if preflight {
            log.info("preflight granted")
            return true
        }
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            log.info("preflight false, ScreenCaptureKit works")
            return true
        } catch {
            log.error("no screen capture access: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func request() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
