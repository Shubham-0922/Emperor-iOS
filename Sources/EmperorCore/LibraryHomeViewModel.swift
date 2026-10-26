import Foundation
#if canImport(Darwin)
import Observation
#endif

/// The Library's front room: the collections, a shelf of each, and a search across all of them
/// (`pages/Library.jsx`, `LibraryHome.jsx`, `SearchResults.jsx`).
///
/// See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class LibraryHomeViewModel {

    struct ShelfState: Equatable, Sendable {
        var state: LoadState = .idle
        var items: [LibraryDoc] = []
    }

    /// How many titles each collection shows in the search results, and how many passages.
    static let titlesPerCollection = 6
    static let passageCount = 5
    static let shelfSize = 14

    private(set) var categories: [LibraryCategory] = []
    private(set) var state: LoadState = .idle
    /// This server has no catalogue: not a failure to retry so much as a state of the server.
    private(set) var isUnavailable = false
    private(set) var shelves: [String: ShelfState] = [:]

    var query = ""
    /// The search the results are for; `nil` while the home shelves show.
    private(set) var submittedQuery: String?
    private(set) var results: LibraryGroupedResults?
    private(set) var passages: LibraryPage?
    private(set) var titlesFailed = false
    private(set) var passagesFailed = false
    private(set) var isSearching = false
    private var searchToken = 0

    private let service: any LibraryProviding

    init(service: any LibraryProviding) {
        self.service = service
    }

    static let unavailableTitle = "Library unavailable"
    static let unavailableMessage = LibraryError.catalogueUnavailable.message

    // MARK: - Collections

    func load() async {
        state = .loading
        do {
            categories = try await service.categories()
            isUnavailable = false
            state = .loaded
        } catch LibraryError.catalogueUnavailable {
            isUnavailable = true
            categories = []
            state = .loaded
        } catch {
            isUnavailable = false
            state = .failed(LoadFailure(error))
        }
    }

    /// The collections that have a shelf, in shelf order (`CATEGORY_ORDER` present in `/categories`).
    var shelfKeys: [String] {
        let present = Set(categories.map(\.key))
        return LibraryCategoryKey.order.filter { present.contains($0) }
    }

    /// The strip of collections: the known ones in shelf order, then any this client does not know.
    var orderedCategories: [LibraryCategory] {
        let known = LibraryCategoryKey.order.compactMap { k in categories.first { $0.key == k } }
        return known + categories.filter { !LibraryCategoryKey.order.contains($0.key) }
    }

    func category(_ key: String) -> LibraryCategory? { categories.first { $0.key == key } }

    /// Whether there is nothing at all to show — every collection empty or none at all.
    var isEmpty: Bool { state.hasLoaded && !isUnavailable && categories.isEmpty }

    func shelf(_ key: String) -> ShelfState { shelves[key] ?? ShelfState() }

    /// Loads a collection's shelf the first time it comes near the screen; never twice.
    func loadShelf(_ key: String) async {
        let current = shelves[key]?.state ?? .idle
        guard current == .idle || current.failure != nil else { return }
        shelves[key] = ShelfState(state: .loading, items: shelves[key]?.items ?? [])
        do {
            let shelf = try await service.shelf(category: key, limit: Self.shelfSize)
            shelves[key] = ShelfState(state: .loaded, items: shelf.items)
        } catch {
            shelves[key] = ShelfState(state: .failed(LoadFailure(error)), items: [])
        }
    }

    // MARK: - Search

    var isShowingResults: Bool { submittedQuery != nil }

    /// Searches every collection's titles and the words inside judgments, side by side; one
    /// failing does not take the other with it.
    func submitSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            clearSearch()
            return
        }
        searchToken += 1
        let token = searchToken
        submittedQuery = q
        results = nil
        passages = nil
        titlesFailed = false
        passagesFailed = false
        isSearching = true

        let service = self.service
        async let titles = Self.attempt { try await service.titleSearch(q: q, perCategory: Self.titlesPerCollection) }
        async let bodies = Self.attempt {
            try await service.searchBodies(LibraryFilters(
                category: LibraryCategoryKey.caseLaw.rawValue, q: q, pageSize: Self.passageCount))
        }
        let (t, b) = await (titles, bodies)
        guard token == searchToken else { return }
        switch t {
        case .success(let value): results = value
        case .failure: titlesFailed = true
        }
        switch b {
        case .success(let value): passages = value
        case .failure: passagesFailed = true
        }
        isSearching = false
    }

    private nonisolated static func attempt<T: Sendable>(_ work: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    func clearSearch() {
        searchToken += 1
        submittedQuery = nil
        results = nil
        passages = nil
        titlesFailed = false
        passagesFailed = false
        isSearching = false
    }

    /// The collections with title matches, in shelf order.
    var resultGroups: [LibraryGroupedResults.Group] {
        let groups = results?.groups ?? []
        let ordered = LibraryCategoryKey.order.compactMap { k in groups.first { $0.category == k && $0.total > 0 } }
        return ordered + groups.filter { !LibraryCategoryKey.order.contains($0.category) && $0.total > 0 }
    }

    var passageItems: [LibraryDoc] { passages?.items ?? [] }

    /// `1,000+` when the server stopped counting.
    var passageCountText: String {
        guard let passages else { return "" }
        return LibraryDisplay.fmtCount(passages.total) + (passages.totalIsCapped == true ? "+" : "")
    }

    /// Nothing matched anywhere (and the search answered).
    var foundNothing: Bool {
        isShowingResults && !isSearching && resultGroups.isEmpty && passageItems.isEmpty && !searchFailed
    }

    /// Every part of the search failed: say so, rather than "Nothing found".
    var searchFailed: Bool {
        isShowingResults && !isSearching && titlesFailed && passagesFailed
    }

    var nothingFoundTitle: String { "Nothing found for “\(submittedQuery ?? "")”" }
    static let nothingFoundHint =
        "Check the spelling, try fewer words, or put a phrase in quotes — \"bona fide purchaser\" — to find it inside judgments."
    static let searchFailedTitle = "The search could not reach the library"
    static let searchFailedHint = "The library did not answer. Try again in a moment."

    /// The heading of a collection's results — case law matches are by name.
    static func resultTitle(for group: LibraryGroupedResults.Group) -> String {
        group.category == LibraryCategoryKey.caseLaw.rawValue
            ? "Case law by name" : (group.label ?? LibraryDisplay.theme(group.category).label)
    }
}
