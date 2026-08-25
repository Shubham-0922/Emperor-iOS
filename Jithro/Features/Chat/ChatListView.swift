import SwiftUI

struct ChatListView: View {
    @Environment(Session.self) private var session

    @State private var chats: [ChatSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var newChatID: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && chats.isEmpty {
                    ProgressView()
                } else if chats.isEmpty {
                    ContentUnavailableView(
                        "No conversations yet",
                        systemImage: "text.document",
                        description: Text("Start one, or bring in a paperbook to ask about."))
                } else {
                    List(chats) { chat in
                        NavigationLink(value: chat.id) {
                            row(for: chat)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Jithro")
            .navigationDestination(for: String.self) { chatID in
                ChatThreadView(chatID: chatID)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newChatID = ChatViewModel.newChatID()
                    } label: {
                        Label("New chat", systemImage: "square.and.pencil")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if let user = session.currentUser {
                            Text(user.email ?? user.name ?? "Signed in")
                        }
                        Button("Sign out", role: .destructive) {
                            Task { await session.signOut() }
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
            .navigationDestination(item: $newChatID) { chatID in
                ChatThreadView(chatID: chatID)
            }
            .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task { await load() }
        }
    }

    private func row(for chat: ChatSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(chat.displayTitle)
                .font(.headline)
                .lineLimit(1)
            if let preview = chat.lastPreview, !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let updated = chat.updatedAt {
                Text(updated, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            chats = try await session.chats.chats()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
