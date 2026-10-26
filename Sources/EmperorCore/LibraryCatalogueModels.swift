import Foundation

// The reference library's catalogue, as `/library/catalogue/*` sends it (`lib/library/routes.js`,
// `query.js`, `act.js`, `shelf.js`, `judgment.js` on the platform).
//
// Keys the server leaves `undefined` are absent and its `null`s are present, so every field but
// an id is optional. A few columns are text on one row and a number on another (`volume`,
// `issue`, a paragraph's `n`); those are read as either and kept as text.

// MARK: - Lenient reading

extension KeyedDecodingContainer {
    /// A string, or a number written as one; `nil` for absent, `null` or anything else.
    func libraryString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return JSCompat.numberString(d) }
        return nil
    }

    /// An integer, or a whole number sent as text; `nil` otherwise.
    func libraryInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key), d.isFinite, d == d.rounded() { return Int(d) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s) }
        return nil
    }

    /// A flag that may come as a boolean or as `0`/`1`.
    func libraryBool(_ key: Key) -> Bool? {
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        return nil
    }

    /// A list that is dropped, not fatal, when its shape is not the one expected.
    func libraryArray<T: Decodable>(_ type: T.Type, _ key: Key) -> [T]? {
        try? decodeIfPresent([T].self, forKey: key)
    }
}

// MARK: - A document

/// Something wrong the catalogue noticed about a row — almost always a date ("decided" next year).
struct LibraryAnomaly: Decodable, Hashable, Sendable {
    var kind: String?
}

/// The passage a body search found the words in.
struct LibrarySnippet: Decodable, Hashable, Sendable {
    var text: String?
    /// Whether the passage starts inside a sentence (an ellipsis goes before it).
    var before: Bool?
    var after: Bool?
    var term: String?
}

/// One document of the catalogue — a judgment, an Act or one of its instruments, a volume.
struct LibraryDoc: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    var title: String?
    var displayTitle: String?
    var rawTitle: String?
    var genericTitle: Bool?
    var displayRef: String?
    var reportNo: Int?
    var subject: String?
    var publisher: String?
    var kind: String?
    var lang: String?
    var volumeNo: Int?
    var dateFromTitle: String?
    var category: String?
    var docType: String?
    var isAmendment: Bool?
    var jurisdiction: String?
    var court: String?
    var courtLabel: String?
    var year: Int?
    /// A day in India, `YYYY-MM-DD`.
    var decidedOn: String?
    var petitioner: String?
    var respondent: String?
    var neutralCitation: String?
    var caseType: String?
    var caseNumber: String?
    /// A comma-separated list on a row (an array only in a judgment's header).
    var bench: String?
    var series: String?
    var volume: String?
    var issue: String?
    var reference: String?
    var titleFromScan: Bool?
    /// With its dot — `.pdf`.
    var ext: String?
    var fileSize: Int?
    /// `html`, `text`, `pdf` or `other`.
    var render: String?
    var hasChildren: Int?
    var parentId: Int?
    var anomalies: [LibraryAnomaly]?
    var coverUrl: String?
    /// `web` (a real front cover), `none` (never ask for one), or absent (the first page).
    var cover: String?
    var hasCover: Bool?
    var snippet: LibrarySnippet?
    // The Act index and the Act page.
    var tabCounts: [String: Int]?
    var instruments: Int?
    var groupTitle: String?
    var firstLetter: String?
    var aliases: [String]?
    var jurisdictionInferred: Bool?
    var copies: [Int]?
    var repealed: Bool?
    // `/doc` and `/judgment`.
    var hasFile: Bool?
    var hasText: Bool?

    init(id: Int, title: String? = nil, category: String? = nil) {
        self.id = id
        self.title = title
        self.category = category
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, displayTitle, rawTitle, genericTitle, displayRef, reportNo, subject, publisher,
             kind, lang, volumeNo, dateFromTitle, category, docType, isAmendment, jurisdiction, court,
             courtLabel, year, decidedOn, petitioner, respondent, neutralCitation, caseType,
             caseNumber, bench, series, volume, issue, reference, titleFromScan, ext, fileSize,
             render, hasChildren, parentId, anomalies, coverUrl, cover, hasCover, snippet,
             tabCounts, instruments, groupTitle, firstLetter, aliases, jurisdictionInferred,
             copies, repealed, hasFile, hasText
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.libraryInt(.id) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: c, debugDescription: "a library document without an id")
        }
        self.id = id
        title = c.libraryString(.title)
        displayTitle = c.libraryString(.displayTitle)
        rawTitle = c.libraryString(.rawTitle)
        genericTitle = c.libraryBool(.genericTitle)
        displayRef = c.libraryString(.displayRef)
        reportNo = c.libraryInt(.reportNo)
        subject = c.libraryString(.subject)
        publisher = c.libraryString(.publisher)
        kind = c.libraryString(.kind)
        lang = c.libraryString(.lang)
        volumeNo = c.libraryInt(.volumeNo)
        dateFromTitle = c.libraryString(.dateFromTitle)
        category = c.libraryString(.category)
        docType = c.libraryString(.docType)
        isAmendment = c.libraryBool(.isAmendment)
        jurisdiction = c.libraryString(.jurisdiction)
        court = c.libraryString(.court)
        courtLabel = c.libraryString(.courtLabel)
        year = c.libraryInt(.year)
        decidedOn = c.libraryString(.decidedOn)
        petitioner = c.libraryString(.petitioner)
        respondent = c.libraryString(.respondent)
        neutralCitation = c.libraryString(.neutralCitation)
        caseType = c.libraryString(.caseType)
        caseNumber = c.libraryString(.caseNumber)
        if let list = try? c.decodeIfPresent([String].self, forKey: .bench) {
            bench = list.joined(separator: ", ")
        } else {
            bench = c.libraryString(.bench)
        }
        series = c.libraryString(.series)
        volume = c.libraryString(.volume)
        issue = c.libraryString(.issue)
        reference = c.libraryString(.reference)
        titleFromScan = c.libraryBool(.titleFromScan)
        ext = c.libraryString(.ext)
        fileSize = c.libraryInt(.fileSize)
        render = c.libraryString(.render)
        hasChildren = c.libraryInt(.hasChildren)
        parentId = c.libraryInt(.parentId)
        anomalies = c.libraryArray(LibraryAnomaly.self, .anomalies)
        coverUrl = c.libraryString(.coverUrl)
        cover = c.libraryString(.cover)
        hasCover = c.libraryBool(.hasCover)
        if let snippet = try? c.decodeIfPresent(LibrarySnippet.self, forKey: .snippet) {
            self.snippet = snippet
        } else if let text = c.libraryString(.snippet) {
            snippet = LibrarySnippet(text: text)
        }
        tabCounts = try? c.decodeIfPresent([String: Int].self, forKey: .tabCounts)
        instruments = c.libraryInt(.instruments)
        groupTitle = c.libraryString(.groupTitle)
        firstLetter = c.libraryString(.firstLetter)
        aliases = c.libraryArray(String.self, .aliases)
        jurisdictionInferred = c.libraryBool(.jurisdictionInferred)
        copies = c.libraryArray(Int.self, .copies)
        repealed = c.libraryBool(.repealed)
        hasFile = c.libraryBool(.hasFile)
        hasText = c.libraryBool(.hasText)
    }

    // MARK: Derived

    /// Opens in the judgment reader rather than as a PDF (`isTextDoc`, `coverTheme.js`).
    var isText: Bool { LibraryDisplay.isTextDoc(self) }
    var isPDF: Bool { ext?.lowercased() == ".pdf" }
    /// The day decided, as midnight in India.
    var decidedDay: Date? { WireDate.parseDay(decidedOn) }
    /// From a shelf or a search result, a bare Act — or anything with instruments under it —
    /// opens its Act page; everything else the reading room (`openAny`, `pages/Library.jsx`).
    var opensAsAct: Bool {
        category == LibraryCategoryKey.bareActs.rawValue && (docType == "act" || (hasChildren ?? 0) > 0)
    }
    /// Whether a cover image is worth asking for: a PDF the server did not mark `cover: none`.
    var coverWanted: Bool { (isPDF || render == "pdf" || coverUrl != nil) && cover != "none" }
    /// The source dates it after today, or the catalogue flagged its date (`CaseLaw.jsx`).
    func isDateUnclear(today: String = WireDate.todayKey()) -> Bool {
        if !(anomalies ?? []).isEmpty { return true }
        return LibraryDisplay.isFutureDate(decidedOn, today: today)
    }
}

// MARK: - Envelopes

/// One collection, with how many documents it holds (`/categories`).
struct LibraryCategory: Decodable, Identifiable, Hashable, Sendable {
    let key: String
    var label: String?
    var count: Int?

    var id: String { key }
    var displayLabel: String { (label?.isEmpty == false ? label : nil) ?? LibraryDisplay.theme(key).label }

    init(key: String, label: String? = nil, count: Int? = nil) {
        self.key = key
        self.label = label
        self.count = count
    }
}

struct LibraryCategoriesResponse: Decodable, Sendable {
    var categories: [LibraryCategory]?
}

/// A facet value with its count — a court, a publisher, a kind, a document type, a jurisdiction.
struct LibraryFacetOption: Decodable, Hashable, Sendable {
    var value: String
    var label: String?
    var name: String?
    var count: Int?

    var displayLabel: String { (label?.isEmpty == false ? label : nil) ?? name ?? value }

    init(value: String, label: String? = nil, count: Int? = nil) {
        self.value = value
        self.label = label
        self.count = count
    }

    private enum CodingKeys: String, CodingKey { case value, label, name, count }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = c.libraryString(.value) ?? ""
        label = c.libraryString(.label)
        name = c.libraryString(.name)
        count = c.libraryInt(.count)
    }
}

struct LibraryYearCount: Decodable, Hashable, Sendable {
    var year: Int
    var count: Int
}

struct LibraryYearRange: Decodable, Hashable, Sendable {
    var min: Int
    var max: Int
}

struct LibrarySeriesFacet: Decodable, Hashable, Sendable {
    var value: String
    var count: Int?
    var yearMin: Int?
    var yearMax: Int?
}

/// One letter of an A–Z index (`#` for numbers and other scripts).
struct LibraryLetter: Decodable, Hashable, Sendable {
    var letter: String
    var count: Int
}

struct LibrarySortOption: Decodable, Hashable, Sendable {
    var value: String
    var label: String
}

/// What a collection can be narrowed by (`/facets`).
struct LibraryFacets: Decodable, Hashable, Sendable {
    var category: String?
    var label: String?
    var courts: [LibraryFacetOption] = []
    /// Newest first.
    var years: [LibraryYearCount] = []
    var yearRange: LibraryYearRange?
    var docTypes: [LibraryFacetOption] = []
    var jurisdictions: [LibraryFacetOption] = []
    var series: [LibrarySeriesFacet] = []
    var publishers: [LibraryFacetOption] = []
    var kinds: [LibraryFacetOption] = []
    var letters: [LibraryLetter] = []
    var sorts: [LibrarySortOption] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case category, label, courts, years, yearRange, docTypes, jurisdictions, series, publishers,
             kinds, letters, sorts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        category = c.libraryString(.category)
        label = c.libraryString(.label)
        courts = c.libraryArray(LibraryFacetOption.self, .courts) ?? []
        years = c.libraryArray(LibraryYearCount.self, .years) ?? []
        yearRange = try? c.decodeIfPresent(LibraryYearRange.self, forKey: .yearRange)
        docTypes = c.libraryArray(LibraryFacetOption.self, .docTypes) ?? []
        jurisdictions = c.libraryArray(LibraryFacetOption.self, .jurisdictions) ?? []
        series = c.libraryArray(LibrarySeriesFacet.self, .series) ?? []
        publishers = c.libraryArray(LibraryFacetOption.self, .publishers) ?? []
        kinds = c.libraryArray(LibraryFacetOption.self, .kinds) ?? []
        letters = c.libraryArray(LibraryLetter.self, .letters) ?? []
        sorts = c.libraryArray(LibrarySortOption.self, .sorts) ?? []
    }
}

struct LibraryFacetsResponse: Decodable, Sendable {
    var facets: LibraryFacets?
}

/// How much of the corpus a body search can see (`/search` carries it inline).
struct LibrarySearchIndex: Decodable, Hashable, Sendable {
    var available: Bool?
    var ready: Bool?
    var complete: Bool?
    var indexed: Int?
    var pending: Int?
    var noText: Int?
    var total: Int?
}

struct LibrarySearchStatusResponse: Decodable, Sendable {
    var index: LibrarySearchIndex?
}

/// One page of a collection (`/browse`) or of a body search (`/search`).
struct LibraryPage: Decodable, Hashable, Sendable {
    var items: [LibraryDoc] = []
    var total: Int = 0
    var page: Int = 1
    var pageSize: Int = 40
    var sort: String?
    var search: String?
    /// The body search stops counting at 1,000.
    var totalIsCapped: Bool?
    var mode: String?
    var index: LibrarySearchIndex?

    init(items: [LibraryDoc] = [], total: Int = 0, page: Int = 1, pageSize: Int = 40) {
        self.items = items
        self.total = total
        self.page = page
        self.pageSize = pageSize
    }

    private enum CodingKeys: String, CodingKey {
        case items, total, page, pageSize, sort, search, totalIsCapped, mode, index
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([LibraryDoc].self, forKey: .items) ?? []
        total = c.libraryInt(.total) ?? items.count
        page = c.libraryInt(.page) ?? 1
        pageSize = c.libraryInt(.pageSize) ?? max(items.count, 1)
        sort = c.libraryString(.sort)
        search = c.libraryString(.search)
        totalIsCapped = c.libraryBool(.totalIsCapped)
        mode = c.libraryString(.mode)
        index = try? c.decodeIfPresent(LibrarySearchIndex.self, forKey: .index)
    }

    /// How many pages `total` makes, at least one.
    var pageCount: Int { max(1, Int((Double(total) / Double(max(pageSize, 1))).rounded(.up))) }
}

/// Title matches in every collection at once (`/browse?groupBy=category`).
struct LibraryGroupedResults: Decodable, Hashable, Sendable {
    struct Group: Decodable, Hashable, Sendable {
        var category: String
        var label: String?
        var total: Int
        var items: [LibraryDoc]
    }

    var groups: [Group] = []
    var search: String?
    var pageSize: Int?

    init(groups: [Group] = []) { self.groups = groups }
}

/// One page of the Acts index (`/folders`).
struct LibraryActIndexPage: Decodable, Hashable, Sendable {
    var items: [LibraryDoc] = []
    var total: Int = 0
    var page: Int = 1
    var pageSize: Int = 60
    var letters: [LibraryLetter] = []
    var jurisdictions: [LibraryFacetOption] = []

    init(items: [LibraryDoc] = [], total: Int = 0, page: Int = 1, pageSize: Int = 60) {
        self.items = items
        self.total = total
        self.page = page
        self.pageSize = pageSize
    }

    private enum CodingKeys: String, CodingKey { case items, total, page, pageSize, letters, jurisdictions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([LibraryDoc].self, forKey: .items) ?? []
        total = c.libraryInt(.total) ?? items.count
        page = c.libraryInt(.page) ?? 1
        pageSize = c.libraryInt(.pageSize) ?? 60
        letters = c.libraryArray(LibraryLetter.self, .letters) ?? []
        jurisdictions = c.libraryArray(LibraryFacetOption.self, .jurisdictions) ?? []
    }

    var pageCount: Int { max(1, Int((Double(total) / Double(max(pageSize, 1))).rounded(.up))) }
}

/// One tab of an Act page — the Act itself, its Rules, its Amendments… (`/act`).
struct LibraryActTab: Decodable, Hashable, Sendable, Identifiable {
    var key: String
    var label: String
    var count: Int
    var docs: [LibraryDoc]

    var id: String { key }

    init(key: String, label: String, count: Int, docs: [LibraryDoc]) {
        self.key = key
        self.label = label
        self.count = count
        self.docs = docs
    }

    private enum CodingKeys: String, CodingKey { case key, label, count, docs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.libraryString(.key) ?? ""
        docs = try c.decodeIfPresent([LibraryDoc].self, forKey: .docs) ?? []
        label = c.libraryString(.label) ?? key
        count = c.libraryInt(.count) ?? docs.count
    }
}

/// An Act and everything made under it.
struct LibraryActBundle: Decodable, Hashable, Sendable {
    var act: LibraryDoc
    var bundleId: Int?
    /// `act`, `orphan` (an instrument whose Act is not held) or `amendments` (an Act known only
    /// by the Acts that amended it).
    var kind: String?
    var groupTitle: String?
    var requestedId: Int?
    var selectedId: Int?
    var selectedTab: String?
    var orphan: Bool?
    var tabs: [LibraryActTab] = []

    init(act: LibraryDoc, tabs: [LibraryActTab], kind: String? = "act",
         selectedId: Int? = nil, selectedTab: String? = nil) {
        self.act = act
        self.tabs = tabs
        self.kind = kind
        self.selectedId = selectedId
        self.selectedTab = selectedTab
    }

    private enum CodingKeys: String, CodingKey {
        case act, bundleId, kind, groupTitle, requestedId, selectedId, selectedTab, orphan, tabs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        act = try c.decode(LibraryDoc.self, forKey: .act)
        bundleId = c.libraryInt(.bundleId)
        kind = c.libraryString(.kind)
        groupTitle = c.libraryString(.groupTitle)
        requestedId = c.libraryInt(.requestedId)
        selectedId = c.libraryInt(.selectedId)
        selectedTab = c.libraryString(.selectedTab)
        orphan = c.libraryBool(.orphan)
        tabs = try c.decodeIfPresent([LibraryActTab].self, forKey: .tabs) ?? []
    }

    /// The kind, `orphan` read from the flag when the kind is absent.
    var resolvedKind: String { kind ?? (orphan == true ? "orphan" : "act") }
}

/// A few representative documents of a collection for the home page (`/shelf`).
struct LibraryShelf: Decodable, Hashable, Sendable {
    var category: String?
    var label: String?
    /// The day the shelf was chosen, `YYYYMMDD` in India.
    var day: Int?
    var items: [LibraryDoc] = []

    init(category: String? = nil, items: [LibraryDoc] = []) {
        self.category = category
        self.items = items
    }
}

/// Books & law reports shelved by series (`/shelf?by=series`).
struct LibrarySeriesShelves: Decodable, Hashable, Sendable {
    struct Shelf: Decodable, Hashable, Sendable, Identifiable {
        var series: String
        var count: Int?
        var yearMin: Int?
        var yearMax: Int?
        var items: [LibraryDoc] = []
        var id: String { series }
    }

    struct Standalone: Decodable, Hashable, Sendable {
        var count: Int?
        var items: [LibraryDoc] = []
    }

    var seriesTotal: Int?
    var shelves: [Shelf] = []
    var standalone: Standalone?

    init(shelves: [Shelf] = [], standalone: Standalone? = nil, seriesTotal: Int? = nil) {
        self.shelves = shelves
        self.standalone = standalone
        self.seriesTotal = seriesTotal
    }
}

/// A document with what hangs off it (`/doc`).
struct LibraryDocDetail: Decodable, Hashable, Sendable {
    struct ChildGroup: Decodable, Hashable, Sendable {
        var key: String
        var label: String?
        var items: [LibraryDoc] = []
    }

    var doc: LibraryDoc
    var childGroups: [ChildGroup] = []
    var childCount: Int?
    var editions: [LibraryDoc] = []
    var parent: LibraryDoc?

    init(doc: LibraryDoc) { self.doc = doc }

    private enum CodingKeys: String, CodingKey { case childGroups, childCount, editions, parent }

    init(from decoder: Decoder) throws {
        doc = try LibraryDoc(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        childGroups = c.libraryArray(ChildGroup.self, .childGroups) ?? []
        childCount = c.libraryInt(.childCount)
        editions = c.libraryArray(LibraryDoc.self, .editions) ?? []
        parent = try? c.decodeIfPresent(LibraryDoc.self, forKey: .parent)
    }
}

struct LibraryDocResponse: Decodable, Sendable {
    var doc: LibraryDocDetail
}

/// What a cover request came to.
enum LibraryCoverResult: Equatable, Sendable {
    case image(Data)
    /// No cover (`404 no_cover`, `cover: none`, or not worth asking): draw the typographic one.
    case none
    /// The server is rendering it (`404 cover_pending`, 202, 503): ask again later.
    case pending(retryAfter: TimeInterval)
}

// MARK: - Requests

/// The filters of a collection, the web's `libraryApi.js` `qs` rule: an empty value is not sent,
/// so equal filters make equal requests.
struct LibraryFilters: Hashable, Sendable {
    var category: String?
    var court: String?
    var yearFrom: Int?
    var yearTo: Int?
    var docType: String?
    var jurisdiction: String?
    var series: String?
    var parentId: Int?
    var publisher: String?
    var kind: String?
    var letter: String?
    var q: String?
    var sort: String?
    var page: Int?
    var pageSize: Int?

    init(category: String? = nil, q: String? = nil, sort: String? = nil,
         page: Int? = nil, pageSize: Int? = nil) {
        self.category = category
        self.q = q
        self.sort = sort
        self.page = page
        self.pageSize = pageSize
    }

    var query: [String: String] {
        var out: [String: String] = [:]
        func put(_ key: String, _ value: String?) {
            guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            out[key] = value
        }
        put("category", category)
        put("court", court)
        put("yearFrom", yearFrom.map(String.init))
        put("yearTo", yearTo.map(String.init))
        put("docType", docType)
        put("jurisdiction", jurisdiction)
        put("series", series)
        put("parentId", parentId.map(String.init))
        put("publisher", publisher)
        put("kind", kind)
        put("letter", letter)
        put("q", q?.trimmingCharacters(in: .whitespacesAndNewlines))
        put("sort", sort)
        put("page", page.map(String.init))
        put("pageSize", pageSize.map(String.init))
        return out
    }

    /// The filters a reader sets, as opposed to the collection, the search and the page.
    var activeFilterCount: Int {
        [court, docType, jurisdiction, series, publisher, kind, letter].filter { $0?.isEmpty == false }.count
            + ((yearFrom != nil || yearTo != nil) ? 1 : 0)
    }
}

/// The Acts index's filters (`/folders`).
struct LibraryActQuery: Hashable, Sendable {
    var letter: String?
    /// `Central`, a State, or `none`.
    var jurisdiction: String?
    var q: String?
    /// `acts` (the default), `all`, `folders` or `featured`.
    var kind: String?
    /// A tab key: only Acts with rules, notifications…
    var has: String?
    /// `title` (absent), `year` or `size`.
    var sort: String?
    var page: Int?
    var pageSize: Int?

    init(letter: String? = nil, jurisdiction: String? = nil, q: String? = nil, kind: String? = nil,
         has: String? = nil, sort: String? = nil, page: Int? = nil, pageSize: Int? = nil) {
        self.letter = letter
        self.jurisdiction = jurisdiction
        self.q = q
        self.kind = kind
        self.has = has
        self.sort = sort
        self.page = page
        self.pageSize = pageSize
    }

    var query: [String: String] {
        var out: [String: String] = [:]
        func put(_ key: String, _ value: String?) {
            guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            out[key] = value
        }
        put("letter", letter)
        put("jurisdiction", jurisdiction)
        put("q", q?.trimmingCharacters(in: .whitespacesAndNewlines))
        put("kind", kind)
        put("has", has)
        put("sort", sort)
        put("page", page.map(String.init))
        put("pageSize", pageSize.map(String.init))
        return out
    }
}
