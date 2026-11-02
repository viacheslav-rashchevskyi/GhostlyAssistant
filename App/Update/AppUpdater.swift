import AppKit
import Combine
import Sparkle

/// Sparkle drives checking, downloading, verifying and installing; `UpdateUserDriver` draws every step in our own window.
/// The feed and the public signing key live in Info.plist (`SUFeedURL`, `SUPublicEDKey`).
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecks: Bool {
        didSet { updater?.automaticallyChecksForUpdates = automaticallyChecks }
    }

    private let driver = UpdateUserDriver()
    private var updater: SPUUpdater?
    private var observation: AnyCancellable?

    override init() {
        automaticallyChecks = UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? true
        super.init()
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// Starts Sparkle's daily schedule and also checks once in the background now, so a new release shows up at launch.
    func start() {
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        do {
            try updater.start()
        } catch {
            NSLog("GhostlyAssistant: updater failed to start: \(error)")
            return
        }
        self.updater = updater
        automaticallyChecks = updater.automaticallyChecksForUpdates
        observation = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
        if automaticallyChecks {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak updater] in
                guard let updater, updater.canCheckForUpdates else { return }
                updater.checkForUpdatesInBackground()
            }
        }
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    // MARK: SPUUpdaterDelegate

    /// Development aid: GHOSTLY_UPDATE_FEED=<url> points the updater at a test appcast.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment["GHOSTLY_UPDATE_FEED"]
    }
}
