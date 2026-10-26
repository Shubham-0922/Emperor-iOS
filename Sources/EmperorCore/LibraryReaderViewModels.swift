import Foundation
#if canImport(Darwin)
import Observation
#endif

// MARK: - A document's file

/// A PDF from the catalogue, asked about before it is fetched: a file the server does not hold
/// says so ("not on the shelf yet") instead of failing in the viewer, and one too large to hold
/// in memory is offered on the web instead (`ReadingRoom.jsx`, `act/ReadingPane.jsx`).
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class LibraryFileViewModel {

    enum Content: Equatable, Sendable {
        case idle
        case loading
        case ready(Data)
        /// Listed in the catalogue, but its file is not on this server yet.
        case missing
        /// Larger than this client opens in memory; the web can page it.
        case tooLarge(bytes: Int?)
        case failed(LoadFailure)
    }

    /// The largest file read into memory. The corpus holds scans of several hundred megabytes.
    static let maxInMemoryBytes = 64 * 1024 * 1024

    let docID: Int
    private(set) var content: Content = .idle
    private let service: any LibraryProviding

    init(docID: Int, service: any LibraryProviding) {
        self.docID = docID
        self.service = service
    }

    var data: Data? {
        if case .ready(let data) = content { return data }
        return nil
    }

    func load(knownMissing: Bool = false) async {
        if case .ready = content { return }
        if knownMissing {
            content = .missing
            return
        }
        content = .loading
        do {
            let head = try await service.fileHead(id: docID)
            if head.status == 404 {
                content = .missing
                return
            }
            guard (200..<300).contains(head.status) else {
                content = .failed(LoadFailure(APIError.server(status: head.status, message: "The server answered \(head.status).")))
                return
            }
            if let length = head.length, length > Self.maxInMemoryBytes {
                content = .tooLarge(bytes: length)
                return
            }
            let data = try await service.file(id: docID, prefer: nil)
            content = data.count > Self.maxInMemoryBytes ? .tooLarge(bytes: data.count) : .ready(data)
        } catch LibraryError.fileMissing {
            content = .missing
        } catch LibraryError.notFound {
            content = .missing
        } catch {
            content = .failed(LoadFailure(error))
        }
    }

    static let missingTitle = "This document is not on the shelf yet"
    static let missingMessage = "It is listed in the catalogue, but its file has not been copied to this server. Try again later."
    static let tooLargeTitle = "Too large to open here"
    static func tooLargeMessage(_ bytes: Int?) -> String {
        let size = LibraryDisplay.bookSize(bytes)
        return "This scan is \(size.isEmpty ? "very large" : size). Open it on the web, where it can be read a page at a time."
    }
}

// MARK: - The reading room

/// The reading room: the catalogue row that was tapped paints the header at once, `/doc` fills
/// it in, and the body is the judgment reader for a text document or the PDF otherwise
/// (`ReadingRoom.jsx`).
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class LibraryReaderViewModel {

    enum Body: Equatable {
        case loading
        case judgment
        case pdf
        /// `/doc` answered "no such document".
        case notFound
        case failed(LoadFailure)
    }

    private(set) var doc: LibraryDoc
    private(set) var detail: LibraryDocDetail?
    private(set) var body: Body = .loading
    private(set) var judgment: LibraryJudgmentViewModel?
    private(set) var file: LibraryFileViewModel?

    private let service: any LibraryProviding

    init(seed: LibraryDoc, service: any LibraryProviding) {
        self.doc = seed
        self.service = service
    }

    var title: String {
        doc.category == LibraryCategoryKey.caseLaw.rawValue ? LibraryDisplay.caseTitleText(doc) : LibraryDisplay.tidyTitle(doc)
    }

    var cap: String { LibraryDisplay.theme(doc.category).cap }
    var meta: [String] { LibraryDisplay.docMeta(doc) }

    /// Whether the file is on this server — `/doc` says `hasFile: false` when it is not.
    var isOnShelf: Bool { doc.hasFile != false }

    func load() async {
        body = .loading
        do {
            let detail = try await service.doc(id: doc.id)
            self.detail = detail
            doc = detail.doc
        } catch LibraryError.notFound {
            body = .notFound
            return
        } catch {
            // The seed row is enough to try the file; a missing document or an ended session
            // stops here.
            if let api = error as? APIError, api == .invalidCredentials || api == .notAuthenticated {
                body = .failed(LoadFailure(error))
                return
            }
        }
        if doc.isText {
            let model = judgment ?? LibraryJudgmentViewModel(doc: doc, service: service)
            judgment = model
            body = .judgment
            await model.load()
        } else {
            let model = file ?? LibraryFileViewModel(docID: doc.id, service: service)
            file = model
            body = .pdf
            await model.load(knownMissing: doc.hasFile == false)
        }
    }

    static let notFoundTitle = "There is no such document"
    static let notFoundMessage = "The link may be old. Find it in the library instead."

    /// A name for the file when it is shared.
    var shareName: String {
        let base = title.replacingOccurrences(of: "/", with: "-")
        return base + (doc.isPDF ? ".pdf" : (doc.ext ?? ".txt"))
    }
}

// MARK: - The judgment reader

/// A formatted judgment, with its contents, find, paragraph links and the plain-text fallback
/// (`caselaw/JudgmentView.jsx`, `readerModel.js`).
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class LibraryJudgmentViewModel {

    enum State: Equatable {
        case loading
        case ready
        /// The judgment's text is not on this server yet.
        case missing
        case tooLarge
        case failed(LoadFailure)
    }

    /// Text-size steps (`SIZE_STEPS`), the third the default.
    static let sizeSteps: [Double] = [0.88, 0.94, 1, 1.08, 1.17, 1.28, 1.4]

    let doc: LibraryDoc
    private(set) var state: State = .loading
    private(set) var header: LibraryJudgmentHeader?
    private(set) var blocks: [JudgmentBlock] = []
    private(set) var toc: [JudgmentTOCEntry] = []
    private(set) var stats: JudgmentStats?
    /// Shown as plain text because the formatted version could not be prepared.
    private(set) var isPlain = false
    var sizeStep = 2

    private(set) var findQuery = ""
    private(set) var hits: [JudgmentText.Hit] = []
    private(set) var hitsCapped = false
    private(set) var currentHit: Int?

    private let service: any LibraryProviding

    init(doc: LibraryDoc, service: any LibraryProviding) {
        self.doc = doc
        self.service = service
    }

    static let plainNote = "Shown as plain text — the formatted version could not be prepared."
    static let missingTitle = "This judgment is not on the shelf yet"
    static let missingMessage = "It is listed in the catalogue, but its text has not been copied to this server yet."
    static let tooLargeTitle = "This judgment is too long to open here"
    static let tooLargeMessage = "The reader opens judgments up to 4 MB. Share the original to read all of it."
    static let failedTitle = "We couldn’t load this judgment"

    func load() async {
        state = .loading
        do {
            let j = try await service.judgment(id: doc.id)
            header = j.header
            blocks = j.blocks
            toc = j.toc
            stats = j.stats
            isPlain = false
            state = .ready
        } catch LibraryError.fileMissing {
            state = .missing
        } catch let error as APIError where error == .invalidCredentials || error == .notAuthenticated {
            state = .failed(LoadFailure(error))
        } catch {
            await loadPlain(after: error)
        }
        refreshFind()
    }

    /// Anything but "not here" or a signed-out answer: the stored text, split into paragraphs.
    private func loadPlain(after original: Error) async {
        do {
            let data = try await service.file(id: doc.id, prefer: "text")
            guard data.count <= JudgmentText.maxReaderBytes else {
                state = .tooLarge
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            header = nil
            toc = []
            stats = nil
            blocks = JudgmentText.blocks(fromParagraphs: JudgmentText.paragraphs(fromStoredText: text))
            isPlain = true
            state = .ready
        } catch LibraryError.tooLarge {
            state = .tooLarge
        } catch {
            state = .failed(LoadFailure(original))
        }
    }

    var textScale: Double { Self.sizeSteps[max(0, min(sizeStep, Self.sizeSteps.count - 1))] }
    var canEnlarge: Bool { sizeStep < Self.sizeSteps.count - 1 }
    var canShrink: Bool { sizeStep > 0 }
    func enlarge() { if canEnlarge { sizeStep += 1 } }
    func shrink() { if canShrink { sizeStep -= 1 } }

    // MARK: Contents

    /// The headings of the contents (levels 1 and 2).
    var headings: [JudgmentTOCEntry] { toc.filter { $0.level <= 2 } }

    /// About sixteen evenly spaced paragraphs to jump to, in a judgment of fifteen or more
    /// (`paraMarksOf`); a later opinion's restarted numbers do not repeat.
    var paragraphMarks: [JudgmentTOCEntry] {
        let numbered = blocks.compactMap { b -> (id: String, n: Int)? in
            guard let n = b.n, let v = Int(n) else { return nil }
            return (b.id, v)
        }
        guard numbered.count >= 15, let last = numbered.last?.n else { return [] }
        let step = [5, 10, 20, 25, 50, 100, 200, 250, 500].first { Double(last) / Double($0) <= 18 } ?? 1000
        var seen = Set<Int>()
        return numbered.filter { p in
            guard p.n == 1 || p.n % step == 0, !seen.contains(p.n) else { return false }
            seen.insert(p.n)
            return true
        }.map { JudgmentTOCEntry(id: $0.id, label: "Para \($0.n)", level: 3) }
    }

    /// The contents sheet: the headings, then the paragraph marks.
    var contents: [JudgmentTOCEntry] { headings + paragraphMarks }

    /// The highest paragraph number.
    var lastParagraph: String? {
        blocks.compactMap(\.n).max { (JudgmentText.parseFloatPrefix($0) ?? 0) < (JudgmentText.parseFloatPrefix($1) ?? 0) }
    }

    /// Where "go to paragraph n" lands, and what to say when it is not exact.
    func paragraph(_ n: String) -> (blockID: String?, message: String?) {
        guard let i = JudgmentText.paragraphIndex(blocks, n) else {
            return (nil, lastParagraph.map { "There is no paragraph \(n). The last is \($0)." }
                ?? "This judgment has no numbered paragraphs.")
        }
        let b = blocks[i]
        return (b.id, b.n == JSCompat.trim(n) ? nil : "No paragraph \(n); showing \(b.n ?? "").")
    }

    // MARK: Find

    func find(_ query: String) {
        findQuery = query
        refreshFind()
    }

    private func refreshFind() {
        let found = JudgmentText.hits(in: blocks, query: findQuery)
        hits = found.hits
        hitsCapped = found.capped
        currentHit = hits.isEmpty ? nil : 0
    }

    /// The next (or previous) match, wrapping at either end.
    func step(_ direction: Int) {
        guard !hits.isEmpty else { return }
        guard let current = currentHit else {
            currentHit = direction >= 0 ? 0 : hits.count - 1
            return
        }
        currentHit = ((current + direction) % hits.count + hits.count) % hits.count
    }

    /// The block holding the current match.
    var currentHitBlockID: String? {
        guard let currentHit, hits.indices.contains(currentHit) else { return nil }
        return blocks[hits[currentHit].block].id
    }

    /// `3 of 41`, `No matches`, or nothing before two characters are typed.
    var findLabel: String {
        guard JSCompat.trim(findQuery).utf16.count >= 2 else { return "" }
        guard let currentHit, !hits.isEmpty else { return "No matches" }
        return "\(LibraryDisplay.fmtCount(currentHit + 1)) of \(LibraryDisplay.fmtCount(hits.count))\(hitsCapped ? "+" : "")"
    }

    /// The UTF-16 ranges of the matches inside one block.
    func hits(inBlock index: Int) -> [JudgmentText.Hit] { hits.filter { $0.block == index } }

    // MARK: Copying

    /// `<web>/library/doc/<id>#para-12`.
    func paragraphLink(_ blockID: String, apiBaseURL: URL) -> URL {
        LibraryLinks.doc(id: doc.id, anchor: blockID, apiBaseURL: apiBaseURL)
    }

    var citationLine: String { LibraryDisplay.citationLine(doc, header: header) }

    var title: String { LibraryDisplay.caseTitleText(doc, header: header) }
    var court: LibraryDisplay.Court {
        LibraryDisplay.courtInfo(LibraryDisplay.truthy(header?.court) ?? doc.court,
                                 label: LibraryDisplay.truthy(header?.courtLabel) ?? doc.courtLabel)
    }
    var caseNumber: String {
        let fromHeader = header.map { LibraryDisplay.caseNumberText(caseType: $0.caseType, caseNumber: $0.caseNumber) } ?? ""
        return fromHeader.isEmpty ? LibraryDisplay.caseNumberText(doc) : fromHeader
    }
    var decided: String? {
        guard let day = LibraryDisplay.truthy(header?.decidedOn) ?? LibraryDisplay.truthy(doc.decidedOn) else { return nil }
        return LibraryDisplay.isFutureDate(day) ? "\(LibraryDisplay.fmtDay(day)) (as printed)" : LibraryDisplay.fmtDay(day)
    }
    var bench: [String] {
        if let list = header?.bench, !list.isEmpty { return list }
        return (doc.bench ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    /// The neutral citation first, then the reported ones, each once.
    var citations: [String] {
        var seen = Set<String>()
        let neutral = LibraryDisplay.truthy(header?.neutralCitation) ?? LibraryDisplay.truthy(doc.neutralCitation)
        return ([neutral] + (header?.citations ?? []).map { Optional($0) }).compactMap { LibraryDisplay.truthy($0) }
            .filter { seen.insert($0).inserted }
    }
    var lengthText: String? {
        guard let words = stats?.words, words > 0 else { return nil }
        let minutes = max(1, Int(JSCompat.round(Double(words) / 230)))
        return (stats?.paragraphs.map { "\(LibraryDisplay.fmtCount($0)) paragraphs · " } ?? "") + "\(minutes) min read"
    }
}

// MARK: - The Act page

/// An Act and everything made under it, a tab each (`act/ActPage.jsx`, `act/actFiles.js`).
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class LibraryActViewModel {

    let id: Int
    private(set) var seed: LibraryDoc?
    private(set) var bundle: LibraryActBundle?
    private(set) var state: LoadState = .idle
    private(set) var selectedTabKey: String?
    private var chosen: [String: Int] = [:]
    private var files: [Int: LibraryFileViewModel] = [:]

    private let service: any LibraryProviding

    init(id: Int, seed: LibraryDoc? = nil, service: any LibraryProviding) {
        self.id = id
        self.seed = seed
        self.service = service
    }

    /// `/act` said there is no such document, or that it is not part of the Bare Acts.
    private(set) var isNotFound = false

    func load() async {
        state = .loading
        isNotFound = false
        do {
            bundle = try await service.act(id: id)
            state = .loaded
        } catch {
            isNotFound = error as? LibraryError == .notFound || error as? LibraryError == .notAnAct
            state = .failed(LoadFailure(error))
        }
    }

    var act: LibraryDoc? { bundle?.act ?? seed }
    var kind: String { bundle?.resolvedKind ?? "act" }

    /// The tabs as the page shows them: the first named for what the Act is; an Act known only by
    /// its amending Acts gets one chronological list (`tabsForView`).
    var tabs: [LibraryActTab] {
        guard let bundle else { return [] }
        if kind == "amendments" {
            let amend = bundle.tabs.first { $0.key == "amendments" }
            let docs = JSCompat.stableSorted((bundle.tabs.first?.docs ?? []) + (amend?.docs ?? [])) { a, b in
                let y = (a.year ?? 9999) - (b.year ?? 9999)
                if y != 0 { return y }
                let ta = a.title ?? "", tb = b.title ?? ""
                return ta < tb ? -1 : (ta > tb ? 1 : 0)
            }
            let rest = bundle.tabs.filter { $0.key != "act" && $0.key != "amendments" }
            return [LibraryActTab(key: "amendments", label: "Amending Acts", count: docs.count, docs: docs)] + rest
        }
        return bundle.tabs.map { t in
            t.key == "act" ? LibraryActTab(key: t.key, label: LibraryDisplay.actTabLabel(bundle.act, kind: kind), count: t.count, docs: t.docs) : t
        }
    }

    /// The tab open: the reader's, else the bundle's own (opening a rule's id opens its tab).
    var activeTab: LibraryActTab? {
        let all = tabs
        var key = selectedTabKey ?? "act"
        if selectedTabKey == nil, let s = bundle?.selectedTab, s != "act", s != "editions" { key = s }
        if kind == "amendments", key == "act" { key = "amendments" }
        return all.first { $0.key == key } ?? all.first
    }

    /// Few tabs fit a segmented control; more scroll as chips.
    var usesSegments: Bool { tabs.count <= 4 }

    func select(tab key: String) { selectedTabKey = key }

    /// What a tab's reading pane can show: the Act tab also offers its other editions.
    func choices(for tab: LibraryActTab) -> [LibraryDoc] {
        guard tab.key == "act" else { return tab.docs }
        return tab.docs + (tabs.first { $0.key == "editions" }?.docs ?? [])
    }

    /// The instrument a tab opens on: the reader's choice, else the one asked for, else the first.
    func currentDoc(for tab: LibraryActTab) -> LibraryDoc? {
        let pool = choices(for: tab)
        if let picked = chosen[tab.key], let doc = pool.first(where: { $0.id == picked }) { return doc }
        if let bundle {
            let mine = bundle.selectedTab == tab.key
                || (tab.key == "amendments" && kind == "amendments")
                || (tab.key == "act" && bundle.selectedTab == "editions")
            if mine, let hit = pool.first(where: { $0.id == bundle.selectedId }) { return hit }
        }
        return tab.docs.first
    }

    var currentDoc: LibraryDoc? { activeTab.flatMap(currentDoc(for:)) }

    func select(doc: LibraryDoc) {
        guard let tab = activeTab else { return }
        chosen[tab.key] = doc.id
    }

    func latestID(in tab: LibraryActTab) -> Int? {
        tab.key == "editions" || tab.key == "related" ? nil : LibraryDisplay.latestID(tab.docs)
    }

    /// The other editions, for the edition choice on the Act tab.
    var editions: [LibraryDoc] { tabs.first { $0.key == "editions" }?.docs ?? [] }

    static func editionLabel(_ doc: LibraryDoc, index: Int) -> String {
        ["Edition \(index + 2)", LibraryDisplay.copySource(doc), LibraryDisplay.actSize(doc.fileSize)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The file view of a document, kept so returning to it does not fetch it again.
    func file(for doc: LibraryDoc) -> LibraryFileViewModel {
        if let existing = files[doc.id] { return existing }
        let model = LibraryFileViewModel(docID: doc.id, service: service)
        files[doc.id] = model
        return model
    }

    // MARK: Header

    var title: String {
        if let g = LibraryDisplay.truthy(bundle?.groupTitle) { return g }
        return act.map { LibraryDisplay.splitTitle($0).name } ?? ""
    }

    /// `Central Act · 1860 · IPC`.
    var kicker: [String] {
        guard let act else { return [] }
        let j = LibraryDisplay.jurisdictionOf(act)
        let year = LibraryDisplay.splitTitle(act).year
        var parts: [String?] = []
        if kind == "orphan", let t = act.docType, t != "act" { parts.append(LibraryDisplay.actKicker(act)) }
        parts.append(kind == "amendments" ? "Amending Acts" : (j.central ? "Central Act" : (j.value == "none" ? nil : j.label)))
        if kind == "amendments", j.value != "none" { parts.append(j.label) }
        if kind != "amendments" { parts.append(year) }
        parts.append((act.aliases ?? bundle?.act.aliases)?.first)
        return parts.compactMap { LibraryDisplay.truthy($0) }
    }

    var isRepealed: Bool { act.map(LibraryDisplay.isRepealed) ?? false }

    /// `9 rules · 25 amendments`.
    var holds: String {
        guard let bundle else { return "" }
        if kind == "amendments" {
            let n = bundle.tabs.filter { $0.key == "act" || $0.key == "amendments" }.reduce(0) { $0 + $1.count }
            return "\(LibraryDisplay.fmtCount(n)) amending Acts"
        }
        let counts = Dictionary(bundle.tabs.map { ($0.key, $0.count) }, uniquingKeysWith: { a, _ in a })
        return LibraryDisplay.countParts(counts).prefix(3).joined(separator: " · ")
    }

    var notice: String? {
        if kind == "orphan" { return "Its Act is not in the library" }
        if kind == "amendments" { return "The Act itself is not in the library" }
        return nil
    }

    var failureTitle: String {
        isNotFound ? "There is no such Act" : "This Act could not be opened"
    }

    /// An instrument's facts in a list row.
    func rowFacts(_ doc: LibraryDoc, in tab: LibraryActTab) -> [String] {
        var out: [String] = []
        if tab.key == "editions" { out.append(LibraryDisplay.copySource(doc)) }
        if tab.key != "amendments", tab.key != "editions", let y = doc.year, y != 0 { out.append(String(y)) }
        let size = LibraryDisplay.actSize(doc.fileSize)
        if !size.isEmpty { out.append(size) }
        if let copies = doc.copies, !copies.isEmpty { out.append("\(copies.count + 1) copies") }
        return out
    }
}
