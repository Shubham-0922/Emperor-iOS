import SwiftUI

/// Add or edit one of the matter's own chronology entries: its kind, its date — to the day, the
/// month or only the year, as a lawyer often knows it — a title and the details. An edited entry
/// keeps where it came from. `ChronologyEditor` holds the rules.
struct ChronologyEntrySheet: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let projectID: String
    /// The entry to edit; nil adds one.
    var entry: MatterRecord.Entry?
    let today: String
    /// Once saved, with the matter's next hearing as it now stands.
    let onSaved: (SavedUpdate) -> Void

    @State private var model: ChronologyEditor?

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
            model = ChronologyEditor(projectID: projectID, entry: entry, today: today, writes: session.projectWrites)
        }
    }

    private func form(_ model: ChronologyEditor) -> some View {
        @Bindable var model = model
        return MatterFormSheet(
            title: model.isEdit ? "Edit entry" : "Add to the chronology", actionTitle: model.isEdit ? "Save" : "Add",
            actionID: "chronology-save", isSaving: model.isSaving, error: model.error,
            onCancel: { dismiss() },
            onAction: { save(model) }
        ) {
            Section {
                Picker("Kind", selection: $model.draft.kind) {
                    ForEach(MatterVocabulary.ChronoKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind.rawValue)
                    }
                }
                RecordSegmentedControl(
                    label: "Date known to the",
                    options: ChronologyDraft.Precision.allCases.map { (value: $0, title: $0.label) },
                    selection: $model.draft.precision)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                MatterDayField(label: "Date", day: $model.draft.day, allowsClear: false)
            } footer: {
                if model.draft.kind == "hearing" {
                    Text("A hearing dated today or later becomes the matter's next hearing when it is the soonest.")
                }
            }
            .listRowBackground(theme.surface)

            Section {
                MatterField(label: "Title") {
                    TextField("Notice issued, written statement filed…", text: $model.draft.title, axis: .vertical)
                        .lineLimit(1...3)
                        .accessibilityIdentifier("chronology-title")
                }
                MatterField(label: "Details") {
                    TextField("What happened", text: $model.draft.body, axis: .vertical)
                        .lineLimit(3...8)
                }
                if !model.draft.sourceRef.isEmpty {
                    Label(model.draft.sourceRef, systemImage: "doc")
                        .font(.brand(.caption))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .listRowBackground(theme.surface)
        }
    }

    private func save(_ model: ChronologyEditor) {
        Task {
            guard let saved = await model.save() else { return }
            onSaved(saved)
            dismiss()
        }
    }
}
