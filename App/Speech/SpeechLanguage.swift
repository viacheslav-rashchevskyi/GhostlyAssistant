import Foundation

/// Languages offered for speech recognition; `code` is Whisper's language code, nil means auto-detect.
enum SpeechLanguage: String, CaseIterable, Identifiable {
    case auto, uk, ru, en, pl, de, fr, es

    var id: String { rawValue }

    var code: String? { self == .auto ? nil : rawValue }

    var title: String {
        switch self {
        case .auto: "Автоопределение"
        case .uk: "Українська"
        case .ru: "Русский"
        case .en: "English"
        case .pl: "Polski"
        case .de: "Deutsch"
        case .fr: "Français"
        case .es: "Español"
        }
    }
}
