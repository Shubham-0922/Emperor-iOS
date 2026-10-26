import PhotosUI
import SwiftUI

/// "Edit matter details" — every field a matter has, in one form (the web's `ProjectForm`): the
/// parties and side, practice area, forum and case number, stage, status and priority, the two
/// dates, the description, the banner (a preset or a picture) and the folder colour. Every field
/// goes back on every save, so a field cleared here is cleared on the server.
/// `MatterDetailsEditor` holds the rules and the order things are sent in.
struct MatterDetailsSheet: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let project: Project
    /// The field that takes focus first — the setup strip's "add the client" lands there.
    var focusField: String?
    /// The banner picture on file, to show until another is chosen.
    var bannerData: Data?
    /// Once saved: what to say ("Changes saved", or "Saved, but …").
    let onSaved: (_ message: String) -> Void

    @State private var model: MatterDetailsEditor?
    @State private var photo: PhotosPickerItem?
    @State private var isPreparingImage = false
    @FocusState private var focused: String?

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
            model = MatterDetailsEditor(project: project, writes: session.projectWrites, focusField: focusField)
            try? await Task.sleep(for: .milliseconds(350))
            focused = focusField ?? "name"
        }
    }

    private func form(_ model: MatterDetailsEditor) -> some View {
        @Bindable var model = model
        return MatterFormSheet(
            title: "Edit matter details", subtitle: project.displayName, actionTitle: "Save",
            actionID: "matter-details-save", isSaving: model.isSaving || isPreparingImage, busy: model.busy,
            error: model.error,
            onCancel: { dismiss() },
            onAction: { save(model) }
        ) {
            Section {
                textField("Matter name", text: $model.draft.name, key: "name")
                textField("Client", text: $model.draft.client, key: "client", prompt: "Who you act for")
                textField("Opposite party", text: $model.draft.oppositeParty, key: "oppositeParty",
                          prompt: "Who is on the other side")
                Picker("Your side", selection: $model.draft.ourSide) {
                    Text("Not set").tag("")
                    ForEach(MatterVocabulary.OurSide.allCases, id: \.self) { side in
                        Text(side.label).tag(side.rawValue)
                    }
                }
                .focused($focused, equals: "side")
                if model.draft.ourSide == "other" {
                    textField("Your side, in words", text: $model.draft.ourSideText, key: "ourSideText",
                              prompt: "Caveator, intervenor…")
                }
                Picker("Practice area", selection: $model.draft.practiceArea) {
                    Text("Not set").tag("")
                    ForEach(MatterVocabulary.PracticeArea.allCases, id: \.self) { area in
                        Text(area.label).tag(area.rawValue)
                    }
                    // A key another client stored that this list does not know stays selectable.
                    if !model.draft.practiceArea.isEmpty,
                       MatterVocabulary.PracticeArea(rawValue: model.draft.practiceArea) == nil {
                        Text(model.draft.practiceArea).tag(model.draft.practiceArea)
                    }
                }
                .focused($focused, equals: "practiceArea")
            } header: {
                Text("The matter")
            }
            .listRowBackground(theme.surface)

            Section {
                Picker("Forum", selection: $model.draft.forumType) {
                    ForEach(MatterVocabulary.Forum.allCases, id: \.self) { forum in
                        Text(forum.label).tag(forum.rawValue)
                    }
                }
                textField("Court or forum", text: $model.draft.forumName, key: "forumName",
                          prompt: "Delhi High Court")
                textField("Case type", text: $model.draft.caseType, key: "caseType", prompt: "W.P.(C)")
                textField("Case number", text: $model.draft.caseNumber, key: "caseNumber", prompt: "4412")
                textField("Year", text: $model.draft.caseYear, key: "caseYear", prompt: "2025")
                    .keyboardType(.numberPad)
                textField("CNR or diary no.", text: $model.draft.cnr, key: "cnr")
                    .textInputAutocapitalization(.characters)
                textField("Stage", text: $model.draft.stage, key: "stage", prompt: "Admission, Arguments…")
            } header: {
                Text("Court")
            }
            .listRowBackground(theme.surface)

            Section {
                Picker("Status", selection: $model.draft.status) {
                    ForEach(MatterVocabulary.ProjectStatus.allCases, id: \.self) { status in
                        Text(status.label).tag(status.rawValue)
                    }
                }
                Picker("Priority", selection: $model.draft.priority) {
                    ForEach(MatterVocabulary.Priority.allCases, id: \.self) { priority in
                        Text(priority.label).tag(priority.rawValue)
                    }
                }
                MatterDayField(label: "Next hearing", day: $model.draft.nextHearingDate)
                MatterDayField(label: "Filing date", day: $model.draft.filingDate)
            } header: {
                Text("Status and dates")
            }
            .listRowBackground(theme.surface)

            Section {
                TextField("What the matter is about", text: $model.draft.description, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityLabel("Description")
            } header: {
                Text("Description")
            }
            .listRowBackground(theme.surface)

            Section {
                MatterBannerView(
                    preset: model.preset, imageData: model.hasImage ? (model.image ?? bannerData) : nil,
                    cornerRadius: Radius.control)
                    .frame(height: 74)
                    .accessibilityHidden(true)
                MatterField(label: "Banner") {
                    BannerPicker(selected: model.hasImage ? nil : model.preset) { model.pickPreset($0) }
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(model.hasImage ? "Choose another image" : "Choose image", systemImage: "photo")
                }
                .disabled(isPreparingImage)
                if model.hasImage {
                    Button(role: .destructive) {
                        model.removeImage()
                    } label: {
                        Label("Remove image", systemImage: "trash")
                    }
                }
                MatterField(label: "Folder colour") {
                    ColourSwatches(selected: model.draft.color) { model.draft.color = $0 }
                }
            } header: {
                Text("Banner and colour")
            } footer: {
                Text("A picture is made into a JPEG of up to 2 MB before it is sent.")
            }
            .listRowBackground(theme.surface)
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await loadImage(item, into: model) }
        }
    }

    private func textField(_ label: String, text: Binding<String>, key: String, prompt: String? = nil) -> some View {
        MatterField(label: label) {
            TextField(prompt ?? label, text: text)
                .focused($focused, equals: key)
                .accessibilityIdentifier("matter-field-\(key)")
        }
    }

    /// The picked photo, as the server takes it: a PNG, JPEG or WebP of up to 2 MB as it is, else
    /// re-encoded as a JPEG under that.
    private func loadImage(_ item: PhotosPickerItem, into model: MatterDetailsEditor) async {
        isPreparingImage = true
        defer {
            isPreparingImage = false
            photo = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            model.error = "That image could not be read."
            return
        }
        if data.count <= MatterRules.bannerMaxBytes, MatterRules.bannerImageType(data) != nil {
            model.pickImage(data)
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("banner-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try data.write(to: url)
            let report = try await OnDeviceToolEngine().compressImage(url, targetBytes: MatterRules.bannerMaxBytes - 64 * 1024)
            model.pickImage(report.result.data)
        } catch {
            model.error = DisplayText.message(for: error)
        }
    }

    private func save(_ model: MatterDetailsEditor) {
        Task {
            guard await model.save() != nil else { return }
            onSaved(model.savedMessage)
            dismiss()
        }
    }
}
