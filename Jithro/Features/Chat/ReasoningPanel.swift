import SwiftUI

/// Shows what the model is doing, and what it has already done.
///
/// Collapsed by default: the answer is the point, and a practitioner reading a chronology does
/// not want a scrolling log in the way. But when an answer looks wrong, the first question is
/// always "which documents did it actually read?" — and that has to be answerable.
struct ReasoningPanel: View {
    let snapshot: ReasoningSnapshot
    let isStreaming: Bool
    let liveStatus: String?

    @State private var isExpanded = false

    var body: some View {
        if snapshot.isEmpty && liveStatus == nil {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                header
                if isExpanded {
                    Divider().padding(.vertical, 8)
                    detail
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .animation(.easeInOut(duration: 0.2), value: isExpanded)
        }
    }

    // MARK: - Header

    private var header: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                if isStreaming {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if !snapshot.isEmpty {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(snapshot.isEmpty)
    }

    /// While running, the live status is more informative than a count. Once finished, the
    /// count is what tells you whether the answer rests on real work.
    private var summary: String {
        if isStreaming, let liveStatus, !liveStatus.isEmpty { return liveStatus }
        let steps = snapshot.stepCount
        if steps == 0 { return isStreaming ? "Working…" : "Answered directly" }
        return steps == 1 ? "Worked · 1 step" : "Worked · \(steps) steps"
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !snapshot.plan.isEmpty {
                section("Plan") {
                    ForEach(snapshot.plan) { task in
                        planRow(task, isSubtask: false)
                        ForEach(task.subtasks) { subtask in
                            planRow(subtask, isSubtask: true)
                        }
                    }
                }
            }

            if !snapshot.workLog.isEmpty {
                section("Work") {
                    ForEach(snapshot.workLog) { entry in
                        switch entry {
                        case .note(_, let text, _):
                            Text(text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 2)
                        case .group(let group):
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(group.steps) { step in
                                    stepRow(step)
                                }
                            }
                            .padding(.leading, 2)
                        }
                    }
                }
            }

            if !snapshot.reasoning.isEmpty {
                section("Reasoning") {
                    ForEach(Array(snapshot.reasoning.enumerated()), id: \.offset) { _, sentence in
                        Text(sentence)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 1)
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func planRow(_ row: PlanRow, isSubtask: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            statusIcon(row.status)
            Text(row.title)
                .font(isSubtask ? .caption : .caption.weight(.medium))
                .foregroundStyle(row.status == .pending ? .tertiary : .secondary)
            Spacer(minLength: 0)
        }
        .padding(.leading, isSubtask ? 16 : 0)
    }

    private func stepRow(_ step: WorkStep) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            statusIcon(step.status)
            Text(step.label)
                .font(.caption)
                // A superseded call is struck through: it really happened, but its results
                // were thrown away, and it must not read as work the answer rests on.
                .strikethrough(step.status == .superseded)
                .foregroundStyle(step.status == .superseded ? .tertiary : .secondary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: WorkStatus) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2).foregroundStyle(.green)
        case .inProgress:
            ProgressView().controlSize(.mini)
        case .pending:
            Image(systemName: "circle").font(.caption2).foregroundStyle(.tertiary)
        case .superseded:
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.caption2).foregroundStyle(.tertiary)
        case .stopped:
            // Deliberately not a tick: the stream ended without confirming this came back.
            Image(systemName: "questionmark.circle")
                .font(.caption2).foregroundStyle(.orange)
        }
    }
}
