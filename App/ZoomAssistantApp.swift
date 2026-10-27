import AppKit
import SwiftUI

@main
struct ZoomAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Асистент", systemImage: "waveform") {
            Button("Показати / сховати картку") { appDelegate.toggleCard() }
            Button("Налаштування…") { appDelegate.openSettings() }
            Divider()
            Button("Вийти") { NSApp.terminate(nil) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var panel: CardPanel?
    private var settings: SettingsWindowController?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let path = DebugCommandLine.transcribePath {
            Task { await DebugCommandLine.runTranscribe(path) }
            return
        }
        settings = SettingsWindowController(model: model)
        let card = CardView(model: model) { [weak self] in self?.openSettings() }
        let panel = CardPanel(contentView: NSHostingView(rootView: card))
        panel.orderFrontRegardless()
        self.panel = panel
        hotKey = HotKey.toggleCard { [weak self] in self?.toggleCard() }
        Task { await model.start() }
    }

    func toggleCard() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
        model.isCardVisible = panel.isVisible
    }

    func openSettings() {
        settings?.show()
    }
}
