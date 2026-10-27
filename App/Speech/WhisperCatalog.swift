import Foundation

/// Multilingual Whisper models from argmaxinc/whisperkit-coreml; sizes measured from the repository.
struct WhisperModelInfo: Identifiable, Equatable {
    let variant: String
    let title: String
    let sizeMB: Int
    let note: String

    var id: String { variant }

    var sizeLabel: String {
        sizeMB >= 1000 ? L("%.1f ГБ", Double(sizeMB) / 1000).replacingOccurrences(of: ".", with: Loc.language == .ru ? "," : ".") : L("%d МБ", sizeMB)
    }
}

enum WhisperCatalog {
    static let recommended = "large-v3-v20240930_626MB"

    static let models: [WhisperModelInfo] = [
        WhisperModelInfo(variant: "tiny", title: "Tiny", sizeMB: 77, note: L("Мгновенно, но часто ошибается")),
        WhisperModelInfo(variant: "base", title: "Base", sizeMB: 147, note: L("Очень быстро, грубо")),
        WhisperModelInfo(variant: "small_216MB", title: L("Small, сжатая"), sizeMB: 217, note: L("Быстро, средне")),
        WhisperModelInfo(variant: "small", title: "Small", sizeMB: 486, note: L("Быстро, средне")),
        WhisperModelInfo(variant: "large-v3-v20240930_626MB", title: L("Large v3 Turbo, сжатая"), sizeMB: 627, note: L("Быстро и точно")),
        WhisperModelInfo(variant: "large-v3_947MB", title: L("Large v3, сжатая"), sizeMB: 948, note: L("Точнее, медленнее")),
        WhisperModelInfo(variant: "medium", title: "Medium", sizeMB: 1530, note: L("Медленнее Turbo, не точнее")),
        WhisperModelInfo(variant: "large-v3-v20240930", title: "Large v3 Turbo", sizeMB: 1620, note: L("Как сжатая Turbo, но тяжелее")),
        WhisperModelInfo(variant: "large-v3", title: "Large v3", sizeMB: 3090, note: L("Максимум точности, самая медленная"))
    ]
}
