import SwiftUI

/// "Attach from My Files" — the web's `AttachFromMyFiles`: My Files by folder, only documents My
/// Files has finished reading tickable (one still being read says so), at most 25 at a time, the
/// matter folder they go into, and every file the server left out with its reason. Each document
/// is copied into the matter with what My Files already read from it; nothing is uploaded here.
struct AttachFromMyFilesSheet: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let projectID: String
    let destinations: [String]
    let destination: String
    /// After an attach that copied something: the summary, for the matter to say.
    let onAttached: (String) -> Void

    @State private var model: AttachFromMyFilesViewModel?

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
            .navigationTitle("Attach from My Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(model?.isAttaching == true)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model?.attachTitle ?? "Attach documents") { attach() }
                        .disabled(model?.canAttach != true)
                        .accessibilityIdentifier("attach-confirm")
                }
            }
        }
        .interactiveDismissDisabled(model?.isAttaching == true)
        .task {
            guard model == nil else { return }
            let created = AttachFromMyFilesViewModel(
                projectID: projectID, myFiles: session.files, service: session.matterFiles,
                destinations: destinations, destination: destination)
            model = created
            await created.load()
        }
    }

    @ViewBuilder
    private func content(_ model: AttachFromMyFilesViewModel) -> some View {
        @Bindable var bindable = model
        List {
            Section {
                Text(AttachFromMyFilesViewModel.intro)
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Attach to", selection: $bindable.destination) {
                    ForEach(model.destinations, id: \.self) { sub in
                        Text(MatterFilesViewModel.folderLabel(sub)).tag(sub)
                    }
                }
                .accessibilityIdentifier("attach-destination")
            }
            .listRowBackground(theme.surface)

            if !model.outcomes.isEmpty {
                outcomes(model)
            }
            if let notice = model.notice {
                Section {
                    Label(notice, systemImage: "info.circle")
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textSecondary)
                }
                .listRowBackground(theme.surface)
            }
            if let error = model.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("attach-error")
                }
                .listRowBackground(theme.surface)
            }

            documents(model)

            if let note = model.readingNote {
                Section {
                    Label(note, systemImage: "hourglass")
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(theme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .searchable(text: $bindable.query, prompt: "Search My Files")
        .accessibilityIdentifier("attach-sheet")
    }

    @ViewBuilder
    private func documents(_ model: AttachFromMyFilesViewModel) -> some View {
        if let failure = model.state.failure {
            Section {
                Text(failure.message)
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.danger)
                Button("Try again") { Task { await model.load() } }
            }
            .listRowBackground(theme.surface)
        } else if model.state == .loading {
            Section {
                ProgressView("Loading My Files…")
            }
            .listRowBackground(theme.surface)
        } else if model.groups.isEmpty {
            let noMatch: String = "Nothing in My Files matches “" + model.query + "”."
            let said: String = model.query.isEmpty ? AttachFromMyFilesViewModel.emptyMessage : noMatch
            Section {
                Text(said)
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(theme.surface)
        } else {
            ForEach(model.groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        documentRow(row, model: model)
                    }
                } header: {
                    Text(group.title)
                }
                .listRowBackground(theme.surface)
            }
        }
    }

    private func documentRow(_ row: AttachFromMyFilesViewModel.Row, model: AttachFromMyFilesViewModel) -> some View {
        let usable = model.selectable(row)
        let chosen = model.isSelected(row)
        let symbol = chosen ? "checkmark.circle.fill" : "circle"
        return Button {
            model.toggle(row)
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(usable ? theme.accentText : theme.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(DisplayText.fileName(row.file.name))
                        .font(.brand(.body))
                        .foregroundStyle(usable ? theme.textPrimary : theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let why = row.whyNot {
                        Text(why)
                            .font(.brand(.caption))
                            .foregroundStyle(theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!usable)
        .accessibilityLabel(row.file.name)
        .accessibilityValue(chosen ? "Selected" : "")
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("attach-file-\(row.file.name)")
    }

    private func outcomes(_ model: AttachFromMyFilesViewModel) -> some View {
        Section {
            ForEach(Array(model.outcomes.enumerated()), id: \.offset) { _, row in
                outcomeRow(row)
            }
        } header: {
            Text("What happened")
        }
        .listRowBackground(theme.surface)
    }

    private func outcomeRow(_ row: AttachRow) -> some View {
        let skipped = row.isSkipped
        let detail: String = skipped ? (row.reason ?? "Not attached") : "Attached"
        let tint: Color = skipped ? theme.warning : theme.textSecondary
        return VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(row.sourceName)
                .font(.brand(.subheadline, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text(detail)
                .font(.brand(.caption))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("attach-outcome-\(row.sourceName)")
    }

    private func attach() {
        guard let model else { return }
        Task {
            guard let summary = await model.attach() else { return }
            onAttached(summary)
            if model.finished { dismiss() }
        }
    }
}
