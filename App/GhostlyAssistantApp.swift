import AppKit
import SwiftUI

@main
struct GhostlyAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("GhostlyAssistant", systemImage: "waveform") {
            Button("Показать / скрыть карточку") { appDelegate.toggleCard() }
            Button("Настройки…") { appDelegate.openSettings() }
            Divider()
            Button("Выйти") { NSApp.terminate(nil) }
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
        let host = NSHostingView(rootView: card)
        host.sizingOptions = [.minSize] // the user sizes the card; content fills it
        let panel = CardPanel(contentView: host)
        panel.ensureOnScreen()
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
            panel.ensureOnScreen()
            panel.orderFrontRegardless()
        }
        model.isCardVisible = panel.isVisible
    }

    func openSettings() {
        settings?.show()
    }
}
