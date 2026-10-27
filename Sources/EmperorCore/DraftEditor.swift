import Foundation
#if canImport(Darwin)
import Observation
#endif

/// Rules for editing a saved draft in place.
enum DraftEditor {
    /// Whether an HTML draft can be edited in its web view. Markdown drafts are always editable,
    /// as text. Off would leave HTML drafts read-only, as they were.
    static let htmlEditingEnabled = true

    /// Said when an edit would leave nothing to save.
    static let emptyMessage = "A draft cannot be saved empty."

    /// Said when the edited document could not be read back to save it.
    static let unreadableMessage = "Your changes could not be read to save them. Please try again."

    /// The script that reads an HTML draft's edited body back out of its web view: the wrapper's
    /// contents only, never the page shell around it (`ArtifactDocument.html(wrapping:editable:)`).
    static let readBackScript = "return document.querySelector('.scroll').innerHTML;"

    /// Whether `content` holds no words once markup is taken out — an HTML draft whose text was
    /// all deleted still has its wrapping tags.
    static func isBlank(_ content: String) -> Bool {
        let withoutTags = content.replacingOccurrences(
            of: "<[^>]*>", with: " ", options: .regularExpression)
        let withoutSpaces = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
        return withoutSpaces.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Editing one saved draft and saving it over its row, as the web's live-draft canvas does
/// (`src/tools/ToolWorkspace.jsx`, `onDocEditCommit`): the same id, so the edit replaces the
/// draft in the library instead of adding a copy.
///
/// The row keeps its conversation and its kind: both are sent as the row has them. The server
/// may answer with a different id — the same content already saved in that conversation — and
/// that id is the one adopted, so the next save lands on the right row.
///
/// See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class DraftEditorModel {

    enum Phase: Equatable, Sendable {
        case reading
        case editing
        case saving
        /// The save was refused or failed; the edit is kept on screen with the reason.
        case failed(String)
    }

    /// What one save sends, read from the row.
    struct Request: Equatable, Sendable {
        let id: String
        let title: String
        let content: String
        let type: String
        let chatId: String?
    }

    private(set) var phase: Phase = .reading
    /// The draft as last saved — what the reader shows.
    private(set) var content: String
    /// The row that holds it: the one opened, or the one the server answered with.
    private(set) var itemID: String
    /// The edit a failed save was holding, so the editor can be filled with it again.
    private(set) var pendingEdit: String?

    private let item: DraftedItem
    private let service: any FileRouteProviding

    init(item: DraftedItem, content: String, service: any FileRouteProviding) {
        self.item = item
        self.content = content
        self.itemID = item.id
        self.service = service
    }

    var isEditing: Bool { phase != .reading }
    var isSaving: Bool { phase == .saving }

    var errorMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    func beginEditing() {
        guard phase == .reading else { return }
        pendingEdit = nil
        phase = .editing
    }

    func cancel() {
        guard phase != .saving else { return }
        pendingEdit = nil
        phase = .reading
    }

    /// Saves `edited` over the row. `true` when it was saved.
    ///
    /// Nothing is sent when the text is unchanged — editing ends — or when nothing would be left
    /// of the draft. A failure keeps the edit and says why.
    func save(_ edited: String) async -> Bool {
        guard phase != .saving else { return false }
        if edited == content {
            pendingEdit = nil
            phase = .reading
            return false
        }
        if DraftEditor.isBlank(edited) {
            pendingEdit = edited
            phase = .failed(DraftEditor.emptyMessage)
            return false
        }
        pendingEdit = edited
        phase = .saving
        let request = Self.request(item: currentItem, content: edited)
        do {
            let result = try await service.saveDocument(
                id: request.id, title: request.title, content: request.content,
                type: request.type, chatId: request.chatId)
            if let id = result.id, !id.isEmpty { itemID = id }
            content = edited
            pendingEdit = nil
            phase = .reading
            return true
        } catch {
            phase = .failed(DisplayText.message(for: error))
            return false
        }
    }

    /// The edit could not be read back from the editor; it stays on screen to try again.
    func couldNotRead() {
        guard phase != .saving else { return }
        phase = .failed(DraftEditor.unreadableMessage)
    }

    /// The row as it now stands — with the id the last save answered.
    var currentItem: DraftedItem {
        DraftedItem(
            id: itemID, chatID: item.chatID, title: item.title, type: item.type,
            createdAtRaw: item.createdAtRaw, chatTitle: item.chatTitle)
    }

    /// The save for `content` over `item`: the row's own id, title, kind and conversation.
    nonisolated static func request(item: DraftedItem, content: String) -> Request {
        let chat = item.chatID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let kind = item.type?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Request(
            id: item.id,
            title: item.displayTitle,
            content: content,
            type: kind.isEmpty ? DraftKind.document.rawValue : kind,
            chatId: chat.isEmpty ? nil : chat)
    }
}
