import SwiftUI

/// "Build from documents" — the web's `BuildFlow`: which documents to read (all, or the ones
/// picked), the read itself, then the proposed events to review — each with where it was found,
/// a date that can be corrected, and a tick — and Save. Nothing is added until it is ticked; an
/// event that looks like one already on the record starts unticked.
struct ChronologyExtractSheet: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let projectID: String
    let existing: [MatterRecord.Entry]
    /// After a save that added something: what to say.
    let onSaved: (String) -> Void

    @State private var model: ChronologyExtractViewModel?

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
            .navigationTitle("Build from documents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { close() }
                        .disabled(model?.phase == .saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    primaryAction
                }
            }
        }
        .interactiveDismissDisabled(model?.phase == .saving || model?.phase == .reading)
        .task {
            guard model == nil else { return }
            model = ChronologyExtractViewModel(
                projectID: projectID, service: session.matterFiles, writes: session.projectWrites, existing: existing)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if let model {
            switch model.phase {
            case .pick:
                Button("Read documents") { Task { await model.start() } }
                    .disabled(!model.canStart)
                    .accessibilityIdentifier("chronology-build-read")
            case .review, .saving:
                if !model.proposals.isEmpty {
                    Button(model.saveTitle) { save(model) }
                        .disabled(model.picked.isEmpty || model.phase == .saving)
                        .accessibilityIdentifier("chronology-build-save")
                }
            case .reading, .failed:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: ChronologyExtractViewModel) -> some View {
        switch model.phase {
        case .pick: pick(model)
        case .reading: reading(model)
        case .failed: failed(model)
        case .review, .saving: review(model)
        }
    }

    // MARK: - Choosing

    private func pick(_ model: ChronologyExtractViewModel) -> some View {
        List {
            Section {
                Text(ChronologyExtractViewModel.intro)
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(theme.surface)
            Section {
                scopeRow(model, .all, title: "All documents in this matter",
                         detail: "Every processed file in the matter’s own storage.")
                scopeRow(model, .some, title: "Choose documents", detail: "Read only the files you pick.")
            } header: {
                Text("Which documents")
            }
            .listRowBackground(theme.surface)
            if model.scope == .some {
                chosenFiles(model)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("chronology-build-sheet")
    }

    private func scopeRow(_ model: ChronologyExtractViewModel, _ scope: ChronologyExtractViewModel.Scope,
                          title: String, detail: String) -> some View {
        let isOn = model.scope == scope
        let symbol = isOn ? "largecircle.fill.circle" : "circle"
        return Button {
            if scope == .all {
                model.chooseAll()
            } else {
                Task { await model.chooseSome() }
            }
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: symbol)
                    .foregroundStyle(theme.accentText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(.brand(.body, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(detail)
                        .font(.brand(.caption))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder
    private func chosenFiles(_ model: ChronologyExtractViewModel) -> some View {
        Section {
            if let files = model.files {
                if files.isEmpty {
                    Text(model.filesError ?? "This matter has no files yet. Attach them from My Files in Files first.")
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(files) { file in
                        fileRow(file, model: model)
                    }
                }
            } else {
                ProgressView()
            }
        } header: {
            Text("Documents")
        }
        .listRowBackground(theme.surface)
    }

    private func fileRow(_ file: MatterFile, model: ChronologyExtractViewModel) -> some View {
        let isOn = model.chosen.contains(file.id)
        let symbol = isOn ? "checkmark.circle.fill" : "circle"
        let note: String? = file.isReady ? nil : (file.isFailed ? "could not be read" : "still processing")
        let place: String? = file.sub.isEmpty ? nil : MatterFilesViewModel.folderLabel(file.sub)
        let parts: [String?] = [place, note]
        let line = parts.compactMap { $0 }.joined(separator: " · ")
        return Button {
            model.toggleFile(file)
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: symbol)
                    .foregroundStyle(file.isReady ? theme.accentText : theme.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(DisplayText.fileName(file.name))
                        .font(.brand(.body))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !line.isEmpty {
                        Text(line)
                            .font(.brand(.caption))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!file.isReady)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Reading

    private func reading(_ model: ChronologyExtractViewModel) -> some View {
        let count = model.chosen.count
        let unit: String = count == 1 ? "file" : "files"
        let some: String = "\(count) \(unit)"
        let what: String = model.scope == .some ? some : "all files"
        return VStack(spacing: Spacing.lg) {
            ProgressView()
                .controlSize(.large)
            Text("Reading the documents — \(what)")
                .font(.brand(.headline))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("Finding dated events and where each one is written…")
                .font(.brand(.subheadline))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            Text(ChronologyExtractViewModel.readingNote)
                .font(.brand(.footnote))
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chronology-build-reading")
    }

    private func failed(_ model: ChronologyExtractViewModel) -> some View {
        VStack(spacing: Spacing.md) {
            EmptyStateContent(
                title: "Couldn’t build the chronology", systemImage: "exclamationmark.triangle",
                message: model.error, tone: .neutral) {
                Button("Back") { model.back() }
                    .buttonStyle(.secondaryAction)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Reviewing

    private func review(_ model: ChronologyExtractViewModel) -> some View {
        @Bindable var bindable = model
        let saving = model.phase == .saving
        return List {
            if model.partial {
                Section {
                    Label("Some of the documents could not be read in full, so this list may be incomplete.",
                          systemImage: "exclamationmark.triangle")
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(theme.surface)
            }
            if let result = model.result {
                Section {
                    Label(result, systemImage: model.resultIsFailure ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.brand(.footnote))
                        .foregroundStyle(model.resultIsFailure ? theme.danger : theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(theme.surface)
            }
            if model.proposals.isEmpty {
                Section {
                    Text(model.message ?? model.emptyMessage)
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(theme.surface)
            } else {
                Section {
                    ForEach($bindable.proposals) { $proposal in
                        ProposalRow(proposal: $proposal, disabled: saving) {
                            model.toggle(proposal.id)
                        }
                    }
                } header: {
                    HStack {
                        Text("\(model.proposals.count) found · \(model.picked.count) ticked")
                        Spacer()
                        Button("Tick all") { model.tickAll() }
                            .disabled(saving)
                        Button("Untick all") { model.untickAll() }
                            .disabled(saving)
                    }
                }
                .listRowBackground(theme.surface)
            }
            if saving {
                Section {
                    ProgressView(value: Double(model.progress.done), total: Double(max(model.progress.total, 1)))
                    Text("Adding \(model.progress.done) of \(model.progress.total)…")
                        .font(.brand(.caption))
                        .foregroundStyle(theme.textSecondary)
                }
                .listRowBackground(theme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("chronology-build-review")
    }

    private func save(_ model: ChronologyExtractViewModel) {
        Task {
            let added = await model.accept()
            if let result = model.result, added || model.resultIsFailure {
                onSaved(result)
            }
            if added, !model.resultIsFailure { dismiss() }
        }
    }

    private func close() {
        model?.abandon()
        dismiss()
    }
}

/// One proposed event: the tick, its date (correctable — an undated one waits for a date), the
/// title, what it says and where it was found.
private struct ProposalRow: View {
    @Environment(\.theme) private var theme

    @Binding var proposal: ChronologyExtractViewModel.Proposal
    let disabled: Bool
    let onToggle: () -> Void

    var body: some View {
        let usable = proposal.usable
        let ticked = proposal.on && usable
        let symbol = ticked ? "checkmark.square.fill" : "square"
        let kind = MatterRecord.kindLabel(proposal.kind)
        let named: String = proposal.title.isEmpty ? "this event" : proposal.title
        let spoken: String = "Add “" + named + "”"
        let readAs: String = "Date (read as “" + proposal.rawDate + "”)"
        let dateLabel: String = proposal.undated ? readAs : "Date"
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Button(action: onToggle) {
                    Image(systemName: symbol)
                        .font(.system(size: 20))
                        .foregroundStyle(usable ? theme.accentText : theme.textTertiary)
                        .frame(minWidth: Layout.touchTarget, minHeight: Layout.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled || !usable)
                .accessibilityLabel(spoken)
                .accessibilityAddTraits(ticked ? .isSelected : [])
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(proposal.title.isEmpty ? "Untitled event" : proposal.title)
                        .font(.brand(.body, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Spacing.xs) {
                        StatusPill(text: kind)
                        if proposal.dup {
                            StatusPill(text: "Already on the record", tone: .warning)
                        }
                    }
                }
            }
            MatterDayField(label: dateLabel, day: $proposal.day, allowsClear: false)
                .disabled(disabled)
            if !proposal.details.isEmpty {
                Text(proposal.details)
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !proposal.sourceRef.isEmpty {
                Label("Found in \(proposal.sourceRef)", systemImage: "doc.text.magnifyingglass")
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chronology-proposal-\(proposal.id)")
    }
}
