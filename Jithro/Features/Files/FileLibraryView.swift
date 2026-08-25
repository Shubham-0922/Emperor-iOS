import SwiftUI

/// Picks documents from the DMS to attach to a turn.
///
/// Presented as a sheet from the composer rather than as a tab: on a phone, attaching a file
/// is nearly always something you do *while* asking a question, not a separate errand.
struct FileLibraryView: View {
    /// Files already attached, so they can be shown as selected and toggled off.
    let alreadyAttached: [ChatAttachment]
    let onAttach: ([ChatAttachment]) -> Void

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var files: [FileNode.StoredFile] = []
    @State private var selected: Set<String> = []
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var visible: [FileNode.StoredFile] {
        FileService.search(query, in: files)
    }

    /// Grouped by matter, because that is how a practitioner thinks about a file — not as a
    /// flat list of names.
    private var grouped: [(folder: String, files: [FileNode.StoredFile])] {
        Dictionary(grouping: visible, by: \.folderPath)
            .map { (folder: $0.key, files: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.folder.localizedStandardCompare($1.folder) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && files.isEmpty {
                    ProgressView()
                } else if files.isEmpty {
                    ContentUnavailableView(
                        "No documents yet",
                        systemImage: "folder",
                        description: Text("Scan a paperbook to add your first document."))
                } else if visible.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    list
                }
            }
            .navigationTitle("Documents")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search documents and matters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Attach") {
                        onAttach(attachments(for: selected))
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .alert("Could not load documents", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var list: some View {
        List {
            ForEach(grouped, id: \.folder) { group in
                Section(group.folder.isEmpty ? "Unfiled" : group.folder.replacingOccurrences(of: "_", with: " ")) {
                    ForEach(group.files, id: \.path) { file in
                        row(for: file)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(for file: FileNode.StoredFile) -> some View {
        Button {
            toggle(file)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected.contains(file.path) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(file.path) ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name.replacingOccurrences(of: "_", with: " "))
                        .lineLimit(2)
                        .foregroundStyle(file.isReadable ? .primary : .secondary)
                    statusLine(for: file)
                }

                Spacer(minLength: 0)

                if file.favorite == true {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A file still being read cannot answer questions yet, so it cannot be attached.
        .disabled(!file.isReadable)
    }

    @ViewBuilder
    private func statusLine(for file: FileNode.StoredFile) -> some View {
        switch file.state {
        case .ready:
            if let size = file.size {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        case .scanned:
            // Worth saying plainly: this is usable, just by a different route.
            Label("Scanned — read as images", systemImage: "eye")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .inProgress(let message):
            Label(message, systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .failed(let reason):
            Label(
                reason.replacingOccurrences(of: "ERROR: ", with: ""),
                systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private func toggle(_ file: FileNode.StoredFile) {
        if selected.contains(file.path) {
            selected.remove(file.path)
        } else {
            selected.insert(file.path)
        }
    }

    private func attachments(for paths: Set<String>) -> [ChatAttachment] {
        files.filter { paths.contains($0.path) }.map(\.attachment)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let tree = try await session.files.tree()
            files = FileService.allFiles(in: tree)
            // Reflect what the turn already carries, so the sheet is a true picture of state.
            let attachedPaths = Set(alreadyAttached.map { attachment -> String in
                let folder = attachment.folderName ?? ""
                return folder.isEmpty ? attachment.name : "\(folder)/\(attachment.name)"
            })
            selected = Set(files.map(\.path).filter { attachedPaths.contains($0) })
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
