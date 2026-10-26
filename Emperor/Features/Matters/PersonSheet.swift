import SwiftUI

/// Add or edit a person on the matter: their role, name, phone, email, address and notes. The
/// client's address is what the fee receipt prints. `PersonEditor` checks the email and phone as
/// the web does, then as the server does.
struct PersonSheet: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let projectID: String
    /// The person to edit; nil adds one in `role`.
    var person: ProjectPerson?
    var role = "client"
    /// A name to start with — the matter's client, say.
    var name = ""
    let onSaved: () -> Void

    @State private var model: PersonEditor?

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
            model = PersonEditor(projectID: projectID, person: person, role: role, name: name, writes: session.projectWrites)
        }
    }

    private func form(_ model: PersonEditor) -> some View {
        @Bindable var model = model
        return MatterFormSheet(
            title: model.isEdit ? "Edit person" : "Add a person", actionTitle: model.isEdit ? "Save" : "Add",
            actionID: "person-save", isSaving: model.isSaving, error: model.error,
            onCancel: { dismiss() },
            onAction: { save(model) }
        ) {
            Section {
                Picker("Role", selection: $model.draft.role) {
                    ForEach(MatterVocabulary.PeopleRole.allCases, id: \.self) { role in
                        Text(role.label).tag(role.rawValue)
                    }
                }
                MatterField(label: "Name") {
                    TextField("Full name", text: $model.draft.name)
                        .textContentType(.name)
                        .accessibilityIdentifier("person-name")
                }
                MatterField(label: "Phone") {
                    TextField("98765 43210", text: $model.draft.phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                MatterField(label: "Email") {
                    TextField("name@example.com", text: $model.draft.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                MatterField(label: "Address") {
                    TextField("For the fee receipt", text: $model.draft.address, axis: .vertical)
                        .lineLimit(1...4)
                }
                TextField("Notes", text: $model.draft.notes, axis: .vertical)
                    .lineLimit(2...6)
                    .accessibilityLabel("Notes")
            }
            .listRowBackground(theme.surface)
        }
    }

    private func save(_ model: PersonEditor) {
        Task {
            guard await model.save() != nil else { return }
            onSaved()
            dismiss()
        }
    }
}
