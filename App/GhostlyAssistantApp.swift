import AppKit
import SwiftUI

@main
struct GhostlyAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("GhostlyAssistant", image: "MenuBarIcon") {
            MenuContent(model: appDelegate.model, updater: appDelegate.updater, appDelegate: appDelegate)
        }
    }
}

/// Menu bar items; the first one names what it will do to the chat window right now.
private struct MenuContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdater
    let appDelegate: AppDelegate

    var body: some View {
        Button(model.isCardVisible ? L("Скрыть окно") : L("Показать окно")) { appDelegate.toggleCard() }
            .keyboardShortcut("h", modifiers: [.option, .command]) // also registered globally by HotKey
        Button(model.listeningPaused ? L("Возобновить прослушивание") : L("Приостановить прослушивание")) { model.toggleListening() }
            .disabled(model.status != .ready)
        Button(L("Настройки…")) { appDelegate.openSettings() }
            .keyboardShortcut(",", modifiers: .command)
        Button(L("Мастер настройки…")) { appDelegate.openOnboarding(again: true) }
        Button(L("Проверить обновления…")) { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
        Divider()
        Button(L("Выйти")) { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let updater = AppUpdater()
    private var panel: CardPanel?
    private var settings: SettingsWindowController?
    private let onboarding = Onboarding()
    private var guide: OnboardingWindowController?
    private var hotKeys: [HotKey] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let path = DebugCommandLine.transcribePath {
            Task { await DebugCommandLine.runTranscribe(path) }
            return
        }
        if let text = DebugCommandLine.askText {
            Task { await DebugCommandLine.runAsk(text) }
            return
        }
        NSApp.appearance = model.theme.appearance
        settings = SettingsWindowController(model: model, updater: updater)
        let card = ChatView(model: model) { [weak self] in self?.openSettings() }
        let host = NSHostingView(rootView: card)
        host.sizingOptions = [.minSize] // the user sizes the card; content fills it
        let panel = CardPanel(contentView: host)
        panel.ensureOnScreen()
        self.panel = panel
        hotKeys = [
            HotKey.toggleCard { [weak self] in self?.toggleCard() },
            HotKey.answerLast { [weak self] in self?.model.answerLastSkipped() }
        ]
        let onboarding = onboarding
        model.holdsPermissionPrompt = { onboarding.holdsPermissionPrompt }
        guide = OnboardingWindowController(model: model, onboarding: onboarding) { [weak self] in self?.showCard() }
        // Development aid: GHOSTLY_ONBOARDING=<step 0…5> opens the guide on that step (pair with GHOSTLY_CAPTURABLE=1).
        if let raw = ProcessInfo.processInfo.environment["GHOSTLY_ONBOARDING"], let step = Int(raw).flatMap(OnboardingStep.init(rawValue:)) {
            onboarding.restart()
            onboarding.step = step
            guide?.show()
        } else if onboarding.shouldShowAtLaunch(hasKey: model.hasAPIKey) {
            guide?.show()
        }
        if guide?.isOpen == true {
            model.isCardVisible = false
        } else {
            panel.orderFrontRegardless()
        }
        Task { await model.start() }
        updater.start()
        // Development aid: GHOSTLY_OPEN_SETTINGS=1 opens settings at launch (pair with GHOSTLY_CAPTURABLE=1 to screenshot).
        if ProcessInfo.processInfo.environment["GHOSTLY_OPEN_SETTINGS"] == "1" { openSettings() }
        if ProcessInfo.processInfo.environment["GHOSTLY_FOCUS_CHAT"] == "1" {
            NSApp.activate()
            panel.makeKey()
        }
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

    func openOnboarding(again: Bool) {
        if again { onboarding.restart() }
        if panel?.isVisible == true { toggleCard() } // the chat comes back when the guide closes
        guide?.show()
    }

    func showCard() {
        guard let panel, !panel.isVisible else { return }
        toggleCard()
    }
}
