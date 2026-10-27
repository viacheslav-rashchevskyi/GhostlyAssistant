import AssistantCore
import SwiftUI

/// The floating Liquid Glass card: status line, latest question and answer, collapsed history, input field.
struct CardView: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void

    @State private var showHistory = false
    @State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
            TextField("Спитати самому…", text: $typed)
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .onSubmit {
                    model.ask(typed)
                    typed = ""
                }
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .frame(maxHeight: 420, alignment: .top)
        .glassEffect(.regular.tint(.black.opacity(0.25)), in: .rect(cornerRadius: 18))
        .environment(\.colorScheme, .dark)
    }

    private var latest: CardAnswer? { model.answers.last }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.audioPresent ? Color.red : Color.gray)
                .frame(width: 7, height: 7)
            Text(model.audioPresent ? "Слухаю" : "Очікую звук")
            Spacer()
            if latest?.lookingUpKB == true {
                Text("шукаю в базі…")
            } else if let latency = latest?.latency {
                Text(latency.label).monospacedDigit()
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var content: some View {
        switch model.status {
        case .needsKey:
            notice("Додайте ключ у налаштуваннях", button: "Відкрити налаштування", action: openSettings)
        case .needsPermission:
            notice("Немає дозволу на запис екрана. Після надання дозволу перезапустіть застосунок.",
                   button: "Відкрити налаштування", action: ScreenPermission.openSettings)
        case .downloadingModel(let p):
            notice("Завантаження моделі розпізнавання… \(Int(p * 100))%")
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
                    Button(showHistory ? "↓ сховати попередні" : UkrainianPlural.previousAnswers(earlier.count)) {
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
        .frame(maxHeight: 340)
        .fixedSize(horizontal: false, vertical: true)
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
