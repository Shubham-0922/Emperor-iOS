import SwiftUI

/// Step 1: the saved draft to assemble — searched by title, or the one chosen with a way back.
struct FilingDraftPicker: View {
    @Environment(\.theme) private var theme

    let model: FilingAssemblyViewModel

    var body: some View {
        Section {
            if let draft = model.draft {
                RecordRow(
                    title: draft.displayTitle, subtitle: detail(for: draft),
                    leading: { IconTile(systemImage: "doc.text") },
                    trailing: { EmptyView() })
                    .listRowInsets(EdgeInsets())
            } else if model.drafts.isEmpty, model.draftsState == .idle || model.draftsState.isLoading {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                    Text("Loading drafts…")
                        .font(.brand(.subheadline))
                        .foregroundStyle(theme.textSecondary)
                }
            } else if model.drafts.isEmpty, let failure = model.draftsState.failure {
                failureRow(failure)
            } else if model.drafts.isEmpty {
                Text(FilingAssemblyViewModel.noDrafts)
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("filing-no-drafts")
            } else {
                RecordSearchField(
                    text: Binding(get: { model.draftQuery }, set: { model.draftQuery = $0 }),
                    prompt: "Search drafts by title…")
                    .accessibilityIdentifier("filing-draft-search")
                if model.filteredDrafts.isEmpty {
                    Text("No drafts match “\(model.draftQuery)”.")
                        .font(.brand(.subheadline))
                        .foregroundStyle(theme.textSecondary)
                }
                ForEach(model.filteredDrafts) { draft in
                    Button {
                        Task { await model.pick(draft) }
                    } label: {
                        RecordRow(
                            title: draft.displayTitle,
                            subtitle: draft.createdAt.map(FileBrowser.shortDate),
                            leading: { IconTile(systemImage: "doc.text") },
                            trailing: {
                                if let type = draft.type, !type.isEmpty {
                                    StatusPill(text: type, tone: .neutral)
                                }
                            })
                    }
                    .buttonStyle(.recordRow)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("filing-draft-\(draft.id)")
                }
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "1 · Choose a draft")
                Spacer(minLength: Spacing.sm)
                if model.draft != nil {
                    Button("Change draft") { model.changeDraft() }
                        .font(.brand(.footnote, weight: .semibold))
                        .foregroundStyle(theme.accentText)
                        .textCase(nil)
                        .accessibilityIdentifier("filing-change-draft")
                }
            }
        } footer: {
            Text("Saved documents from your Library / Live Drafts")
        }
    }

    private func detail(for draft: FilingDraft) -> String? {
        let parts = [draft.type, draft.createdAt.map(FileBrowser.shortDate)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func failureRow(_ failure: LoadFailure) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(failure.message)
                .font(.brand(.subheadline))
                .foregroundStyle(theme.warning)
                .fixedSize(horizontal: false, vertical: true)
            if failure.isRetryable {
                Button("Retry") { Task { await model.loadDrafts() } }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}
