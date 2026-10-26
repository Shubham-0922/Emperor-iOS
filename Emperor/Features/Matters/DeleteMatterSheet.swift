import SwiftUI

/// Delete matter: typing the matter's name is the confirmation, as the server demands — this is
/// the one action on a matter that cannot be walked back. It says what goes with it, and that a
/// linked case stays tracked. `MatterDeletion` holds the match rule (surrounding spaces forgiven,
/// nothing else) and sends the stored name.
struct DeleteMatterSheet: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let project: Project
    let onDeleted: (_ message: String) -> Void

    @State private var model: MatterDeletion?

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
            model = MatterDeletion(project: project, writes: session.projectWrites)
        }
    }

    private func form(_ model: MatterDeletion) -> some View {
        @Bindable var model = model
        return MatterFormSheet(
            title: "Delete matter", actionTitle: "Delete matter", actionID: "delete-matter-confirm",
            isSaving: model.isDeleting, error: model.error, destructive: true,
            actionDisabled: !model.matches(model.typed),
            onCancel: { dismiss() },
            onAction: { delete(model) }
        ) {
            Section {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("This permanently deletes \(model.storedName) and everything in it:")
                        .font(.brand(.subheadline, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(model.consequences, id: \.self) { line in
                        Label(line, systemImage: "minus")
                            .font(.brand(.footnote))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(MatterDeletion.footnote)
                        .font(.brand(.caption))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Spacing.xs)
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(theme.surface)

            Section {
                TextField(model.storedName, text: $model.typed)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Type \(model.storedName) to confirm")
                    .accessibilityIdentifier("delete-matter-name")
            } header: {
                Text("Type the matter name to confirm")
            }
            .listRowBackground(theme.surface)
        }
        .presentationDetents([.medium, .large])
    }

    private func delete(_ model: MatterDeletion) {
        Task {
            guard await model.delete() else { return }
            onDeleted(model.deletedMessage)
            dismiss()
        }
    }
}
