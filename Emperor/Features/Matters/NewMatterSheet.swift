import SwiftUI

/// New matter — as quick as adding a case (the web's `NewMatterDialog`): a name, a banner, a
/// folder colour, then the court case: Find the case (the court lookup in pick mode), Not filed
/// yet, or Add later. A found case is tracked and the matter is made from it; the server names it
/// after the cause title when the name is left blank. `NewMatterViewModel` holds every rule.
struct NewMatterSheet: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// The user's matters, for the least-used banner.
    let existing: [Project]
    /// The new (or existing) matter's id, and whether it already existed.
    let onCreated: (_ projectID: String, _ existed: Bool) -> Void

    @State private var model: NewMatterViewModel?
    @State private var isSearching = false

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
            model = NewMatterViewModel(
                writes: session.projectWrites, tracking: session.caseTracking, existing: existing)
        }
    }

    private func form(_ model: NewMatterViewModel) -> some View {
        @Bindable var model = model
        return MatterFormSheet(
            title: "New matter", actionTitle: "Create", actionID: "new-matter-create",
            isSaving: model.isSaving, busy: model.busy, error: model.error,
            onCancel: { dismiss() },
            onAction: { create(model) }
        ) {
            Section {
                TextField(model.namePlaceholder, text: $model.name, axis: .vertical)
                    .lineLimit(1...3)
                    .submitLabel(.done)
                    .accessibilityLabel("Matter name")
                    .accessibilityIdentifier("new-matter-name")
            } header: {
                Text("Matter name")
            } footer: {
                if !model.titleFromCase.isEmpty, model.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Left blank, the matter is named after the cause title.")
                }
            }
            .listRowBackground(theme.surface)

            Section {
                preview(model)
                    .listRowInsets(EdgeInsets(top: Spacing.sm, leading: Spacing.md, bottom: Spacing.sm, trailing: Spacing.md))
                MatterField(label: "Banner") {
                    BannerPicker(selected: model.banner) { model.banner = $0 }
                }
                MatterField(label: "Folder colour") {
                    ColourSwatches(selected: model.color) { model.color = $0 }
                }
            } header: {
                Text("How it looks")
            }
            .listRowBackground(theme.surface)

            Section {
                RecordSegmentedControl(
                    label: "Court case",
                    options: NewMatterViewModel.Court.allCases.map { (value: $0, title: $0.label) },
                    selection: $model.court)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                if model.court == .find {
                    findRow(model)
                }
            } header: {
                Text("Court case")
            } footer: {
                Text(courtFooter(model.court))
            }
            .listRowBackground(theme.surface)
        }
        .sheet(isPresented: $isSearching) {
            CourtSearchView(onSaved: {}, onPick: { result in
                model.choose(result)
                isSearching = false
            })
            .pageSizedSheet()
        }
    }

    private func preview(_ model: NewMatterViewModel) -> some View {
        MatterBannerView(preset: model.banner, cornerRadius: Radius.control) {
            LinearGradient(colors: [Color(MatterBanner.plate), Color.clear], startPoint: .leading, endPoint: .trailing)
        }
        .frame(height: 74)
        .overlay(alignment: .bottomLeading) {
            Text(model.shownName)
                .font(.display(size: 17, relativeTo: .headline))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .padding(Spacing.sm)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview: \(model.shownName), \(model.banner.label) banner")
    }

    @ViewBuilder
    private func findRow(_ model: NewMatterViewModel) -> some View {
        if let pick = model.pick {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(pick.displayTitle)
                    .font(.brand(.callout, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                let facts = [pick.reference, pick.courtName].compactMap { $0 }.filter { !$0.isEmpty }
                if !facts.isEmpty {
                    Text(facts.joined(separator: " · "))
                        .font(.brand(.caption))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Change") { isSearching = true }
                    .buttonStyle(.quietAction)
                    .disabled(model.isSaving)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("new-matter-picked")
        } else {
            Button {
                isSearching = true
            } label: {
                Label("Search the court records", systemImage: "magnifyingglass")
            }
            .accessibilityIdentifier("new-matter-find")
        }
    }

    private func courtFooter(_ court: NewMatterViewModel.Court) -> String {
        switch court {
        case .find: return "Found by case or diary number, the case is tracked from the court from then on and the matter is filled in from it."
        case .notFiled: return "There is no case to find yet. Nothing asks for one until it is filed."
        case .later: return "The case exists; you will look it up another time."
        }
    }

    private func create(_ model: NewMatterViewModel) {
        Task {
            guard let made = await model.create() else { return }
            onCreated(made.projectID, made.existed)
            dismiss()
        }
    }
}
