import SwiftUI

/// The workspace's Drafts — the web's `DraftsSection`: the documents and tables this matter's
/// conversations produced, newest first, each opened in the draft reader, whose export menu
/// downloads the Word copy. They are not in the Library.
struct MatterDraftsSection: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session

    let workspace: MatterWorkspaceViewModel

    @State private var model: MatterDraftListViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task {
            if model == nil {
                model = MatterDraftListViewModel(projectID: workspace.projectID, service: session.drafts)
            }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(_ model: MatterDraftListViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Drafts from this matter’s conversations stay with the matter. They are not in the Library.",
                  systemImage: "lock")
                .font(.brand(.caption))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let failure = model.state.failure {
                LoadFailureView(failure: failure, retry: { await model.load() })
                    .frame(minHeight: 200)
            } else if model.state == .loading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if model.items.isEmpty {
                EmptyStateContent(
                    title: "No drafts yet", systemImage: "doc.text",
                    message: "What Emperor drafts in this matter’s conversations is kept here.",
                    tone: .neutral) {}
            } else {
                if let partial = model.partial {
                    Label(partial, systemImage: "exclamationmark.triangle")
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.warning)
                }
                RecordGroup {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { RecordDivider() }
                        draftRow(item, model: model)
                    }
                }
            }
        }
        .fullScreenCover(item: Binding(
            get: { model.opened },
            set: { model.opened = $0 }
        )) { opened in
            DraftReaderView(draft: opened)
        }
        .alert("Couldn't open that", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func draftRow(_ item: DraftedItem, model: MatterDraftListViewModel) -> some View {
        let table = model.isTable(item)
        let day = item.createdAt.map { MatterRecord.fmtDay(WireDate.dayKey($0)) }
        let kindWord: String = table ? "Table" : "Document"
        let parts: [String?] = [kindWord, day]
        let subtitle: String = parts.compactMap { $0 }.joined(separator: " · ")
        return Button {
            Task { await model.open(item) }
        } label: {
            RecordRow(title: item.displayTitle, subtitle: subtitle, subtitleColor: nil, titleLines: 2) {
                IconTile(systemImage: table ? "tablecells" : "doc.text")
            } trailing: {
                if model.loadingID == item.id {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .buttonStyle(.recordRow)
        .accessibilityHint("Opens the draft")
        .accessibilityIdentifier("matter-draft-\(item.id)")
    }
}
