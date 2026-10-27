import SwiftUI

/// The documents a matter's conversation reads — the web's `ProjectSubmitFiles`: the matter's own
/// files only, by folder, the readable ones tickable, and "Attach from My Files" for a document
/// the matter does not hold yet. Shown in place of the library picker for a matter's conversation;
/// the library picker itself is left as it is.
struct MatterFilesPicker: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let projectID: String
    let alreadyAttached: [ChatAttachment]
    let onAttach: ([ChatAttachment]) -> Void

    @State private var model: MatterFilesViewModel?
    @State private var chosen: [ChatAttachment] = []
    @State private var isAttachingFromMyFiles = false
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(theme.groupedBackground)
            .navigationTitle("This matter’s documents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onAttach(chosen)
                        dismiss()
                    }
                    .accessibilityIdentifier("matter-files-picker-done")
                }
            }
            .recordToast($toast)
        }
        .sheet(isPresented: $isAttachingFromMyFiles) {
            AttachFromMyFilesSheet(
                projectID: projectID, destinations: model?.destinations ?? MatterFilesService.standardFolders,
                destination: MatterFilesService.standardFolders[0]
            ) { summary in
                toast = summary
                let model = self.model
                Task { await model?.load() }
            }
        }
        .task {
            guard model == nil else { return }
            chosen = alreadyAttached
            let created = MatterFilesViewModel(projectID: projectID, service: session.matterFiles)
            model = created
            await created.load()
        }
    }

    @ViewBuilder
    private func content(_ model: MatterFilesViewModel) -> some View {
        List {
            Section {
                Button {
                    isAttachingFromMyFiles = true
                } label: {
                    Label("Attach from My Files", systemImage: "paperclip")
                }
                .accessibilityIdentifier("matter-files-picker-attach")
            } footer: {
                Text("Only this matter’s documents can be read here. Documents come into the matter from My Files.")
            }
            .listRowBackground(theme.surface)

            if let failure = model.state.failure {
                Section {
                    Text(failure.message)
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.danger)
                    Button("Try again") { Task { await model.load() } }
                }
                .listRowBackground(theme.surface)
            } else if model.allFiles.isEmpty, model.state == .loaded {
                Section {
                    Text("This matter has no documents yet.")
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textTertiary)
                }
                .listRowBackground(theme.surface)
            } else {
                ForEach(model.folders.filter { $0.count > 0 }) { folder in
                    Section {
                        ForEach(model.files(in: folder.sub)) { file in
                            fileRow(file)
                        }
                    } header: {
                        Text(folder.name)
                    }
                    .listRowBackground(theme.surface)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("matter-files-picker")
    }

    private func fileRow(_ file: MatterFile) -> some View {
        let attachment = file.attachment
        let isChosen = chosen.contains(attachment)
        let symbol = isChosen ? "checkmark.circle.fill" : "circle"
        return Button {
            toggle(attachment)
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(file.isReady ? theme.accentText : theme.textTertiary)
                    .accessibilityHidden(true)
                Text(DisplayText.fileName(file.name))
                    .font(.brand(.body))
                    .foregroundStyle(file.isReady ? theme.textPrimary : theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let status = file.statusText {
                    StatusPill(text: status, tone: file.isFailed ? .danger : .warning)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!file.isReady)
        .accessibilityLabel(file.name)
        .accessibilityValue(isChosen ? "Selected" : "")
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func toggle(_ attachment: ChatAttachment) {
        if let index = chosen.firstIndex(of: attachment) {
            chosen.remove(at: index)
        } else {
            chosen.append(attachment)
        }
    }
}
