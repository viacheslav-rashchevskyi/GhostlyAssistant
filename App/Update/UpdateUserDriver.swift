import AppKit
import Sparkle

/// What the update window shows. Sparkle hands over a callback at each step; the window answers through it.
enum UpdatePhase {
    case checking(cancel: () -> Void)
    case found(UpdateOffer, reply: (SPUUserUpdateChoice) -> Void)
    case downloading(received: UInt64, expected: UInt64, cancel: () -> Void)
    case extracting(progress: Double?)
    case readyToInstall(reply: (SPUUserUpdateChoice) -> Void)
    case installing
    case message(title: String, detail: String, acknowledge: () -> Void)
}

struct UpdateOffer {
    let version: String
    let size: UInt64
    /// An "information only" release can't be installed from the app; the window links to `infoURL` instead.
    let informationOnly: Bool
    let infoURL: URL?
}

/// Release notes from the appcast: Markdown (what `scripts/publish-update.sh` embeds) or HTML.
enum ReleaseNotes {
    case none, loading, markdown(String), html(String)

    init(text: String?, format: String?) {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { self = .none; return }
        self = format == "html" ? .html(text) : .markdown(text)
    }
}

@MainActor
final class UpdateSession: ObservableObject {
    @Published var phase: UpdatePhase?
    @Published var notes: ReleaseNotes = .none
    /// Closes the window after the user answered, without counting it as a close-button answer.
    var finish: () -> Void = {}

    func answer(_ reply: (SPUUserUpdateChoice) -> Void, _ choice: SPUUserUpdateChoice) {
        if choice != .install { finish() }
        reply(choice)
    }
}

/// Sparkle's user interface, replaced with our own window: localized through `Loc`, themed, hidden from screen capture.
@MainActor
final class UpdateUserDriver: NSObject, SPUUserDriver {
    private let session = UpdateSession()
    private lazy var window = UpdateWindowController(session: session) { [weak self] in self?.windowClosedByUser() }

    override init() {
        super.init()
        session.finish = { [weak self] in self?.dismissUpdateInstallation() }
    }

    private func show(_ phase: UpdatePhase, activate: Bool = false) {
        session.phase = phase
        window.show(activate: activate)
    }

    /// The close button answers like the gentlest choice of the step on screen.
    private func windowClosedByUser() {
        guard let phase = session.phase else { return }
        session.phase = nil
        switch phase {
        case .checking(let cancel), .downloading(_, _, let cancel): cancel()
        case .found(_, let reply), .readyToInstall(let reply): reply(.dismiss)
        case .message(_, _, let acknowledge): acknowledge()
        case .extracting, .installing: break
        }
    }

    // MARK: SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Info.plist sets SUEnableAutomaticChecks, so Sparkle has no reason to ask; answer the same way if it does.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        show(.checking(cancel: cancellation), activate: true)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let offer = UpdateOffer(version: appcastItem.displayVersionString,
                                size: appcastItem.contentLength,
                                informationOnly: appcastItem.isInformationOnlyUpdate,
                                infoURL: appcastItem.infoURL)
        session.notes = appcastItem.releaseNotesURL != nil && appcastItem.itemDescription == nil
            ? .loading
            : ReleaseNotes(text: appcastItem.itemDescription, format: appcastItem.itemDescriptionFormat)
        // A scheduled check doesn't take focus from the call; the window just appears on top.
        show(.found(offer, reply: reply), activate: state.userInitiated)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        let text = String(data: downloadData.data, encoding: .utf8)
        let isHTML = downloadData.mimeType?.contains("html") ?? false
        session.notes = ReleaseNotes(text: text, format: isHTML ? "html" : "markdown")
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        session.notes = .none
    }

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        let latest = (error as NSError).userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem
        let detail = if let latest, !latest.minimumOperatingSystemVersionIsOK {
            L("Версии %@ нужна более новая macOS.", latest.displayVersionString)
        } else {
            L("У вас последняя версия — %@.", AppUpdater.currentVersion)
        }
        show(.message(title: L("Обновлений нет"), detail: detail, acknowledge: acknowledgement), activate: true)
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        show(.message(title: L("Не удалось обновить"), detail: error.localizedDescription, acknowledge: acknowledgement), activate: true)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        show(.downloading(received: 0, expected: 0, cancel: cancellation))
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        guard case .downloading(let received, _, let cancel) = session.phase else { return }
        session.phase = .downloading(received: received, expected: expectedContentLength, cancel: cancel)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        guard case .downloading(let received, let expected, let cancel) = session.phase else { return }
        session.phase = .downloading(received: received + length, expected: expected, cancel: cancel)
    }

    func showDownloadDidStartExtractingUpdate() {
        show(.extracting(progress: nil))
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        show(.extracting(progress: progress))
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        show(.readyToInstall(reply: reply))
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        show(.installing)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {
        window.show(activate: true)
    }

    func dismissUpdateInstallation() {
        session.phase = nil
        session.notes = .none
        window.close()
    }
}
