import Foundation
@testable import EmperorCore

/// A catalogue in memory. Every answer can be replaced, failed, or held back until released.
final class FakeLibrary: LibraryProviding, @unchecked Sendable {
    private let lock = NSLock()

    var categoriesResult: Result<[LibraryCategory], Error> = .success([])
    var facetsByCategory: [String: LibraryFacets] = [:]
    var facetsError: Error?
    /// Answers `browse` from the filters; the default echoes an empty page.
    var browseHandler: (LibraryFilters) throws -> LibraryPage = { _ in LibraryPage() }
    var searchHandler: (LibraryFilters) throws -> LibraryPage = { _ in LibraryPage() }
    var titleSearchResult: Result<LibraryGroupedResults, Error> = .success(LibraryGroupedResults())
    var actIndexHandler: (LibraryActQuery) throws -> LibraryActIndexPage = { _ in LibraryActIndexPage() }
    var actResult: Result<LibraryActBundle, Error> = .failure(LibraryError.notFound)
    var judgmentResult: Result<LibraryJudgment, Error> = .failure(LibraryError.notFound)
    var shelves: [String: [LibraryDoc]] = [:]
    var shelfError: Error?
    var seriesShelvesResult: Result<LibrarySeriesShelves, Error> = .success(LibrarySeriesShelves())
    var docResult: (Int) throws -> LibraryDocDetail = { LibraryDocDetail(doc: LibraryDoc(id: $0)) }
    var headResult: (Int) -> (status: Int, length: Int?) = { _ in (200, 100) }
    var fileResult: (Int, String?) throws -> Data = { _, _ in Data("%PDF-1.4".utf8) }
    var coverResults: [Int: [LibraryCoverResult]] = [:]
    /// Called before `browse`/`search` answer, so a test can hold an answer back.
    var gate: (@Sendable (LibraryFilters) async -> Void)?

    private(set) var calls: [String] = []
    private(set) var browseCalls: [LibraryFilters] = []
    private(set) var searchCalls: [LibraryFilters] = []
    private(set) var actIndexCalls: [LibraryActQuery] = []
    private(set) var coverCalls: [(id: Int, width: Int, attempt: Int)] = []
    private(set) var fileCalls: [(id: Int, prefer: String?)] = []

    private func record(_ name: String) { lock.withLock { calls.append(name) } }
    func count(_ name: String) -> Int { lock.withLock { calls.filter { $0 == name }.count } }

    func categories() async throws -> [LibraryCategory] {
        record("categories")
        return try categoriesResult.get()
    }

    func facets(_ category: String) async throws -> LibraryFacets {
        record("facets")
        if let facetsError { throw facetsError }
        return facetsByCategory[category] ?? LibraryFacets()
    }

    func browse(_ filters: LibraryFilters) async throws -> LibraryPage {
        record("browse")
        lock.withLock { browseCalls.append(filters) }
        if let gate { await gate(filters) }
        return try browseHandler(filters)
    }

    func titleSearch(q: String, perCategory: Int) async throws -> LibraryGroupedResults {
        record("titleSearch")
        return try titleSearchResult.get()
    }

    func searchBodies(_ filters: LibraryFilters) async throws -> LibraryPage {
        record("search")
        lock.withLock { searchCalls.append(filters) }
        if let gate { await gate(filters) }
        return try searchHandler(filters)
    }

    func searchStatus() async throws -> LibrarySearchIndex { LibrarySearchIndex(ready: true) }

    func actIndex(_ query: LibraryActQuery) async throws -> LibraryActIndexPage {
        record("actIndex")
        lock.withLock { actIndexCalls.append(query) }
        return try actIndexHandler(query)
    }

    func act(id: Int) async throws -> LibraryActBundle {
        record("act")
        return try actResult.get()
    }

    func judgment(id: Int) async throws -> LibraryJudgment {
        record("judgment")
        return try judgmentResult.get()
    }

    func shelf(category: String, limit: Int) async throws -> LibraryShelf {
        record("shelf:\(category)")
        if let shelfError { throw shelfError }
        return LibraryShelf(category: category, items: shelves[category] ?? [])
    }

    func seriesShelves(limit: Int, per: Int) async throws -> LibrarySeriesShelves {
        record("seriesShelves")
        return try seriesShelvesResult.get()
    }

    func doc(id: Int) async throws -> LibraryDocDetail {
        record("doc")
        return try docResult(id)
    }

    func fileHead(id: Int) async throws -> (status: Int, length: Int?) {
        record("head")
        return headResult(id)
    }

    func file(id: Int, prefer: String?) async throws -> Data {
        record("file")
        lock.withLock { fileCalls.append((id, prefer)) }
        return try fileResult(id, prefer)
    }

    func cover(id: Int, width: Int, web: Bool, attempt: Int) async -> LibraryCoverResult {
        lock.withLock {
            coverCalls.append((id, width, attempt))
            var queue = coverResults[id] ?? []
            let next = queue.isEmpty ? LibraryCoverResult.none : queue.removeFirst()
            coverResults[id] = queue
            return next
        }
    }
}

extension LibraryDoc {
    /// A row for tests.
    static func sample(_ id: Int, _ title: String = "Indian Contract Act, 1872", category: String = "case-law",
                       decidedOn: String? = nil, ext: String = ".pdf") -> LibraryDoc {
        var doc = LibraryDoc(id: id, title: title, category: category)
        doc.decidedOn = decidedOn
        doc.ext = ext
        doc.render = ext == ".pdf" ? "pdf" : "text"
        return doc
    }
}
