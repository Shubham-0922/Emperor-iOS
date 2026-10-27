import SwiftUI

/// "Add to Matters" — the web's `AddToMattersDialog`, the last step of a court lookup: what to
/// call the matter, which side the user acts for (in the case's own words, with each side's lead
/// party), and plainly what adding does. The case is tracked, its matter made — or the existing
/// one found — and the side recorded; then the matter opens.
struct AddToMattersSheet: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.navigator) private var navigator
    @Environment(\.dismiss) private var dismiss

    /// The case and what the sheet starts with: its title as the name, no side yet.
    let request: AddToMattersRequest
    /// The matter made or found, with the words to say about it (`MatterCreated.toast`).
    let onDone: (MatterCreated) -> Void

    @State private var model: AddToMattersViewModel?

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
            model = AddToMattersViewModel(request: request, service: session.matterCreation)
        }
    }

    private func form(_ model: AddToMattersViewModel) -> some View {
        @Bindable var model = model
        return MatterFormSheet(
            title: "Add to Matters", actionTitle: model.actionTitle, actionID: "add-to-matters-add",
            isSaving: model.isAdding, error: model.error, actionDisabled: !model.canAdd,
            onCancel: { dismiss() },
            onAction: { add(model) }
        ) {
            Section {
                MatterField(label: "Matter name") {
                    TextField("Matter name", text: $model.request.name)
                        .accessibilityIdentifier("add-to-matters-name")
                }
            }
            .listRowBackground(theme.surface)

            Section {
                ForEach(SideChoice.allCases, id: \.self) { side in
                    sideOption(side, model: model)
                }
            } header: {
                Text("Which side are you on?")
            }
            .listRowBackground(theme.surface)

            Section {
                ForEach(AddToMattersViewModel.explainer, id: \.self) { line in
                    Label(line, systemImage: Self.symbol(for: line))
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .listRowBackground(theme.surface)
        }
    }

    private func sideOption(_ side: SideChoice, model: AddToMattersViewModel) -> some View {
        let isOn = model.request.side == side
        let title = model.optionTitle(side)
        let detail = model.optionDetail(side)
        let symbol = isOn ? "largecircle.fill.circle" : "circle"
        return Button {
            model.request.side = side
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: symbol)
                    .foregroundStyle(theme.accentText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(.brand(.body, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(.brand(.caption))
                            .foregroundStyle(theme.textTertiary)
                            .dynamicLineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isAdding)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("add-to-matters-side-\(side.rawValue)")
    }

    private static func symbol(for line: String) -> String {
        if line.hasPrefix("We check") { return "hourglass" }
        if line.hasPrefix("You get") { return "bell" }
        return "checklist"
    }

    private func add(_ model: AddToMattersViewModel) {
        Task {
            guard let made = await model.add() else { return }
            onDone(made)
            dismiss()
            navigator.openMatter(made.projectID)
        }
    }
}
