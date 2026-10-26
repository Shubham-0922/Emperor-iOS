import Foundation
#if canImport(Darwin)
import Observation
#endif

/// One collection of the Library — its facets, filters, sort and numbered pages
/// (`categories/CaseLaw.jsx` and the shared `books/CoverGrid.jsx`).
///
/// A page being replaced stays on screen, dimmed, until the next arrives (`isStale`), and an
/// answer for filters the reader has since changed is dropped rather than shown.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class LibraryCollectionViewModel {

    /// What the search box searches in Case Law: case names and parties, or the words inside.
    enum Mode: String, Sendable { case titles, text }

    /// The facet rows a collection offers, in order.
    enum FacetRow: String, Sendable { case courts, publishers, kinds, years, letters }

    private(set) var category: LibraryCategory
    private(set) var facets: LibraryFacets?
    private(set) var facetsState: LoadState = .idle
    private(set) var filters: LibraryFilters
    private(set) var query: String
    private(set) var mode: Mode = .titles
    private(set) var result: LibraryPage?
    private(set) var state: LoadState = .idle
    private(set) var isLoading = false
    private var token = 0

    private let service: any LibraryProviding
    private let today: () -> String

    init(category: LibraryCategory, query: String = "", mode: Mode = .titles,
         service: any LibraryProviding, today: @escaping () -> String = { WireDate.todayKey() }) {
        self.category = category
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.service = service
        self.today = today
        self.filters = LibraryFilters(category: category.key)
        self.mode = mode
    }

    // MARK: - What the collection is

    var key: String { category.key }
    var theme: LibraryDisplay.Theme { LibraryDisplay.theme(key) }
    var isCaseLaw: Bool { key == LibraryCategoryKey.caseLaw.rawValue }

    /// "Words inside" is a Case Law search: only there, and only with something to search for.
    var offersTextMode: Bool { isCaseLaw && !query.isEmpty }
    var effectiveMode: Mode { offersTextMode ? mode : .titles }

    /// Read by reference and date rather than browsed by look: a list, not a grid of covers.
    var showsList: Bool {
        [LibraryCategoryKey.caseLaw, .regulatorOrders, .parliament].map(\.rawValue).contains(key)
    }

    var pageSize: Int {
        if isCaseLaw { return 20 }
        return showsList ? 30 : 36
    }

    /// The rows of the filter sheet (`facetKeys` of each `categories/*.jsx`).
    var facetRows: [FacetRow] {
        switch LibraryCategoryKey(rawValue: key) {
        case .caseLaw: return [.courts, .years]
        case .regulatorOrders: return [.publishers, .kinds, .years]
        case .tribunals: return [.publishers, .years]
        case .lawCommission: return [.years]
        case .institutes: return [.publishers, .letters]
        case .parliament: return [.kinds, .years]
        case .books: return [.letters, .years]
        case .legalAid: return []
        case .bareActs, .none: return [.years]
        }
    }

    /// What one of its documents is called, and many.
    var noun: (one: String, many: String) {
        switch LibraryCategoryKey(rawValue: key) {
        case .caseLaw: return ("judgment", "judgments")
        case .regulatorOrders: return ("order", "orders")
        case .tribunals: return ("decision", "decisions")
        case .lawCommission: return ("report", "reports")
        case .institutes: return ("publication", "publications")
        case .parliament, .legalAid: return ("paper", "papers")
        case .books: return ("volume", "volumes")
        default: return ("document", "documents")
        }
    }

    /// The label a facet row goes under.
    func rowLabel(_ row: FacetRow) -> String {
        switch (row, LibraryCategoryKey(rawValue: key)) {
        case (.courts, _): return "Court"
        case (.publishers, .regulatorOrders): return "Regulator"
        case (.publishers, .tribunals): return "Tribunal"
        case (.publishers, .institutes): return "Institute"
        case (.publishers, _): return "Publisher"
        case (.kinds, _): return "Type"
        case (.years, _): return "Year"
        case (.letters, _): return "A–Z"
        }
    }

    /// The sorts on offer: Case Law's own, the text search's, else the server's for the collection.
    var sortOptions: [LibrarySortOption] {
        if isCaseLaw {
            if effectiveMode == .text {
                return [LibrarySortOption(value: "", label: "Best match"),
                        LibrarySortOption(value: "date_desc", label: "Newest"),
                        LibrarySortOption(value: "date_asc", label: "Oldest")]
            }
            return [LibrarySortOption(value: "date_desc", label: "Newest"),
                    LibrarySortOption(value: "date_asc", label: "Oldest"),
                    LibrarySortOption(value: "title_asc", label: "A–Z")]
        }
        return facets?.sorts ?? []
    }

    /// The sort in force: the reader's, else the web's default for the collection, else the
    /// server's (`""` — Best match in a text search).
    var sort: String {
        if let chosen = filters.sort { return chosen }
        if isCaseLaw { return effectiveMode == .text ? "" : LibrarySort.newest.rawValue }
        return LibrarySort.webDefault(for: key) ?? result?.sort ?? ""
    }

    var courts: [LibraryFacetOption] { LibraryDisplay.orderCourts(facets?.courts ?? []) }

    // MARK: - Loading

    func load() async {
        async let f: Void = loadFacets()
        async let p: Void = reload()
        _ = await (f, p)
    }

    func loadFacets() async {
        guard facets == nil, facetsState != .loading else { return }
        facetsState = .loading
        do {
            facets = try await service.facets(key)
            facetsState = .loaded
        } catch {
            facetsState = .failed(LoadFailure(error))
        }
    }

    /// The request this collection would make now.
    var currentFilters: LibraryFilters {
        var f = filters
        f.category = key
        f.q = query.isEmpty ? nil : query
        f.page = (filters.page ?? 1) > 1 ? filters.page : nil
        f.pageSize = pageSize
        let s = sort
        f.sort = s.isEmpty ? nil : s
        return f
    }

    /// Asks for the page the filters describe. The last request wins: an answer for older
    /// filters is dropped.
    func reload() async {
        token += 1
        let mine = token
        let request = currentFilters
        let text = effectiveMode == .text
        isLoading = true
        if result == nil { state = .loading }
        do {
            let page = text ? try await service.searchBodies(request) : try await service.browse(request)
            guard mine == token else { return }
            result = page
            state = .loaded
        } catch {
            guard mine == token else { return }
            result = nil
            state = .failed(LoadFailure(error))
        }
        isLoading = false
    }

    // MARK: - Changing what is shown

    /// Another collection: the search is kept, its filters are not (`selectCategory`).
    func switchCategory(to category: LibraryCategory) async {
        self.category = category
        filters = LibraryFilters(category: category.key)
        facets = nil
        facetsState = .idle
        mode = .titles
        result = nil
        state = .idle
        await load()
    }

    private func apply(_ change: (inout LibraryFilters) -> Void) async {
        change(&filters)
        filters.page = nil
        await reload()
    }

    func setQuery(_ text: String) async {
        query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { mode = .titles }
        await apply { _ in }
    }

    func setMode(_ newMode: Mode) async {
        guard newMode != mode else { return }
        mode = newMode
        await apply { $0.sort = nil }
    }

    func setSort(_ value: String) async {
        await apply { $0.sort = value }
    }

    func setCourt(_ value: String?) async { await apply { $0.court = value } }
    func setPublisher(_ value: String?) async { await apply { $0.publisher = value } }
    func setKind(_ value: String?) async { await apply { $0.kind = value } }
    func setDocType(_ value: String?) async { await apply { $0.docType = value } }
    func setJurisdiction(_ value: String?) async { await apply { $0.jurisdiction = value } }

    func setYears(from: Int?, to: Int?) async {
        await apply {
            $0.yearFrom = from
            $0.yearTo = to
        }
    }

    /// A letter sorts A–Z unless the reader chose a sort (`AlphabetBar`).
    func setLetter(_ value: String?) async {
        await apply {
            $0.letter = value
            if value != nil, $0.sort == nil { $0.sort = LibrarySort.titleAscending.rawValue }
        }
    }

    func clearFilters() async {
        await apply { f in
            f = LibraryFilters(category: key, sort: f.sort)
        }
    }

    var activeFilterCount: Int { filters.activeFilterCount }

    /// The filters in force, as removable chips.
    struct ActiveFilter: Equatable, Identifiable, Sendable {
        enum Field: String, Sendable { case court, publisher, kind, docType, jurisdiction, letter, years }
        let field: Field
        let label: String
        var id: String { field.rawValue }
    }

    var activeFilters: [ActiveFilter] {
        var out: [ActiveFilter] = []
        if let c = filters.court {
            out.append(ActiveFilter(field: .court, label: LibraryDisplay.courtInfo(c, label: courts.first { $0.value == c }?.label).short))
        }
        if let p = filters.publisher {
            out.append(ActiveFilter(field: .publisher, label: facets?.publishers.first { $0.value == p }?.displayLabel ?? p))
        }
        if let k = filters.kind {
            out.append(ActiveFilter(field: .kind, label: facets?.kinds.first { $0.value == k }?.displayLabel ?? k))
        }
        if let d = filters.docType {
            out.append(ActiveFilter(field: .docType, label: facets?.docTypes.first { $0.value == d }?.displayLabel ?? d))
        }
        if let j = filters.jurisdiction { out.append(ActiveFilter(field: .jurisdiction, label: j)) }
        if let l = filters.letter { out.append(ActiveFilter(field: .letter, label: l == "#" ? "Other characters" : l)) }
        if !yearText.isEmpty { out.append(ActiveFilter(field: .years, label: yearText)) }
        return out
    }

    func remove(_ filter: ActiveFilter) async {
        await apply { f in
            switch filter.field {
            case .court: f.court = nil
            case .publisher: f.publisher = nil
            case .kind: f.kind = nil
            case .docType: f.docType = nil
            case .jurisdiction: f.jurisdiction = nil
            case .letter: f.letter = nil
            case .years:
                f.yearFrom = nil
                f.yearTo = nil
            }
        }
    }

    /// `2019`, or `2015–2020` with the facet's range filling an open end.
    var yearText: String {
        let from = filters.yearFrom
        let to = filters.yearTo
        guard from != nil || to != nil else { return "" }
        if let from, from == to { return String(from) }
        let a = from ?? facets?.yearRange?.min
        let b = to ?? facets?.yearRange?.max
        return "\(a.map(String.init) ?? "")–\(b.map(String.init) ?? "")"
    }

    // MARK: - Pages

    var page: Int { result?.page ?? filters.page ?? 1 }
    var pageCount: Int { result?.pageCount ?? 1 }
    var canGoBack: Bool { page > 1 && !isLoading }
    var canGoForward: Bool { page < pageCount && !isLoading }
    /// `Page 2 of 3`, with `+` when the search stopped counting.
    var pageLabel: String {
        "Page \(LibraryDisplay.fmtCount(page)) of \(LibraryDisplay.fmtCount(pageCount))\(result?.totalIsCapped == true ? "+" : "")"
    }

    func go(toPage n: Int) async {
        let target = max(1, min(n, pageCount))
        filters.page = target > 1 ? target : nil
        await reload()
    }

    func nextPage() async { if canGoForward { await go(toPage: page + 1) } }
    func previousPage() async { if canGoBack { await go(toPage: page - 1) } }

    // MARK: - What is on the page

    /// A page being replaced is kept on screen, dimmed.
    var isStale: Bool { isLoading && result != nil }

    var items: [LibraryDoc] {
        let list = result?.items ?? []
        guard isCaseLaw, sort == LibrarySort.newest.rawValue else { return list }
        return Self.arrangeCaseLaw(list, today: today())
    }

    /// On a "newest" list, judgments whose date is unclear go to the end of the page.
    static func arrangeCaseLaw(_ items: [LibraryDoc], today: String) -> [LibraryDoc] {
        let ok = items.filter { !$0.isDateUnclear(today: today) }
        guard ok.count != items.count else { return items }
        return ok + items.filter { $0.isDateUnclear(today: today) }
    }

    func isDateUnclear(_ doc: LibraryDoc) -> Bool { doc.isDateUnclear(today: today()) }

    var presentation: ListPresentation {
        ListPresentation(state: state, isEmpty: (result?.items ?? []).isEmpty)
    }

    /// `2,71,480 judgments with “bail” in the text · Supreme Court · 2015–2020`.
    var countLine: String {
        guard let result else { return "" }
        let total = LibraryDisplay.fmtCount(result.total) + (result.totalIsCapped == true ? "+" : "")
        var line = "\(total) \(result.total == 1 ? noun.one : noun.many)"
        if !query.isEmpty {
            if isCaseLaw {
                line += " with “\(query)” " + (effectiveMode == .text ? "in the text" : "in the case name")
            } else {
                line += " matching “\(query)”"
            }
        }
        if isCaseLaw, let c = filters.court {
            line += " · " + LibraryDisplay.courtInfo(c, label: courts.first { $0.value == c }?.label).name
        }
        if isCaseLaw, !yearText.isEmpty { line += " · " + yearText }
        return line
    }

    /// The empty state's words.
    var emptyTitle: String {
        if isCaseLaw {
            if !query.isEmpty { return "No judgments \(effectiveMode == .text ? "contain" : "are named") “\(query)”" }
            return "No judgments match these filters"
        }
        return query.isEmpty ? "No \(noun.many) match these filters" : "No \(noun.many) match “\(query)”"
    }

    var emptyHint: String {
        if isCaseLaw {
            if effectiveMode == .text {
                return "Try fewer words, or put a phrase in quotes to match it exactly, like \"bona fide purchaser\"."
            }
            return query.isEmpty ? "Try another court, or widen the years."
                : "Try one party’s name, or switch to “Words inside” to search the text of every judgment."
        }
        return activeFilterCount > 0 ? "Remove a filter or widen the years." : "Try a shorter search."
    }
}

// MARK: - The Acts index

/// Bare Acts: the A–Z index of Acts with the featured shelf (`categories/BareActs.jsx`).
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class LibraryActIndexViewModel {

    static let pageSize = 60
    static let sorts: [(value: String, label: String)] = [("", "A–Z"), ("year", "Newest first"), ("size", "Most instruments")]

    private(set) var featured: [LibraryDoc] = []
    private(set) var featuredState: LoadState = .idle
    private(set) var result: LibraryActIndexPage?
    private(set) var state: LoadState = .idle
    private(set) var isLoading = false
    private(set) var query: LibraryActQuery
    private var token = 0
    let total: Int?

    private let service: any LibraryProviding

    init(q: String = "", total: Int? = nil, service: any LibraryProviding) {
        self.service = service
        self.total = total
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        query = LibraryActQuery(q: trimmed.isEmpty ? nil : trimmed)
    }

    /// The whole index, first page, nothing narrowed: the featured shelf shows.
    var isBrowsing: Bool {
        query.q == nil && query.letter == nil && query.jurisdiction == nil && query.has == nil
            && query.sort == nil && (query.page ?? 1) == 1
    }

    var isFiltered: Bool { query.q != nil || query.letter != nil || query.jurisdiction != nil || query.has != nil }

    func load() async {
        async let index: Void = reload()
        async let shelf: Void = loadFeatured()
        _ = await (index, shelf)
    }

    func loadFeatured() async {
        guard featuredState == .idle else { return }
        featuredState = .loading
        do {
            featured = try await service.actIndex(LibraryActQuery(kind: "featured", pageSize: 40)).items
            featuredState = .loaded
        } catch {
            featuredState = .failed(LoadFailure(error))
        }
    }

    func reload() async {
        token += 1
        let mine = token
        var request = query
        // A search reaches everything, stand-alone amending Acts included; browsing shows the Acts.
        request.kind = query.q == nil ? nil : "all"
        request.pageSize = Self.pageSize
        isLoading = true
        if result == nil { state = .loading }
        do {
            let page = try await service.actIndex(request)
            guard mine == token else { return }
            result = page
            state = .loaded
        } catch {
            guard mine == token else { return }
            result = nil
            state = .failed(LoadFailure(error))
        }
        isLoading = false
    }

    private func apply(_ change: (inout LibraryActQuery) -> Void) async {
        change(&query)
        query.page = nil
        await reload()
    }

    func search(_ text: String) async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        await apply {
            $0.q = q.isEmpty ? nil : q
            if !q.isEmpty { $0.letter = nil }
        }
    }

    func setLetter(_ letter: String?) async { await apply { $0.letter = $0.letter == letter ? nil : letter } }
    func setJurisdiction(_ value: String?) async { await apply { $0.jurisdiction = $0.jurisdiction == value ? nil : value } }
    func setHas(_ value: String?) async { await apply { $0.has = $0.has == value ? nil : value } }
    func setSort(_ value: String) async { await apply { $0.sort = value.isEmpty ? nil : value } }

    func clearFilters() async {
        await apply {
            $0.letter = nil
            $0.jurisdiction = nil
            $0.has = nil
            $0.q = nil
        }
    }

    var items: [LibraryDoc] { result?.items ?? [] }
    var letters: [LibraryLetter] { result?.letters ?? [] }
    var jurisdictions: [LibraryFacetOption] { result?.jurisdictions ?? [] }
    var page: Int { result?.page ?? query.page ?? 1 }
    var pageCount: Int { result?.pageCount ?? 1 }
    var isStale: Bool { isLoading && result != nil }
    var pageLabel: String { "Page \(LibraryDisplay.fmtCount(page)) of \(LibraryDisplay.fmtCount(pageCount))" }

    func go(toPage n: Int) async {
        let target = max(1, min(n, pageCount))
        query.page = target > 1 ? target : nil
        await reload()
    }

    /// `83 Central Acts under I, with rules` (`BareActs.jsx`).
    var countLine: String {
        guard let result else { return "" }
        let jurisdictionWord = query.jurisdiction.flatMap { $0 == "none" ? nil : "\($0) " } ?? ""
        var described: [String] = []
        if query.jurisdiction == "none" { described.append("with no jurisdiction recorded") }
        if let l = query.letter { described.append(l == "#" ? "under numbers and other scripts" : "under \(l)") }
        if let h = query.has {
            described.append("with " + (LibraryDisplay.hasFilters.first { $0.key == h }?.label.lowercased() ?? h))
        }
        if let q = query.q { described.append("matching “\(q)”") }
        let head = "\(LibraryDisplay.fmtCount(result.total)) \(jurisdictionWord)\(result.total == 1 ? "Act" : "Acts")"
        return described.isEmpty ? head : head + " " + described.joined(separator: ", ")
    }

    var emptyHint: String {
        query.q != nil ? "Try the short name lawyers use (PMLA, CrPC, NI Act), or fewer words."
            : "Choose another letter or jurisdiction, or clear the filters."
    }

    /// "9 rules · 25 amendments" — what an Act holds, the chosen "Contains" first.
    func holds(_ doc: LibraryDoc) -> String {
        LibraryDisplay.countParts(doc.tabCounts, first: query.has).prefix(3).joined(separator: " · ")
    }
}

// MARK: - Books

/// Books & law reports: shelves by series, one series' volumes, or every book
/// (`categories/BooksAndReports.jsx`). "All books" is a `LibraryCollectionViewModel`.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class LibraryBooksViewModel {

    private(set) var shelves: LibrarySeriesShelves?
    private(set) var state: LoadState = .idle
    private(set) var seriesIndex: [LibrarySeriesFacet] = []

    private let service: any LibraryProviding

    init(service: any LibraryProviding) {
        self.service = service
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading
        async let index: [LibrarySeriesFacet] = (try? await service.facets(LibraryCategoryKey.books.rawValue).series) ?? []
        do {
            shelves = try await service.seriesShelves(limit: 12, per: 14)
            state = .loaded
        } catch {
            state = .failed(LoadFailure(error))
        }
        seriesIndex = await index
    }

    static func shelfBlurb(_ shelf: LibrarySeriesShelves.Shelf) -> String {
        [shelf.count.map { "\(LibraryDisplay.fmtCount($0)) volumes" },
         LibraryDisplay.yearSpan(shelf.yearMin, shelf.yearMax)].compactMap { LibraryDisplay.truthy($0) }
            .joined(separator: " · ")
    }

    static let standaloneBlurb = "Commentaries, treatises, reports and pamphlets that stand on their own."
}

/// Every volume of one series, by decade (`SeriesPage`, `bookFormat.js`).
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class LibrarySeriesViewModel {

    let series: String
    private(set) var volumes: [LibraryDoc] = []
    private(set) var total = 0
    private(set) var state: LoadState = .idle

    private let service: any LibraryProviding

    init(series: String, service: any LibraryProviding) {
        self.series = series
        self.service = service
    }

    var title: String { LibraryDisplay.seriesName(series) }

    /// Three pages of a hundred cover any run in the catalogue.
    func load() async {
        state = .loading
        do {
            var filters = LibraryFilters(category: LibraryCategoryKey.books.rawValue, sort: LibrarySort.yearOldest.rawValue, pageSize: 100)
            filters.series = series
            let first = try await service.browse(filters)
            var items = first.items
            let pages = min(3, Int((Double(first.total) / 100).rounded(.up)))
            if pages >= 2 {
                for p in 2...pages {
                    filters.page = p
                    items += try await service.browse(filters).items
                }
            }
            volumes = items
            total = first.total
            state = .loaded
        } catch {
            state = .failed(LoadFailure(error))
        }
    }

    var decades: [LibraryDisplay.Decade] { LibraryDisplay.groupByDecade(volumes) }

    /// `42 volumes · 1904–1952 · 3 undated`.
    var summary: String {
        guard state.hasLoaded else { return "Loading volumes…" }
        let years = volumes.compactMap(\.year).filter { $0 > 1500 }
        let span = years.isEmpty ? "" : LibraryDisplay.yearSpan(years.min(), years.max())
        let undated = !years.isEmpty && years.count < volumes.count ? "\(volumes.count - years.count) undated" : ""
        return ["\(LibraryDisplay.fmtCount(total)) volume\(total == 1 ? "" : "s")", span, undated]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
