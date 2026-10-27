import AppKit
import AssistantCore
import ScreenCaptureKit

/// Screenshot of the main display without this app's windows, downscaled and JPEG-encoded.
struct ScreenshotService: ScreenshotProviding {
    static let maxLongSide = 1500.0
    static let jpegQuality = 0.7

    func captureJPEG() async throws -> Data {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }
        let me = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        let scale = min(1, Self.maxLongSide / Double(max(display.width, display.height)))
        let config = SCStreamConfiguration()
        config.width = Int(Double(display.width) * scale)
        config.height = Int(Double(display.height) * scale)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: Self.jpegQuality]) else {
            throw CaptureError.noDisplay
        }
        return data
    }
}
