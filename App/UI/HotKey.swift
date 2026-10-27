import Carbon
import Foundation

/// A system-wide hotkey registered through Carbon (works without Accessibility permission).
/// Each instance has a unique id and only fires for its own key, so several can coexist.
@MainActor
final class HotKey {
    private static let signature = OSType(0x4748_5354) // "GHST"
    private static var nextID: UInt32 = 1
    private static var actions: [UInt32: @MainActor () -> Void] = [:]
    private static var handlerInstalled = false

    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        Self.actions[id] = action
        Self.installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0, &ref)
        hotKeyRef = ref
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            MainActor.assumeIsolated { HotKey.actions[pressed.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// ⌥⌘H
    static func toggleCard(_ action: @escaping @MainActor () -> Void) -> HotKey {
        HotKey(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(optionKey | cmdKey), action: action)
    }

    /// ⌥⌘A — answer the last utterance the assistant skipped.
    static func answerLast(_ action: @escaping @MainActor () -> Void) -> HotKey {
        HotKey(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey | cmdKey), action: action)
    }
}
