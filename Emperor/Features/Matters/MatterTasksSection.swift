import SwiftUI

/// The workspace's Tasks — the web's `TasksSection` read-only: Overdue, Due this week, Later,
/// No date and Done, each sorted as the web sorts them. Limitation and certified-copy dates —
/// the two that cannot be missed — wear their kind in red while open.
struct MatterTasksSection: View {
    @Environment(\.theme) private var theme

    let model: MatterWorkspaceViewModel

    var body: some View {
        let groups = model.taskGroups
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if groups.isEmpty {
                EmptyStateContent(
                    title: "No tasks or deadlines yet", systemImage: "checklist",
                    message: "Filings, limitation dates and certified copies added on the web appear here.",
                    tone: .neutral) {}
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SectionHeader(title: group.group.title, detail: "\(group.rows.count)")
                    RecordGroup {
                        ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { RecordDivider(inset: 14) }
                            taskRow(row)
                                .accessibilityIdentifier("matter-task-\(row.id)")
                        }
                    }
                }
            }
        }
    }

    private func taskRow(_ row: MatterWorkspaceViewModel.TaskRow) -> some View {
        let done = row.task.isDone
        return HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? theme.success : theme.textTertiary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    StatusPill(text: row.kindLabel, tone: row.critical ? .danger : .neutral)
                    if row.task.priority == "high", !done {
                        StatusPill(text: "High", tone: .danger, systemImage: "flag.fill")
                    }
                }
                Text(row.title)
                    .strikethrough(done)
                    .font(.brand(.body, weight: row.critical ? Font.Weight.semibold : Font.Weight.regular))
                    .foregroundStyle(done ? theme.textTertiary : theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let notes = row.task.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    Text(notes)
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                due(row)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Open")
    }

    @ViewBuilder
    private func due(_ row: MatterWorkspaceViewModel.TaskRow) -> some View {
        if row.task.isDone {
            let text = row.doneText.isEmpty ? (row.due?.text ?? "") : row.doneText
            if !text.isEmpty {
                Text(text)
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textTertiary)
            }
        } else if let due = row.due {
            HStack(spacing: Spacing.sm) {
                Text(due.text)
                    .font(.brand(.caption))
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
                if !due.rel.isEmpty {
                    StatusPill(text: due.rel, tone: Self.tone(due.tone))
                }
            }
        }
    }

    static func tone(_ tone: MatterDates.Tone) -> StatusPill.Tone {
        switch tone {
        case .danger: return .danger
        case .warn: return .warning
        case .mute: return .neutral
        }
    }
}
