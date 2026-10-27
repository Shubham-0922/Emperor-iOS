import Foundation

/// A matter's Ask section — the web's `AskSection.jsx`: the matter's own conversations, newest
/// first, a new one, and the words around them. A conversation here carries the matter's id on
/// every turn (`ChatService.scoped(toProject:)`), reads only the matter's files, and is not
/// listed in History.
struct MatterChatsViewModel: Equatable, Sendable {

    struct Row: Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        /// "12 Oct 2026", or "" when the server sent no time.
        let when: String
    }

    let chats: [ProjectChat]

    init(chats: [ProjectChat]) {
        self.chats = chats
    }

    static let footnote = "Conversations here stay with this matter and read only its files. They are not listed in History."
    static let introTitle = "Ask about this matter."
    static let suggestions = [
        "Summarise where this matter stands.",
        "List the dates and events from the record.",
        "What should we prepare before the next hearing?",
        "Draft a status update for the client.",
    ]

    /// The line under the intro: what the conversation knows.
    static let introDetail = "Emperor reads this matter’s files and knows its dates, tasks and parties."

    /// The conversations, newest first by their last update (or when they joined the matter).
    var rows: [Row] {
        let listed = chats.filter { !$0.id.isEmpty }
        let sorted = listed.enumerated().sorted { a, b in
            let ta = Self.time(a.element), tb = Self.time(b.element)
            return ta != tb ? ta > tb : a.offset < b.offset
        }.map(\.element)
        return sorted.map { chat in
            let raw = chat.updatedAtRaw ?? chat.linkedAtRaw
            let day = MatterRecord.dayKey(raw)
            return Row(id: chat.id, title: Self.title(for: chat.title), when: day.isEmpty ? "" : MatterRecord.fmtDay(day))
        }
    }

    /// The conversation opened by default: the newest.
    var latestID: String? { rows.first?.id }

    func contains(_ chatID: String) -> Bool { chats.contains { $0.id == chatID } }

    private static func time(_ chat: ProjectChat) -> TimeInterval {
        let date = WireDate.parseAny(chat.updatedAtRaw) ?? WireDate.parseAny(chat.linkedAtRaw)
        return date?.timeIntervalSince1970 ?? 0
    }

    private static let placeholder = MatterPattern(
        "^(new chat|ai chat|untitled( chat| session| conversation)?)$", caseInsensitive: true)

    /// `isPlaceholderTitle`: no title, or one the server writes before the first question.
    static func isPlaceholder(_ title: String?) -> Bool {
        let trimmed = JSCompat.trim(title ?? "")
        return trimmed.isEmpty || placeholder.test(trimmed)
    }

    /// The title a row shows: the conversation's own, else "New conversation".
    static func title(for raw: String?) -> String {
        isPlaceholder(raw) ? "New conversation" : JSCompat.trim(raw ?? "")
    }

    /// A fresh conversation's id.
    static func newChatID() -> String { ChatViewModel.newChatID() }
}
