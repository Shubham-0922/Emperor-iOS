import SwiftUI

/// The workspace's Files — the web's `FilesSection`: the matter's folders as chips (the five
/// standard ones first, in their fixed order, then the user's own), the open folder's documents
/// with their reading state, New folder, and Attach from My Files. Nothing is uploaded into a
/// matter: documents come from My Files. A document opens in the document viewer; the user's own
/// documents and folders can be renamed and deleted, the standard folders cannot. While anything
/// is being read the list follows it, and stops when the section leaves the screen.
struct MatterFilesSection: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session

    let workspace: MatterWorkspaceViewModel

    @State private var model: MatterFilesViewModel?
    @State private var isAttaching = false
    @State private var isNamingFolder = false
    @State private var newFolderName = ""
    @State private var renaming: MatterFile?
    @State private var renamingFolder: MatterFolder?
    @State private var renameText = ""
    @State private var deleting: MatterFile?
    @State private var deletingFolder: MatterFolder?
    @State private var previewing: MatterFile?
    /// Bumped after an attach: the listing is fetched again and its reading followed, by a task
    /// that ends when the section leaves the screen.
    @State private var pollGeneration = 0

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task(id: pollGeneration) {
            if model == nil {
                model = MatterFilesViewModel(
                    projectID: workspace.projectID, service: session.matterFiles, files: session.fileManagement)
            }
            guard let model else { return }
            await model.load()
            // Cancelled with the section: the poll stops when it leaves the screen.
            await model.followReading()
        }
    }

    @ViewBuilder
    private func content(_ model: MatterFilesViewModel) -> some View {
        @Bindable var bindable = model
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Documents come into a matter from My Files. These stay inside this matter, and only its conversations read them.",
                  systemImage: "lock")
                .font(.brand(.caption))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.sm) {
                Button {
                    isAttaching = true
                } label: {
                    Label("Attach from My Files", systemImage: "paperclip")
                }
                .buttonStyle(.compactSecondaryAction)
                .accessibilityIdentifier("matter-attach")
                Button {
                    newFolderName = ""
                    isNamingFolder = true
                } label: {
                    Label("New folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.quietAction)
                .disabled(model.state != .loaded)
                .accessibilityIdentifier("matter-new-folder")
            }

            if let failure = model.state.failure {
                LoadFailureView(failure: failure, retry: { await model.load() })
                    .frame(minHeight: 200)
            } else if model.state == .loading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                if let refresh = model.refreshError {
                    Label(refresh, systemImage: "exclamationmark.triangle")
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                folderChips(model)
                fileList(model)
            }
        }
        .recordToast($bindable.message)
        .sheet(isPresented: $isAttaching) {
            let openSub: String? = (model.openFolder?.sub).flatMap { $0.isEmpty ? nil : $0 }
            let target: String = openSub ?? MatterFilesService.standardFolders[0]
            AttachFromMyFilesSheet(
                projectID: model.projectID, destinations: model.destinations,
                destination: target
            ) { summary in
                model.message = summary
                pollGeneration += 1
                Task { await workspace.reload() }
            }
        }
        .sheet(item: $previewing) { file in
            SourceDocumentView(
                attachment: file.attachment,
                mention: AnnexureMention(fileName: file.name, mark: "", startPage: nil, endPage: nil),
                isCitation: false)
        }
        .alert("New folder", isPresented: $isNamingFolder) {
            TextField("e.g. Written statement", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newFolderName
                Task { await model.createFolder(name) }
            }
        } message: {
            Text("Inside this matter. Use / for a folder within a folder.")
        }
        .alert("Rename", isPresented: Binding(
            get: { renaming != nil || renamingFolder != nil },
            set: { if !$0 { renaming = nil; renamingFolder = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { rename(model) }
        } message: {
            Text(renaming != nil ? "The file keeps its type, whatever the new name ends in." : "")
        }
        .confirmationDialog(
            MatterFilesViewModel.deleteFileTitle,
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible, presenting: deleting
        ) { file in
            Button("Delete", role: .destructive) {
                Task { await model.delete(file) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(MatterFilesViewModel.deleteFileMessage)
        }
        .confirmationDialog(
            MatterFilesViewModel.deleteFolderTitle,
            isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } }),
            titleVisibility: .visible, presenting: deletingFolder
        ) { folder in
            Button("Delete", role: .destructive) {
                Task { await model.deleteFolder(folder) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { folder in
            Text(MatterFilesViewModel.deleteFolderMessage(count: folder.count))
        }
        .alert("That did not go through", isPresented: Binding(
            get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }

    // MARK: - Folders

    private func folderChips(_ model: MatterFilesViewModel) -> some View {
        let open = model.openFolder?.sub
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(model.folders) { folder in
                    folderChip(folder, model: model, isSelected: folder.sub == open)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("matter-folders")
    }

    private func folderChip(_ folder: MatterFolder, model: MatterFilesViewModel, isSelected: Bool) -> some View {
        let count: Int? = folder.count > 0 ? folder.count : nil
        let unit: String = folder.count == 1 ? "document" : "documents"
        let spoken: String = "\(folder.name), \(folder.count) \(unit)"
        return Button {
            model.current = folder.sub
        } label: {
            ChipLabel(title: folder.name, systemImage: "folder", count: count, isSelected: isSelected)
        }
        .buttonStyle(ChipButtonStyle(isSelected: isSelected))
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("matter-folder-\(folder.id)")
        .contextMenu {
            if model.canRename(folder) {
                Button {
                    renameText = folder.name
                    renamingFolder = folder
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
            }
            if model.canDelete(folder) {
                Button(role: .destructive) {
                    deletingFolder = folder
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Files

    @ViewBuilder
    private func fileList(_ model: MatterFilesViewModel) -> some View {
        let files = model.openFiles
        let folderName = model.openFolder?.name ?? ""
        if files.isEmpty {
            EmptyStateContent(
                title: "Nothing in \(folderName) yet", systemImage: "folder",
                message: "Attach documents from My Files; each is copied here with what My Files has already read from it.",
                tone: .neutral) {}
        } else {
            RecordGroup {
                ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                    if index > 0 { RecordDivider() }
                    fileRow(file, model: model)
                }
            }
        }
    }

    private func fileRow(_ file: MatterFile, model: MatterFilesViewModel) -> some View {
        let openSub = model.openFolder?.sub ?? ""
        let deeper = file.sub != openSub && !file.sub.isEmpty
        let where_: String? = deeper ? MatterFilesViewModel.folderLabel(file.sub) : nil
        return HStack(spacing: 0) {
            Button {
                previewing = file
            } label: {
                HStack(spacing: Spacing.md) {
                    IconTile(systemImage: Self.symbol(file.name))
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(DisplayText.fileName(file.name))
                            .font(.brand(.body, weight: .medium))
                            .foregroundStyle(theme.textPrimary)
                            .dynamicLineLimit(2)
                        if let where_ {
                            Text(where_)
                                .font(.brand(.footnote))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let status = file.statusText {
                        StatusPill(text: status, tone: file.isFailed ? .danger : .warning)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: Layout.listRow)
                .contentShape(Rectangle())
            }
            .buttonStyle(.recordRow)
            .accessibilityHint("Opens the document")
            .accessibilityIdentifier("matter-file-\(file.name)")

            Menu {
                Button {
                    previewing = file
                } label: {
                    Label("Open", systemImage: "doc.text.magnifyingglass")
                }
                Button {
                    renameText = file.name
                    renaming = file
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deleting = file
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .frame(minWidth: Layout.touchTarget, minHeight: Layout.touchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(file.name)")
            .accessibilityIdentifier("matter-file-menu-\(file.name)")
            .padding(.trailing, Spacing.xs)
        }
    }

    private func rename(_ model: MatterFilesViewModel) {
        let text = renameText
        if let file = renaming {
            Task { await model.rename(file, to: text) }
        } else if let folder = renamingFolder {
            Task { await model.renameFolder(folder, to: text) }
        }
        renaming = nil
        renamingFolder = nil
    }

    static func symbol(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.hasSuffix(".pdf") { return "doc.richtext" }
        if lower.hasSuffix(".doc") || lower.hasSuffix(".docx") { return "doc.text" }
        if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "photo" }
        return "doc"
    }
}
