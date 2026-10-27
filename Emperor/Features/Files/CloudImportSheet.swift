import SwiftUI

/// My Files → Add → From Google Drive: the drive's recent files, picked and copied into a folder.
///
/// Everything it decides is `CloudImportModel`'s; this lays it out. When nothing can be listed —
/// no drive set up on the server, or this one not connected — it says so, with the way to
/// Connected services where connecting would help.
struct CloudImportSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// The folder on screen when the sheet opened; `nil` for the top level.
    let destination: String?
    /// Every folder the files could go into.
    let folders: [FolderSummary]
    /// Called once an import has run. The presenter closes the sheet, through the binding that
    /// opened it.
    let onFinished: (CloudImportSummary) -> Void

    @State private var model: CloudImportModel?
    @State private var isShowingServices = false

    var body: some View {
        VStack(spacing: 0) {
            RecordSheetHeader(
                title: model?.title ?? "Import",
                subtitle: CloudCopy.listCap,
                onClose: { dismiss() })
            content
        }
        .background(theme.canvas)
        .safeAreaInset(edge: .bottom) {
            if let model, !model.files.isEmpty, model.blocker == nil {
                importBar(model)
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model?.isImporting ?? false)
        .task {
            guard model == nil else { return }
            let created = CloudImportModel(service: session.cloud, destination: destination)
            model = created
            await created.load()
        }
        .sheet(isPresented: $isShowingServices, onDismiss: reload) {
            CloudServicesSheet()
        }
    }

    private func reload() {
        guard let model else { return }
        Task { await model.load() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let model {
            if let blocker = model.blocker {
                blocked(blocker)
            } else if let failure = model.state.failure {
                LoadFailureView(failure: failure, retry: { await model.list() })
            } else if !model.state.hasLoaded {
                loading
            } else if model.files.isEmpty {
                EmptyStateView(
                    "No importable files", systemImage: "tray", message: CloudCopy.emptyDrive,
                    tone: .neutral)
            } else {
                fileList(model)
            }
        } else {
            loading
        }
    }

    private var loading: some View {
        ProgressView("Listing files…")
            .font(.brand(.subheadline))
            .tint(theme.textSecondary)
            .foregroundStyle(theme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func blocked(_ message: String) -> some View {
        let canConnect: Bool = message != CloudCopy.soon
        return EmptyStateView(
            canConnect ? "Connect a drive first" : "Not available yet",
            systemImage: "icloud.slash", message: message, tone: .neutral
        ) {
            if canConnect {
                Button("Open Connected services") {
                    isShowingServices = true
                }
                .buttonStyle(.primaryAction)
                .accessibilityIdentifier("cloud-open-account")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cloud-import-blocked")
    }

    private func fileList(_ model: CloudImportModel) -> some View {
        List {
            Section {
                if model.showsProviderPicker {
                    providerPicker(model)
                }
                destinationPicker(model)
                RecordSearchField(text: queryBinding(model), prompt: "Filter by name")
                    .listRowInsets(EdgeInsets(top: Spacing.sm, leading: Spacing.md, bottom: Spacing.sm, trailing: Spacing.md))
            }
            .listRowBackground(theme.surface)

            Section {
                ForEach(model.visibleFiles) { file in
                    fileRow(file, model: model)
                }
            } header: {
                SectionHeader(title: "Files", detail: selectionDetail(model))
            }
            .listRowBackground(theme.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .disabled(model.isImporting)
    }

    private func selectionDetail(_ model: CloudImportModel) -> String? {
        let count: Int = model.selection.count
        return count == 0 ? nil : "\(count) chosen"
    }

    private func providerPicker(_ model: CloudImportModel) -> some View {
        let options: [(value: CloudProvider, title: String)] = model.connectedProviders.map {
            (value: $0, title: $0.label)
        }
        let selection = Binding<CloudProvider>(
            get: { model.provider },
            set: { chosen in Task { await model.choose(chosen) } })
        return RecordSegmentedControl(label: "Drive", options: options, selection: selection)
            .listRowInsets(EdgeInsets(top: Spacing.sm, leading: Spacing.md, bottom: Spacing.sm, trailing: Spacing.md))
            .accessibilityIdentifier("cloud-import-provider")
    }

    private func destinationPicker(_ model: CloudImportModel) -> some View {
        let selection = Binding<String>(
            get: { model.destination ?? "" },
            set: { model.destination = $0.isEmpty ? nil : $0 })
        return Picker(selection: selection) {
            Text("Files root (top level)").tag("")
            ForEach(folders) { folder in
                Text(folder.breadcrumb).tag(folder.path)
            }
        } label: {
            Text("Save into")
                .font(.brand(.body))
                .foregroundStyle(theme.textPrimary)
        }
        .pickerStyle(.menu)
        .tint(theme.accentText)
        .accessibilityIdentifier("cloud-import-destination")
    }

    private func queryBinding(_ model: CloudImportModel) -> Binding<String> {
        Binding(get: { model.query }, set: { model.query = $0 })
    }

    private func fileRow(_ file: CloudFile, model: CloudImportModel) -> some View {
        let isChosen: Bool = model.selection.contains(file.id)
        return Button {
            Haptics.selection()
            model.toggle(file)
        } label: {
            HStack(spacing: Spacing.md) {
                IconTile(systemImage: "doc", hue: .indigo, size: .small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.brand(.body, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .dynamicLineLimit(2)
                    if let detail = file.detailLine {
                        Text(detail)
                            .font(.brand(.footnote))
                            .monospacedDigit()
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .font(.brand(.title3))
                    .foregroundStyle(isChosen ? theme.accentText : theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
        .accessibilityIdentifier("cloud-file-\(file.id)")
    }

    private func importBar(_ model: CloudImportModel) -> some View {
        Button {
            Task {
                let summary = await model.run()
                onFinished(summary)
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                if model.isImporting {
                    ProgressView()
                        .tint(theme.onAccent)
                }
                Text(model.importTitle)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.primaryAction)
        .disabled(!model.canImport)
        .accessibilityIdentifier("cloud-import-run")
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.sm)
        .background(theme.groupedBackground)
    }
}

/// Connected services on their own, for the import sheet's "Open Connected services".
struct CloudServicesSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                CloudConnectionsSection()
            }
            .font(.brand(.body))
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.groupedBackground)
            .navigationTitle("Connected services")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
