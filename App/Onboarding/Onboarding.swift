import AppKit
import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome, key, permission, languages, speech, usage

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: L("Добро пожаловать")
        case .key: L("Ключ API")
        case .permission: L("Разрешение")
        case .languages: L("Языки")
        case .speech: L("Модель речи")
        case .usage: L("Как пользоваться")
        }
    }
}

/// Progress through first-run setup. It survives a relaunch, because the screen recording permission
/// only takes effect after one.
@MainActor
final class Onboarding: ObservableObject {
    private enum Key {
        static let step = "onboardingStep"
        static let furthest = "onboardingFurthest"
        static let done = "onboardingDone"
        static let keySkipped = "onboardingKeySkipped"
    }

    @Published var step: OnboardingStep {
        didSet {
            UserDefaults.standard.set(step.rawValue, forKey: Key.step)
            if step.rawValue > furthest.rawValue { furthest = step }
        }
    }
    @Published private(set) var furthest: OnboardingStep {
        didSet { UserDefaults.standard.set(furthest.rawValue, forKey: Key.furthest) }
    }
    @Published var keySkipped: Bool {
        didSet { UserDefaults.standard.set(keySkipped, forKey: Key.keySkipped) }
    }

    init() {
        let d = UserDefaults.standard
        step = OnboardingStep(rawValue: d.integer(forKey: Key.step)) ?? .welcome
        furthest = OnboardingStep(rawValue: d.integer(forKey: Key.furthest)) ?? .welcome
        keySkipped = d.bool(forKey: Key.keySkipped)
    }

    var isDone: Bool { UserDefaults.standard.bool(forKey: Key.done) }

    /// Only a first launch opens the guide by itself; someone who already saved a key has set the app up before it existed.
    func shouldShowAtLaunch(hasKey: Bool) -> Bool {
        guard !isDone else { return false }
        let started = UserDefaults.standard.object(forKey: Key.step) != nil
        if !started && hasKey {
            UserDefaults.standard.set(true, forKey: Key.done)
            return false
        }
        return true
    }

    /// Steps before the permission prompt shouldn't trigger it; the permission step asks itself.
    var holdsPermissionPrompt: Bool { !isDone && step.rawValue < OnboardingStep.permission.rawValue }

    func next() {
        if let after = OnboardingStep(rawValue: step.rawValue + 1) { step = after }
    }

    func back() {
        if let before = OnboardingStep(rawValue: step.rawValue - 1) { step = before }
    }

    func canOpen(_ s: OnboardingStep) -> Bool { s.rawValue <= furthest.rawValue }

    func finish() {
        UserDefaults.standard.set(true, forKey: Key.done)
    }

    /// From the menu: run the guide again with every step reachable.
    func restart() {
        furthest = .usage
        step = .welcome
    }

    /// Opens a fresh copy of the app and quits this one.
    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }
}
