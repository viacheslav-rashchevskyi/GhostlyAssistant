import AssistantCore
import SwiftUI

/// The floating Liquid Glass card: status line, latest question and answer, collapsed history, input field.
/// Fills the panel, so the user sizes it by resizing the window.
struct CardView: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void

    @State private var showHistory = false
    @State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
                .frame(maxHeight: .infinity, alignment: .top)
            TextField("Спросить самому…", text: $typed)
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .onSubmit {
                    model.ask(typed)
                    typed = ""
                }
        }
        .padding(12)
        .frame(minWidth: 260, maxWidth: .infinity, minHeight: 120, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular.tint(.black.opacity(0.25)), in: .rect(cornerRadius: 18))
        .environment(\.colorScheme, .dark)
    }

    private var latest: CardAnswer? { model.answers.last }

    /// Also the drag handle: text selection in the answer would otherwise swallow window drags.
    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.audioPresent ? Color.red : Color.gray)
                .frame(width: 7, height: 7)
            Text(model.audioPresent ? "Слушаю" : "Жду звук")
            Spacer()
            if latest?.lookingUpKB == true {
                Text("ищу в базе…")
            } else if let latency = latest?.latency {
                Text(latency.label).monospacedDigit()
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    @ViewBuilder
    private var content: some View {
        switch model.status {
        case .needsKey:
            notice("Добавьте ключ в настройках", button: "Открыть настройки", action: openSettings)
        case .needsPermission:
            notice("Нет разрешения на запись экрана. После выдачи разрешения перезапустите приложение.",
                   button: "Открыть настройки", action: ScreenPermission.openSettings)
        case .downloadingModel(let p):
            notice("Загрузка модели распознавания… \(Int(p * 100))%")
        case .error(let message):
            notice(message)
        case .ready:
            answers
        }
    }

    @ViewBuilder
    private var answers: some View {
        let earlier = Array(model.answers.dropLast())
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !earlier.isEmpty {
                    Button(showHistory ? "↓ скрыть предыдущие" : RussianPlural.previousAnswers(earlier.count)) {
                        showHistory.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    if showHistory {
                        ForEach(earlier) { AnswerBlock(answer: $0, dimmed: true) }
                        Divider()
                    }
                }
                if let latest {
                    AnswerBlock(answer: latest, dimmed: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.bottom)
    }

    private func notice(_ text: String, button: String? = nil, action: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.callout)
            if let button, let action {
                Button(button, action: action).controlSize(.small)
            }
        }
    }
}

private struct AnswerBlock: View {
    let answer: CardAnswer
    let dimmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("❓ \(answer.question)")
                .font(.caption)
                .foregroundStyle(Color(red: 0.62, green: 0.80, blue: 1.0))
                .lineLimit(dimmed ? 1 : 2)
            if !answer.text.isEmpty {
                Text(markdown(answer.text))
                    .font(dimmed ? .caption : .callout)
                    .foregroundStyle(dimmed ? .secondary : .primary)
                    .textSelection(.enabled)
                    .shadow(color: .black.opacity(0.35), radius: 1)
            }
            if let error = answer.error {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
