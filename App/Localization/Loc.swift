import AssistantCore
import Foundation

/// Interface language, switchable at runtime from settings.
enum UILanguage: String, CaseIterable, Identifiable {
    case ru, en

    var id: String { rawValue }
    var title: String { self == .ru ? "Русский" : "English" }
}

/// Russian source strings are the keys; English comes from `Loc.en`. Views re-render on a language change
/// because their roots are keyed by the language (`.id(model.uiLanguage)`).
enum Loc {
    nonisolated(unsafe) static var language: UILanguage =
        UserDefaults.standard.string(forKey: "uiLanguage").flatMap(UILanguage.init(rawValue:)) ?? .ru

    static func text(_ ru: String) -> String {
        language == .ru ? ru : (en[ru] ?? ru)
    }

    /// Messages produced in Russian by the core (answer errors) carry numbers, so they are matched by shape.
    static func coreMessage(_ ru: String) -> String {
        guard language == .en else { return ru }
        if let m = ru.firstMatch(of: /Ошибка API \((\d+)\)\./) { return "API error (\(m.1)). Will try again on the next question." }
        if ru.hasPrefix("Нет сети") { return "No network. Will try again on the next question." }
        if ru.hasPrefix("Модель отказалась") { return "The model declined to answer." }
        return ru
    }

    static let en: [String: String] = [
        // Chat
        "Слушаю": "Listening",
        "Тишина": "Silence",
        "Очистить чат": "Clear chat",
        "Собеседник": "Participant",
        "распознаю речь": "recognizing speech",
        "Распознаю": "Recognizing",
        "Думаю": "Thinking",
        "Ищу в базе": "Searching docs",
        "Отвечаю": "Answering",
        "ищу в базе знаний": "searching the knowledge base",
        "не вопрос": "not a question",
        "слишком коротко": "too short",
        "ничего не разобрал": "couldn't make it out",
        "Слушаю звонок": "Listening to the call",
        "Вопросы собеседников и ответы появятся здесь. Можно спросить и самому — текстом или голосом.":
            "Questions from the call and answers will appear here. You can ask yourself too — by text or voice.",
        "Добавьте ключ Claude API в настройках": "Add your Claude API key in settings",
        "Открыть настройки": "Open settings",
        "Нет разрешения на запись экрана. После выдачи разрешения перезапустите приложение.":
            "No screen recording permission. Restart the app after granting it.",
        "Загрузка модели распознавания… %d%%": "Downloading the speech model… %d%%",
        "Спросить…": "Ask…",
        "распознаю ваш вопрос": "recognizing your question",
        "Говорите… нажмите ■, чтобы спросить": "Speak… press ■ to ask",
        "Отправить": "Send",
        "Остановить и спросить": "Stop and ask",
        "Спросить голосом": "Ask by voice",
        "Не расслышал, попробуйте ещё раз": "Didn't catch that, try again",
        "Нет доступа к микрофону — разрешите в Системных настройках": "No microphone access — allow it in System Settings",
        "Микрофон недоступен: %@": "Microphone unavailable: %@",
        "Не удалось запустить: %@": "Couldn't start: %@",
        // Menu
        "Скрыть окно": "Hide window",
        "Показать окно": "Show window",
        "Настройки…": "Settings…",
        "Выйти": "Quit",
        // Settings
        "Настройки": "Settings",
        "Работает": "Running",
        "Нужен ключ API": "API key needed",
        "Нужно разрешение на запись экрана": "Screen recording permission needed",
        "Загружается модель распознавания": "Loading the speech model",
        "Ошибка запуска": "Startup error",
        "Язык интерфейса": "Interface language",
        "Язык меню, чата и настроек": "Language of the menu, chat and settings",
        "Ключ Claude API": "Claude API key",
        "Хранится только в Связке ключей macOS": "Stored only in the macOS Keychain",
        "Ключ сохранён": "Key saved",
        "Заменить": "Replace",
        "Сохранить": "Save",
        "Отмена": "Cancel",
        "Где взять ключ →": "Get a key →",
        "Модель Claude": "Claude model",
        "Кто отвечает на вопросы. Цена — за 1M токенов на вход / выход": "Who answers. Price per 1M input / output tokens",
        "рекомендуется": "recommended",
        "Самая быстрая — для живого звонка": "Fastest — made for a live call",
        "Баланс ума и скорости": "Balance of smarts and speed",
        "Умная, отвечает медленнее": "Smart, answers slower",
        "Самая мощная — долго думает, для звонка медленная": "Most capable — thinks long, slow for a call",
        "цена неизвестна": "price unknown",
        "Обновляю список и цены…": "Updating models and prices…",
        "Список из API, цены из встроенной таблицы": "Models from the API, built-in prices",
        "Список из API, цены с anthropic.com": "Models from the API, prices from anthropic.com",
        "Нет связи с API — показаны известные модели": "API unreachable — showing known models",
        "Обновить": "Refresh",
        "Свернуть": "Collapse",
        "Все модели (%d)": "All models (%d)",
        "Распознавание речи": "Speech recognition",
        "Whisper работает на Mac, без интернета": "Whisper runs on your Mac, offline",
        "Собеседники в звонке": "People on the call",
        "Что слушает Whisper из звука Zoom": "What Whisper hears from Zoom audio",
        "Ваш голос": "Your voice",
        "Вопросы, которые вы задаёте кнопкой микрофона": "Questions you ask with the mic button",
        "Точно выбранный язык распознаётся быстрее и надёжнее, чем автоопределение. Ответ всегда приходит на языке вопроса.":
            "A fixed language is recognized faster and more reliably than auto-detect. Answers always come in the question's language.",
        "Автоопределение": "Auto-detect",
        "Модель распознавания": "Speech model",
        "Версия Whisper. Крупнее — точнее, но медленнее": "Whisper version. Bigger is more accurate but slower",
        "Мгновенно, но часто ошибается": "Instant, but often wrong",
        "Очень быстро, грубо": "Very fast, rough",
        "Быстро, средне": "Fast, average",
        "Быстро и точно": "Fast and accurate",
        "Точнее, медленнее": "More accurate, slower",
        "Медленнее Turbo, не точнее": "Slower than Turbo, not more accurate",
        "Как сжатая Turbo, но тяжелее": "Like compressed Turbo, but heavier",
        "Максимум точности, самая медленная": "Most accurate, slowest",
        "Small, сжатая": "Small, compressed",
        "Large v3 Turbo, сжатая": "Large v3 Turbo, compressed",
        "Large v3, сжатая": "Large v3, compressed",
        "Активна": "Active",
        "скачана": "downloaded",
        "загружаю": "loading",
        "удаляю": "deleting",
        "Скачать": "Download",
        "Отменить загрузку": "Cancel download",
        "Удалить с диска": "Delete from disk",
        "Модель используется — сначала выберите другую": "In use — select another model first",
        "Удалить модель «%@»?": "Delete the “%@” model?",
        "Удалить (%@)": "Delete (%@)",
        "Файлы модели будут удалены с диска. Её всегда можно скачать снова.": "The model files will be removed. You can always download it again.",
        "Скачано моделей: %d · занято на диске %@": "Models downloaded: %d · %@ on disk",
        "Открыть": "Open",
        "Открыть папку с моделями в Finder": "Show the models folder in Finder",
        "Не удалось скачать модель: %@": "Couldn't download the model: %@",
        "Не удалось загрузить модель: %@": "Couldn't load the model: %@",
        "Не удалось удалить модель: %@": "Couldn't delete the model: %@",
        "%.1f ГБ": "%.1f GB",
        "%d МБ": "%d MB",
        "База знаний": "Knowledge base",
        "Необязательно. PDF, Word, текст, Markdown и картинки": "Optional. PDF, Word, text, Markdown and images",
        "Перетащите файлы или папку сюда": "Drop files or a folder here",
        "Выбрать…": "Choose…",
        "Добавить": "Add",
        "Перечитать": "Reload",
        "Очистить": "Clear",
        "Убрать из базы": "Remove from the knowledge base",
        "не читается": "unreadable",
        "Пропущены: %@": "Skipped: %@",
        "Читаю файлы…": "Reading files…",
        "Целиком в контексте · %@ токенов": "Fully in context · %@ tokens",
        "Поиск по базе · %@ токенов": "Search mode · %@ tokens",
        "Нечего читать": "Nothing to read",
        "Демонстрация экрана": "Screen sharing",
        "Как спрятать чат от трансляции в Zoom": "How to keep the chat out of a Zoom share",
        "Проверьте на устройстве другого участника, что чата не видно": "Check on another participant's device that the chat isn't visible",
        "Если чат всё равно виден — демонстрируйте отдельное окно, а не весь экран, или другой дисплей (чат держите на экране ноутбука).":
            "If the chat still shows — share a single window instead of the whole screen, or another display (keep the chat on the laptop screen).",
        "Скрыть или показать чат:": "Hide or show the chat:"
    ]
}

/// Localized UI string; `args` fill `%d` / `%@` placeholders.
func L(_ ru: String, _ args: CVarArg...) -> String {
    let text = Loc.text(ru)
    return args.isEmpty ? text : String(format: text, arguments: args)
}

extension ClaudePrice {
    /// "$0,10 / $0,50" in Russian, "$0.10 / $0.50" in English.
    var localizedLabel: String {
        Loc.language == .en ? label.replacingOccurrences(of: ",", with: ".") : label
    }
}

extension Latency {
    /// "0,8 с · 140 ток/с" in Russian, "0.8 s · 140 tok/s" in English.
    var localizedLabel: String {
        guard Loc.language == .en else { return label }
        let seconds = String(format: "%.1f s", (timeToFirstToken * 10).rounded() / 10)
        guard let tps = tokensPerSecond else { return seconds }
        return "\(seconds) · \(Int(tps.rounded())) tok/s"
    }
}
