import SwiftUI

/// Filing Assembly: a saved draft, its annexures and a cover page made into one court-ready,
/// paginated bundle — cover, index, list of annexures — by the server.
///
/// The steps follow the web's `/filing` page: choose a draft, arrange its annexures, fill in the
/// cover, assemble. Every rule and sentence lives in `FilingAssemblyViewModel`. One list rather
/// than a scroll view of cards, so the annexures can be dragged into order in place.
struct FilingAssemblyScreen: View {
    static let isReady = true

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session

    @State private var model: FilingAssemblyViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    FilingAssemblyContent(model: model)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(theme.groupedBackground)
            .navigationTitle("Filing Assembly")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                guard model == nil else { return }
                let created = FilingAssemblyViewModel(service: session.filing, files: session.files)
                model = created
                await created.loadDrafts()
            }
        }
    }
}

/// The steps, once the view model exists.
private struct FilingAssemblyContent: View {
    @Environment(\.theme) private var theme

    let model: FilingAssemblyViewModel

    @State private var isAdding = false
    @State private var openBundle: FilingBundle?
    @State private var editMode: EditMode = .inactive
    @State private var renaming: FilingAnnexure?
    @State private var newTitle = ""
    @State private var removing: FilingAnnexure?

    private var renameMessage: String {
        guard let annexure = renaming else { return "" }
        return "The title \(annexure.mark) carries in the Index and List of Annexures."
    }

    var body: some View {
        List {
            Section {
                SerifHeader(title: "Filing Assembly", subtitle: FilingAssemblyViewModel.subtitle)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: Spacing.sm, leading: 0, bottom: 0, trailing: 0))
            }

            if let refusal = model.refusal {
                Section {
                    RefusalCard(refusal: refusal)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            } else {
                FilingDraftPicker(model: model)
                if model.draft != nil {
                    FilingAnnexureSection(
                        model: model, isEditing: editMode.isEditing,
                        onToggleEditing: {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                        },
                        onAdd: { isAdding = true },
                        onRename: { annexure in
                            newTitle = annexure.title
                            renaming = annexure
                        },
                        onRemove: { removing = $0 })
                    FilingCoverSection(model: model)
                    if let outcome = model.outcome {
                        FilingResultView(
                            model: model, result: outcome,
                            onOpen: { openBundle = $0 })
                    } else if let checklist = model.checklist {
                        Section {
                            FilingChecklistList(checklist: checklist)
                        } header: {
                            SectionHeader(title: "Before you can file")
                        } footer: {
                            Text("For the forum on the cover, before assembly.")
                        }
                    }
                    FilingBundlesSection(model: model, onOpen: { openBundle = $0 })
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .accessibilityIdentifier("filing-screen")
        .refreshable {
            if model.draft == nil {
                await model.loadDrafts()
            } else {
                await model.reloadAnnexures()
                await model.refreshBundles()
            }
        }
        .recordToast(Binding(get: { model.toast }, set: { model.toast = $0 }))
        .task(id: model.cover.forum) {
            // Asked once the forum has stopped changing, not on every keystroke.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await model.refreshChecklist()
        }
        .alert(
            "Rename annexure",
            isPresented: Binding(
                get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField("Title", text: $newTitle)
            Button("Save") {
                if let annexure = renaming {
                    let title = newTitle
                    Task { await model.rename(annexure, to: title) }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text(renameMessage)
        }
        .confirmationDialog(
            removing.map(FilingAssemblyViewModel.removePrompt(for:)) ?? "Remove annexure?",
            isPresented: Binding(
                get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let annexure = removing {
                    Task { await model.delete(annexure) }
                }
                removing = nil
            }
            .accessibilityIdentifier("filing-confirm-remove")
            Button("Cancel", role: .cancel) { removing = nil }
        }
        .sheet(isPresented: $isAdding) {
            FilingAddAnnexureSheet(model: model)
        }
        .sheet(item: $openBundle) { bundle in
            FilingBundleViewer(model: model, bundle: bundle)
        }
    }
}
