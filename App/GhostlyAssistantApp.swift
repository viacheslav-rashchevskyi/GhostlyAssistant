import AppKit
import SwiftUI

@main
struct GhostlyAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("GhostlyAssistant", image: "MenuBarIcon") {
            MenuContent(model: appDelegate.model, appDelegate: appDelegate)
        }
    }
}

/// Menu bar items; the first one names what it will do to the chat window right now.
private struct MenuContent: View {
    @ObservedObject var model: AppModel
    let appDelegate: AppDelegate

    var body: some View {
        Button(model.isCardVisible ? "Скрыть окно" : "Показать окно") { appDelegate.toggleCard() }
            .keyboardShortcut("h", modifiers: [.option, .command]) // also registered globally by HotKey
        Button("Настройки…") { appDelegate.openSettings() }
            .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("Выйти") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var panel: CardPanel?
    private var settings: SettingsWindowController?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let path = DebugCommandLine.transcribePath {
            Task { await DebugCommandLine.runTranscribe(path) }
            return
        }
        if let text = DebugCommandLine.askText {
            Task { await DebugCommandLine.runAsk(text) }
            return
        }
        settings = SettingsWindowController(model: model)
        let card = ChatView(model: model) { [weak self] in self?.openSettings() }
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
