import SwiftUI

/// Add or edit a task or deadline: its kind, title, due day, priority and notes. A limitation
/// entry needs its last date and starts at high priority. `TaskEditor` holds the rules.
struct TaskSheet: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let projectID: String
    /// The task to edit; nil adds one of `kind`.
    var task: ProjectTask?
    var kind = "task"
    let onSaved: () -> Void

    @State private var model: TaskEditor?

    var body: some View {
        Group {
            if let model {
                form(model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard model == nil else { return }
            model = TaskEditor(projectID: projectID, task: task, kind: kind, writes: session.projectWrites)
        }
    }

    private func form(_ model: TaskEditor) -> some View {
        @Bindable var model = model
        return MatterFormSheet(
            title: model.isEdit ? "Edit task" : "Add task", actionTitle: model.isEdit ? "Save" : "Add",
            actionID: "task-save", isSaving: model.isSaving, error: model.error,
            onCancel: { dismiss() },
            onAction: { save(model) }
        ) {
            Section {
                MatterField(label: "Title") {
                    TextField("File the rejoinder", text: $model.draft.title, axis: .vertical)
                        .lineLimit(1...3)
                        .accessibilityIdentifier("task-title")
                }
                Picker("Kind", selection: $model.draft.kind) {
                    ForEach(MatterVocabulary.TaskKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind.rawValue)
                    }
                }
                MatterDayField(label: model.draft.kind == "limitation" ? "Last date" : "Due", day: $model.draft.dueDate)
                Picker("Priority", selection: $model.draft.priority) {
                    ForEach(MatterVocabulary.Priority.allCases, id: \.self) { priority in
                        Text(priority.label).tag(priority.rawValue)
                    }
                }
                if model.isEdit {
                    Toggle("Done", isOn: Binding(
                        get: { model.draft.status == "done" },
                        set: { model.draft.status = $0 ? "done" : "open" }))
                }
            }
            .listRowBackground(theme.surface)

            Section {
                TextField("Notes", text: $model.draft.notes, axis: .vertical)
                    .lineLimit(2...6)
                    .accessibilityLabel("Notes")
            } header: {
                Text("Notes")
            }
            .listRowBackground(theme.surface)
        }
    }

    private func save(_ model: TaskEditor) {
        Task {
            guard await model.save() != nil else { return }
            onSaved()
            dismiss()
        }
    }
}
