import Foundation

/// Multilingual Whisper models from argmaxinc/whisperkit-coreml; sizes measured from the repository.
struct WhisperModelInfo: Identifiable, Equatable {
    let variant: String
    let title: String
    let sizeMB: Int
    let note: String

    var id: String { variant }

    var sizeLabel: String {
        sizeMB >= 1000 ? String(format: "%.1f ГБ", Double(sizeMB) / 1000).replacingOccurrences(of: ".", with: ",") : "\(sizeMB) МБ"
    }
}

enum WhisperCatalog {
    static let recommended = "large-v3-v20240930_626MB"

    static let models: [WhisperModelInfo] = [
        WhisperModelInfo(variant: "tiny", title: "Tiny", sizeMB: 77, note: "Мгновенно, но часто ошибается"),
        WhisperModelInfo(variant: "base", title: "Base", sizeMB: 147, note: "Очень быстро, грубо"),
        WhisperModelInfo(variant: "small_216MB", title: "Small, сжатая", sizeMB: 217, note: "Быстро, средне"),
        WhisperModelInfo(variant: "small", title: "Small", sizeMB: 486, note: "Быстро, средне"),
        WhisperModelInfo(variant: "large-v3-v20240930_626MB", title: "Large v3 Turbo, сжатая", sizeMB: 627, note: "Быстро и точно"),
        WhisperModelInfo(variant: "large-v3_947MB", title: "Large v3, сжатая", sizeMB: 948, note: "Точнее, медленнее"),
        WhisperModelInfo(variant: "medium", title: "Medium", sizeMB: 1530, note: "Медленнее Turbo, не точнее"),
        WhisperModelInfo(variant: "large-v3-v20240930", title: "Large v3 Turbo", sizeMB: 1620, note: "Как сжатая Turbo, но тяжелее"),
        WhisperModelInfo(variant: "large-v3", title: "Large v3", sizeMB: 3090, note: "Максимум точности, самая медленная")
    ]
}
