import SwiftUI

/// The workspace's Tasks — the web's `TasksSection`: Overdue, Due this week, Later, No date and
/// Done, each sorted as the web sorts them. Limitation and certified-copy dates — the two that
/// cannot be missed — wear their kind in red while open. The circle ticks a task off (or reopens
/// it); each row's menu edits or deletes it; Add task opens the form.
struct MatterTasksSection: View {
    @Environment(\.theme) private var theme

    let model: MatterWorkspaceViewModel
    var edit: MatterEditActions? = nil

    var body: some View {
        let groups = model.taskGroups
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if let edit {
                Button {
                    edit.open(.task(nil, kind: "task"))
                } label: {
                    Label("Add task", systemImage: "plus")
                }
                .buttonStyle(.compactSecondaryAction)
                .accessibilityIdentifier("tasks-add")
            }
            if groups.isEmpty {
                EmptyStateContent(
                    title: "No tasks or deadlines yet", systemImage: "checklist",
                    message: "What has to be done on this matter, and by when. Start with the limitation date and any certified copy applied for — those are the dates that most often slip.",
                    tone: .neutral) {
                    if let edit {
                        Button("Limitation date") { edit.open(.task(nil, kind: "limitation")) }
                            .buttonStyle(.secondaryAction)
                        Button("Certified copy") { edit.open(.task(nil, kind: "certified_copy")) }
                            .buttonStyle(.quietAction)
                    }
                }
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
        HStack(alignment: .top, spacing: 0) {
            if let edit {
                toggle(row, edit)
            }
            taskBody(row)
            if let edit {
                MatterRowMenu(
                    name: row.title, identifier: "task-menu-\(row.id)",
                    onEdit: { edit.open(.task(row.task, kind: row.task.kind ?? "task")) },
                    onDelete: {
                        edit.run("Task deleted", { await edit.quick.deleteTask(row.id) }, error: { edit.quick.error })
                    })
                    .padding(.trailing, Spacing.xs)
            }
        }
        // A container, so the row carries its identifier and the tick and menu stay controls.
        .accessibilityElement(children: .contain)
    }

    /// The tick: done ⇄ open, the whole task sent back with it.
    private func toggle(_ row: MatterWorkspaceViewModel.TaskRow, _ edit: MatterEditActions) -> some View {
        let done = row.task.isDone
        return Button {
            edit.run(nil, { await edit.quick.toggle(row.task) }, error: { edit.quick.error })
        } label: {
            Group {
                if edit.quick.busyID == row.id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(done ? theme.success : theme.textTertiary)
                }
            }
            .frame(minWidth: Layout.touchTarget, minHeight: Layout.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(edit.quick.busyID != nil)
        .accessibilityLabel(done ? "Reopen \(row.title)" : "Mark \(row.title) done")
        .accessibilityIdentifier("task-toggle-\(row.id)")
    }

    private func taskBody(_ row: MatterWorkspaceViewModel.TaskRow) -> some View {
        let done = row.task.isDone
        return HStack(alignment: .top, spacing: Spacing.md) {
            if edit == nil {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? theme.success : theme.textTertiary)
                    .accessibilityHidden(true)
            }
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
        .padding(.leading, edit == nil ? 14 : 0)
        .padding(.trailing, edit == nil ? 14 : Spacing.xs)
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
