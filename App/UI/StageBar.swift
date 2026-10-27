import AssistantCore
import SwiftUI

/// "Распознаю → Думаю → Отвечаю" for the newest utterance, plus what was heard and why it was skipped.
struct StageBar: View {
    let live: LiveStage

    private enum StepState { case pending, active, done }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                step("Распознаю", state(at: 0))
                chevron
                step(live.step == .searching ? "Ищу в базе" : "Думаю", state(at: 1))
                chevron
                step("Отвечаю", state(at: 2))
            }
            if let line = heardLine {
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }

    private var position: Int {
        switch live.step {
        case .transcribing: 0
        case .thinking, .searching: 1
        case .answering: 2
        case .done: 3
        case .skipped(.nothingHeard), .skipped(.tooShort): 1
        case .skipped(.notAQuestion): 2
        }
    }

    private var isSkipped: Bool {
        if case .skipped = live.step { true } else { false }
    }

    private func state(at index: Int) -> StepState {
        if index < position { return .done }
        if index == position && !isSkipped { return .active }
        return .pending
    }

    private var heardLine: String? {
        let heard = live.heard.map { "Услышал: «\($0)»" }
        switch live.step {
        case .skipped(.nothingHeard): return "Ничего не разобрал"
        case .skipped(.tooShort): return (heard ?? "") + " — слишком коротко, пропускаю"
        case .skipped(.notAQuestion): return (heard ?? "") + " — не вопрос, пропускаю"
        default: return heard
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(.quaternary)
    }

    private func step(_ title: String, _ state: StepState) -> some View {
        HStack(spacing: 3) {
            switch state {
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .active:
                Image(systemName: "circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse, options: .repeating)
            case .pending:
                Image(systemName: "circle").foregroundStyle(.quaternary)
            }
            Text(title).foregroundStyle(state == .pending ? .tertiary : .secondary)
        }
        .font(.caption2)
    }
}
