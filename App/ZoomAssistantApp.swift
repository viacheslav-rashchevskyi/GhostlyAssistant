import AppKit
import SwiftUI

@main
struct ZoomAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Асистент", systemImage: "waveform") {
            Button("Показати / сховати картку") { appDelegate.toggleCard() }
            Divider()
            Button("Вийти") { NSApp.terminate(nil) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: CardPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let path = DebugCommandLine.transcribePath {
            Task { await DebugCommandLine.runTranscribe(path) }
            return
        }
        let host = NSHostingView(rootView: Text("Очікую звук").padding())
        let panel = CardPanel(contentView: host)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func toggleCard() {
        guard let panel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
}
