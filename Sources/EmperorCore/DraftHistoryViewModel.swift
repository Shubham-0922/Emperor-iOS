import Foundation
#if canImport(Darwin)
import Observation
#endif

/// Everything the assistant has drafted, across every conversation.
///
/// Worth its own screen because the alternative is remembering which chat a pleading came out
/// of. On a phone that is the difference between finding last week's draft in five seconds and
/// scrolling a conversation list.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class DraftHistoryViewModel {
    var kind: DraftKind = .document {
        didSet {
            guard kind != oldValue else { return }
            // Drafts and tables are separate routes with separate lists. Showing one while the
            // picker says the other is worse than a spinner.
            items = []
            state = .idle
        }
    }

    private(set) var items: [DraftedItem] = []
    private(set) var state: LoadState = .idle
    var query = ""

    /// The draft being read, once its content has arrived.
    var opened: OpenedDraft?
    private(set) var loadingID: String?
    var errorMessage: String?

    private let service: any DraftHistoryProviding

    struct OpenedDraft: Equatable, Identifiable {
        let item: DraftedItem
        let content: String
        /// Which opening this is — the row first opened, kept when a save moves the draft to
        /// another row, so the reader on screen stays the same reader.
        let presentationID: String
        var id: String { presentationID }

        init(item: DraftedItem, content: String, presentationID: String? = nil) {
            self.item = item
            self.content = content
            self.presentationID = presentationID ?? item.id
        }

        /// How to draw it — read from the content, never taken from the row's `type`.
        ///
        /// Drafts arrive as inline-styled HTML fragments: centred headings, underlined court
        /// names, bordered tables of contents. Rendering one as Markdown gives a wall of raw
        /// tags, which is exactly what this screen did — every draft went to the Markdown
        /// renderer whatever was in it.
        ///
        /// `detectFormat` is the sniff the streaming path already uses, and the platform's own
        /// `canvasShape.js` exists because a declared type is a claim rather than a fact. The
        /// declared kind is passed through as its tiebreak, but it settles only the case where
        /// the body holds neither block HTML nor a Markdown table: the content decides first.
        var format: StreamArtifact.Format {
            StreamArtifact.detectFormat(
                of: content, declared: item.type == DraftKind.table.rawValue ? .table : .canvas)
        }
    }

    init(service: any DraftHistoryProviding) {
        self.service = service
    }

    var presentation: ListPresentation {
        ListPresentation(state: state, isEmpty: visible.isEmpty)
    }

    /// Filtered by the search field, matching on the draft's own title and on the conversation
    /// it came from — someone looking for "the Bakshi petition" may remember either.
    var visible: [DraftedItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { item in
            item.displayTitle.localizedCaseInsensitiveContains(trimmed)
                || (item.chatTitle ?? "").localizedCaseInsensitiveContains(trimmed)
        }
    }

    var showsNoSearchResults: Bool {
        state == .loaded && !items.isEmpty && visible.isEmpty
    }

    /// Grouped by the day they were produced, in India.
    ///
    /// A draft written at 11pm IST is that day's work, not the next day's — which is what
    /// bucketing against the device's own zone would say to anyone travelling.
    var groups: [Group] {
        var order: [String] = []
        var byDay: [String: [DraftedItem]] = [:]
        for item in visible {
            let key = item.createdAt.map(WireDate.dayKey) ?? ""
            if byDay[key] == nil { order.append(key) }
            byDay[key, default: []].append(item)
        }
        return order.map { key in
            Group(id: key, title: Self.dayTitle(key), items: byDay[key] ?? [])
        }
    }

    struct Group: Identifiable, Equatable {
        let id: String
        let title: String
        let items: [DraftedItem]
    }

    /// A row whose timestamp did not parse still has to appear somewhere. Burying it under a
    /// blank heading would read as a rendering fault.
    static func dayTitle(_ key: String) -> String {
        guard !key.isEmpty, let date = WireDate.parseDay(key) else { return "Undated" }
        return DisplayText.relative(date)
    }

    // MARK: - Loading

    func load() async {
        state = .loading
        do {
            items = try await service.drafts(kind)
            state = .loaded
        } catch is CancellationError {
            // Switching the Drafts/Tables control cancels the in-flight fetch, and a cancelled
            // `URLSession` request surfaces as a retryable transport error that `withRetry`
            // then converts into a `CancellationError`. Treated as a failure it renders as
            // "The operation couldn't be completed. (Swift.CancellationError error 1.)" with a
            // Try again button — for a request the user themselves replaced a moment ago.
            // The replacement task owns the state from here.
            return
        } catch {
            items = []
            state = .failed(LoadFailure(error))
        }
    }

    // MARK: - Opening

    func open(_ item: DraftedItem) {
        Task { await runOpen(item) }
    }

    func runOpen(_ item: DraftedItem) async {
        guard loadingID == nil else { return }
        loadingID = item.id
        errorMessage = nil
        defer { loadingID = nil }

        do {
            opened = OpenedDraft(item: item, content: try await service.content(id: item.id))
        } catch {
            // An empty body is the server's answer for a row that is gone, so this is the
            // ordinary "you deleted the conversation" case, not an exceptional one.
            errorMessage = DisplayText.message(for: error)
        }
    }

    func close() { opened = nil }

    // MARK: - Editing

    /// The draft on screen was saved: it now reads `content`, held by the row `id` (the server
    /// may answer with another row than the one opened). The row is patched in place at once;
    /// the screen then reloads the list, where the server has dated it now and put it first.
    func replaceOpened(content: String, id: String) {
        guard let current = opened else { return }
        let old = current.item
        let row = DraftedItem(
            id: id, chatID: old.chatID, title: old.title, type: old.type,
            createdAtRaw: old.createdAtRaw, chatTitle: old.chatTitle)
        opened = OpenedDraft(item: row, content: content, presentationID: current.presentationID)
        var patched: [DraftedItem] = []
        for item in items where item.id != id || item.id == old.id {
            patched.append(item.id == old.id ? row : item)
        }
        items = patched
    }
}
