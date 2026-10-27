import SwiftUI

/// A conversation of a matter, pushed on the Matters stack.
struct MatterChatRoute: Hashable {
    let projectID: String
    let chatID: String
}

/// The workspace's Ask Emperor — the web's `AskSection`: the matter's own conversations, newest
/// first, and a new one. A conversation opens as a full thread on the Matters stack, pinned to the
/// matter: every turn carries the matter, a new one starts with the matter's readable files, and
/// the documents button picks from the matter's files only. None of them is listed in History.
/// Coming back from one reloads the matter, so a new conversation joins the list.
struct MatterAskSection: View {
    @Environment(\.theme) private var theme

    let model: MatterWorkspaceViewModel

    /// Set when a conversation is opened, so coming back reloads the matter.
    @State private var hasAppeared = false

    var body: some View {
        let chats = MatterChatsViewModel(chats: model.detail?.chats ?? [])
        let rows = chats.rows
        VStack(alignment: .leading, spacing: Spacing.md) {
            NavigationLink(value: MattersRoute.matterChat(
                MatterChatRoute(projectID: model.projectID, chatID: MatterChatsViewModel.newChatID()))) {
                Label("New conversation", systemImage: "plus.bubble")
            }
            .buttonStyle(.compactSecondaryAction)
            .accessibilityIdentifier("matter-chat-new")

            if rows.isEmpty {
                EmptyStateContent(
                    title: "No conversations yet", systemImage: "bubble.left.and.text.bubble.right",
                    message: "Ask about this matter: Emperor reads its files and knows its dates, tasks and parties.",
                    tone: .neutral) {}
            } else {
                RecordGroup {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { RecordDivider() }
                        conversationRow(row)
                    }
                }
            }

            Label(MatterChatsViewModel.footnote, systemImage: "lock")
                .font(.brand(.caption))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("matter-section-ask-body")
        .onAppear {
            guard hasAppeared else { hasAppeared = true; return }
            Task { await model.reload() }
        }
    }

    private func conversationRow(_ row: MatterChatsViewModel.Row) -> some View {
        let route = MatterChatRoute(projectID: model.projectID, chatID: row.id)
        return NavigationLink(value: MattersRoute.matterChat(route)) {
            RecordRow(title: row.title, subtitle: row.when.isEmpty ? nil : row.when) {
                IconTile(systemImage: "bubble.left.and.text.bubble.right")
            }
        }
        .buttonStyle(.recordRow)
        .accessibilityIdentifier("matter-chat-\(row.id)")
    }
}

/// What a matter's new conversation opens on: what it is for, and four questions to start with.
struct MatterChatIntro: View {
    @Environment(\.theme) private var theme

    let onAsk: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(MatterChatsViewModel.introTitle)
                    .font(.display(size: 26, relativeTo: .title2))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(MatterChatsViewModel.introDetail)
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(MatterChatsViewModel.suggestions, id: \.self) { question in
                    Button {
                        onAsk(question)
                    } label: {
                        Text(question)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: false))
                    .accessibilityHint("Asks this about the matter")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.md)
        .accessibilityIdentifier("matter-chat-intro")
    }
}
