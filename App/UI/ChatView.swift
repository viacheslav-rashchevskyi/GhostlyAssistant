import AssistantCore
import SwiftUI

/// The floating chat: what the call said, what the assistant answered, and an input bar for the user's own questions.
struct ChatView: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChatHeader(model: model)
            Divider().opacity(0.25)
            Group {
                if model.status == .ready {
                    if model.turns.isEmpty { EmptyChat() } else { Messages(model: model) }
                } else {
                    StatusNotice(status: model.status, openSettings: openSettings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            InputBar(model: model)
        }
        .frame(minWidth: 300, maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
        .id(model.uiLanguage) // rebuild every string when the interface language changes
        .tint(Theme.accent)
        .background(Theme.window)
        .overlay(RoundedRectangle(cornerRadius: CardPanel.cornerRadius, style: .continuous).strokeBorder(Theme.hairline))
        .focusEffectDisabled()
    }
}

// MARK: - Header

private struct ChatHeader: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            GhostGlyph(size: 15)
            Text("Ghostly")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            ListeningPill(active: model.audioPresent)
            Spacer()
            if let latency = model.latestLatency {
                Label(latency.localizedLabel, systemImage: "bolt.fill")
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .layoutPriority(-1)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            if !model.turns.isEmpty {
                Button {
                    withAnimation(.smooth) { model.clearChat() }
                } label: {
                    Image(systemName: "trash").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help(L("Очистить чат"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .animation(.smooth, value: model.latestLatency)
    }
}

private struct ListeningPill: View {
    let active: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform")
            Text(active ? L("Слушаю") : L("Тишина"))
                .contentTransition(.opacity)
        }
        .lineLimit(1)
        .fixedSize()
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(active ? Theme.accent : Color.secondary)
        .background(Capsule().fill(active ? Theme.accentSoft : Color.primary.opacity(0.06)))
        .animation(.smooth, value: active)
    }
}

// MARK: - Messages

private struct Messages: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(model.turns) { turn in
                    TurnView(turn: turn) { model.answerSkipped(turn.id) }
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                }
            }
            .padding(12)
            .animation(.spring(duration: 0.35, bounce: 0.2), value: model.turns.map(\.id)) // only on insert/remove, not on every streamed word
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.bottom)
    }
}

private struct TurnView: View {
    let turn: ChatTurn
    let answer: () -> Void

    var body: some View {
        if turn.isSkipped {
            SkippedLine(turn: turn, answer: answer)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if turn.source == .user {
                    UserBubble(text: turn.question ?? "")
                } else {
                    CallBubble(turn: turn)
                }
                if turn.step != .transcribing {
                    AssistantBubble(turn: turn)
                }
            }
        }
    }
}

/// What a participant said on the call.
private struct CallBubble: View {
    let turn: ChatTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(L("Собеседник"), systemImage: "person.wave.2.fill")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Group {
                if let question = turn.question {
                    Text(question)
                        .transition(.blurReplace)
                } else {
                    HStack(spacing: 6) {
                        TypingDots()
                        Text(L("распознаю речь")).foregroundStyle(.secondary)
                    }
                    .transition(.blurReplace)
                }
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.08)))
            .animation(.smooth, value: turn.question)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 40)
    }
}

/// The user's own typed or dictated question.
private struct UserBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accent))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 40)
    }
}

private struct AssistantBubble: View {
    let turn: ChatTurn

    private var inProgress: Bool {
        switch turn.step {
        case .thinking, .searching, .answering: true
        default: false
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            GhostGlyph(size: 13, pulsing: inProgress)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(0.08)))
            VStack(alignment: .leading, spacing: 6) {
                if inProgress {
                    PipelineSteps(step: turn.step)
                }
                if turn.answer.isEmpty {
                    if turn.step == .searching {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text(L("ищу в базе знаний")).foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    } else if inProgress {
                        TypingDots()
                    }
                } else {
                    Text(markdown(turn.answer))
                        .font(.callout)
                        .textSelection(.enabled)
                        .transition(.blurReplace)
                }
                if let error = turn.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let latency = turn.latency {
                    Text(latency.localizedLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
            .animation(.smooth, value: turn.step)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// Chatter that wasn't a question: one quiet line instead of a bubble.
private struct SkippedLine: View {
    let turn: ChatTurn
    let answer: () -> Void
    @State private var hovering = false

    private var reason: String {
        switch turn.step {
        case .skipped(.nothingHeard): L("ничего не разобрал")
        case .skipped(.tooShort): L("слишком коротко")
        default: L("не вопрос")
        }
    }

    private var canAnswer: Bool {
        turn.question != nil && turn.step != .skipped(.nothingHeard)
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "ear").font(.caption2)
            if let q = turn.question {
                Text("«\(q)»").lineLimit(1).truncationMode(.tail)
            }
            Text("· \(reason)").layoutPriority(1)
            if canAnswer {
                Spacer(minLength: 4)
                Button(action: answer) {
                    Label(L("Ответить"), systemImage: "arrowshape.turn.up.left.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0.6)
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Распознаю → Думаю/Ищу в базе → Отвечаю, with a glowing marker that slides to the active step.
private struct PipelineSteps: View {
    let step: ChatTurn.Step
    @Namespace private var marker

    private var active: Int {
        switch step {
        case .transcribing: 0
        case .thinking, .searching: 1
        default: 2
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            item(L("Распознаю"), 0)
            item(step == .searching ? L("Ищу в базе") : L("Думаю"), 1)
            item(L("Отвечаю"), 2)
        }
        .font(.caption2.weight(.medium))
        .animation(.spring(duration: 0.4, bounce: 0.25), value: active)
    }

    private func item(_ title: String, _ index: Int) -> some View {
        HStack(spacing: 3) {
            if index < active {
                Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.green)
            }
            Text(title)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .foregroundStyle(index == active ? Theme.accent : (index < active ? Color.secondary : Color.secondary.opacity(0.5)))
        .background {
            if index == active {
                Capsule()
                    .fill(Theme.accentSoft)
                    .matchedGeometryEffect(id: "marker", in: marker)
            }
        }
    }
}

/// The Ghostly ghost, white like the app icon; gently pulses while the assistant is working.
private struct GhostGlyph: View {
    let size: CGFloat
    var pulsing = false

    var body: some View {
        let glyph = Image("GhostGlyph")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(.primary)
        // The loop exists only while pulsing: an always-running phaseAnimator redraws the window every frame.
        if pulsing {
            glyph.phaseAnimator([false, true]) { content, phase in
                content
                    .opacity(phase ? 0.45 : 1)
                    .offset(y: phase ? -1.5 : 0)
            } animation: { _ in .easeInOut(duration: 0.7) }
        } else {
            glyph
        }
    }
}

/// Three bouncing dots.
private struct TypingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .frame(width: 5, height: 5)
                        .offset(y: -3 * max(0, sin((t * 6) - Double(i) * 0.7)))
                        .opacity(0.4 + 0.6 * max(0, sin((t * 6) - Double(i) * 0.7)))
                }
            }
            .foregroundStyle(.secondary)
            .frame(height: 10)
        }
    }
}

// MARK: - Empty and status states

private struct EmptyChat: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.accent)
            Text(L("Слушаю звонок"))
                .font(.headline)
            Text(L("Вопросы собеседников и ответы появятся здесь. Можно спросить и самому — текстом или голосом."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}

private struct StatusNotice: View {
    let status: CardStatus
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            switch status {
            case .needsKey:
                notice("key.fill", L("Добавьте ключ Claude API в настройках"), button: L("Открыть настройки"), action: openSettings)
            case .needsPermission:
                notice("lock.shield", L("Нет разрешения на запись экрана. После выдачи разрешения перезапустите приложение."),
                       button: L("Открыть настройки"), action: ScreenPermission.openSettings)
            case .downloadingModel(let p):
                notice("arrow.down.circle", L("Загрузка модели распознавания… %d%%", Int(p * 100)))
                ProgressView(value: p).frame(width: 180)
            case .error(let message):
                notice("exclamationmark.triangle", message)
            case .ready:
                EmptyView()
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private func notice(_ icon: String, _ text: String, button: String? = nil, action: (() -> Void)? = nil) -> some View {
        Image(systemName: icon)
            .font(.system(size: 28, weight: .light))
            .foregroundStyle(.secondary)
        Text(text)
            .font(.callout)
            .multilineTextAlignment(.center)
        if let button, let action {
            Button(button, action: action)
                .buttonStyle(.quiet)
                .controlSize(.small)
        }
    }
}

// MARK: - Input

private struct InputBar: View {
    @ObservedObject var model: AppModel
    @State private var text = ""
    @FocusState private var focused: Bool

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = model.micError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
            HStack(spacing: 8) {
                if model.mic == .recording {
                    RecordingIndicator(level: model.micLevel)
                        .transition(.blurReplace)
                } else if model.mic == .transcribing {
                    HStack(spacing: 6) {
                        TypingDots()
                        Text(L("распознаю ваш вопрос")).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.blurReplace)
                } else {
                    TextField(L("Спросить…"), text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .lineLimit(1...4)
                        .focused($focused)
                        .onSubmit(send)
                        .transition(.blurReplace)
                }
                MicButton(state: model.mic, level: model.micLevel) { model.toggleMic() }
                    .disabled(model.status != .ready)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(canSend ? Theme.onAccent : Color.primary.opacity(0.5), canSend ? Theme.accent : Color.primary.opacity(0.15))
                        .scaleEffect(canSend ? 1 : 0.9)
                }
                .buttonStyle(.plain)
                .disabled(!canSend || model.mic != .idle)
                .help(L("Отправить"))
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.raised))
        }
        .padding(10)
        .animation(.smooth(duration: 0.25), value: model.mic)
        .animation(.smooth(duration: 0.2), value: canSend)
        .animation(.smooth, value: model.micError)
    }

    private func send() {
        guard canSend else { return }
        model.ask(text)
        text = ""
    }
}

private struct MicButton: View {
    let state: MicState
    let level: Float
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if state == .recording {
                    Circle()
                        .fill(Color.red.opacity(0.25))
                        .frame(width: 30, height: 30)
                        .scaleEffect(1 + CGFloat(level) * 0.6)
                        .animation(.easeOut(duration: 0.12), value: level)
                }
                Image(systemName: state == .recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(state == .recording ? Color.red : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .disabled(state == .transcribing)
        .help(state == .recording ? L("Остановить и спросить") : L("Спросить голосом"))
    }
}

/// Live bars that follow the microphone level while recording.
private struct RecordingIndicator: View {
    let level: Float

    var body: some View {
        HStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1.0 / 24)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 2) {
                    ForEach(0..<14) { i in
                        Capsule()
                            .fill(Color.red.opacity(0.8))
                            .frame(width: 2.5, height: 4 + CGFloat(level) * 16 * CGFloat(0.5 + 0.5 * sin(t * 9 + Double(i))))
                    }
                }
                .frame(height: 20)
            }
            Text(L("Говорите… нажмите ■, чтобы спросить"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
