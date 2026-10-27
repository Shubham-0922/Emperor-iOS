import Foundation
#if canImport(Darwin)
import Observation
#endif

/// A matter's Drafts — the web's `DraftsSection`: what the matter's conversations produced,
/// documents and tables together, newest first, each opened in the draft reader. A draft belongs
/// to a matter through the conversation it was made in; the Library leaves these out.
///
/// See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class MatterDraftListViewModel {
    let projectID: String
    private(set) var items: [DraftedItem] = []
    private(set) var state: LoadState = .idle
    /// One of the two lists could not be read; the other is shown.
    private(set) var partial: String?
    var opened: DraftHistoryViewModel.OpenedDraft?
    private(set) var loadingID: String?
    var errorMessage: String?

    private let service: any DraftHistoryProviding

    init(projectID: String, service: any DraftHistoryProviding) {
        self.projectID = projectID
        self.service = service
    }

    /// Both lists; one failing leaves the other on screen with a word about the missing half.
    func load() async {
        if items.isEmpty { state = .loading }
        var docs: [DraftedItem]?
        var tables: [DraftedItem]?
        var failure: Error?
        do { docs = try await service.drafts(.document, projectID: projectID) } catch { failure = error }
        do { tables = try await service.drafts(.table, projectID: projectID) } catch { failure = failure ?? error }
        if docs == nil, tables == nil, let failure {
            state = .failed(LoadFailure(failure))
            return
        }
        var seen = Set<String>()
        let all = (docs ?? []) + (tables ?? [])
        let unique = all.filter { seen.insert($0.id).inserted }
        items = unique.enumerated().sorted { a, b in
            let ta = a.element.createdAt?.timeIntervalSince1970 ?? 0
            let tb = b.element.createdAt?.timeIntervalSince1970 ?? 0
            return ta != tb ? ta > tb : a.offset < b.offset
        }.map(\.element)
        partial = docs == nil ? "Documents could not be loaded." : tables == nil ? "Tables could not be loaded." : nil
        state = .loaded
    }

    func isTable(_ item: DraftedItem) -> Bool { item.type == DraftKind.table.rawValue }

    func open(_ item: DraftedItem) async {
        guard loadingID == nil else { return }
        loadingID = item.id
        errorMessage = nil
        defer { loadingID = nil }
        do {
            opened = DraftHistoryViewModel.OpenedDraft(item: item, content: try await service.content(id: item.id))
        } catch {
            errorMessage = DisplayText.message(for: error)
        }
    }
}
