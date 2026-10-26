import XCTest
@testable import EmperorCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The catalogue's answers decoded, its errors mapped, and the requests this client builds.
final class LibraryWireTests: XCTestCase {

    override func setUp() {
        super.setUp()
        HTTPStub.reset()
    }

    override func tearDown() {
        HTTPStub.reset()
        super.tearDown()
    }

    private func wire<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: try parityFixture("library", "wire/\(name)"))
    }

    private func makeService(retry: TimeInterval = 0) async -> LibraryService {
        let client = APIClient(config: APIConfig(baseURL: URL(string: "https://example.test/api")!),
                               session: HTTPStub.session())
        await client.setCredentials(Credentials(token: "tok", userID: 7))
        return LibraryService(client: client, busyRetryDelay: retry)
    }

    // MARK: - Decoding

    func testCategoriesAndFacets() throws {
        let categories = try wire("categories", as: LibraryCategoriesResponse.self).categories ?? []
        XCTAssertEqual(categories.map(\.key), ["bare-acts", "case-law", "books-and-law-reports"])
        XCTAssertEqual(categories[1].count, 271_480)

        let facets = try XCTUnwrap(wire("facets", as: LibraryFacetsResponse.self).facets)
        XCTAssertEqual(facets.courts.map(\.value), ["delhi", "supremecourt"])
        XCTAssertEqual(facets.yearRange, LibraryYearRange(min: 1950, max: 2025))
        XCTAssertEqual(facets.series.last?.yearMin, nil)
        XCTAssertEqual(facets.publishers.first?.displayLabel, "SEBI")
        XCTAssertEqual(facets.jurisdictions.first?.displayLabel, "Central")
        XCTAssertEqual(facets.sorts.map(\.value), ["date_desc", "date_asc", "court"])
        XCTAssertEqual(LibraryDisplay.orderCourts(facets.courts).map(\.value), ["supremecourt", "delhi"])
    }

    func testBrowseRowsKeepTheExtensionDotAndReadAbsentAndNull() throws {
        let page = try wire("browse", as: LibraryPage.self)
        XCTAssertEqual(page.total, 45)
        XCTAssertEqual(page.pageCount, 3)
        let judgment = page.items[0]
        XCTAssertEqual(judgment.ext, ".txt")
        XCTAssertTrue(judgment.isText)
        XCTAssertFalse(judgment.isPDF)
        XCTAssertNil(judgment.jurisdiction, "null reads as absent")
        XCTAssertEqual(judgment.bench, "A.K. Patnaik, Swatanter Kumar")
        XCTAssertNotNil(judgment.decidedDay)
        XCTAssertEqual(WireDate.dayKey(try XCTUnwrap(judgment.decidedDay)), "2012-10-31")
        XCTAssertFalse(judgment.coverWanted, "a text judgment has no cover image")

        let future = page.items[1]
        XCTAssertEqual(future.anomalies?.first?.kind, "future_date")
        XCTAssertTrue(future.isDateUnclear(today: "2026-10-27"))
        XCTAssertNil(future.snippet)

        let book = page.items[2]
        XCTAssertEqual(book.volume, "12", "a number in a text column is kept as text")
        XCTAssertEqual(book.issue, "615")
        XCTAssertEqual(book.isAmendment, false)
        XCTAssertTrue(book.isPDF)
        XCTAssertTrue(book.coverWanted)
        XCTAssertEqual(book.cover, "web")
    }

    func testGroupedSearchAndBodySearch() throws {
        let grouped = try wire("grouped", as: LibraryGroupedResults.self)
        XCTAssertEqual(grouped.groups.map(\.category), ["bare-acts", "case-law"])
        XCTAssertTrue(try XCTUnwrap(grouped.groups.first?.items.first).opensAsAct)
        XCTAssertFalse(try XCTUnwrap(grouped.groups.last?.items.first).opensAsAct)

        let search = try wire("search", as: LibraryPage.self)
        XCTAssertEqual(search.totalIsCapped, true)
        XCTAssertEqual(search.items.first?.snippet?.term, "bail")
        XCTAssertEqual(search.items.first?.snippet?.before, true)
        XCTAssertNil(search.items.last?.snippet)
        XCTAssertEqual(search.index?.pending, 71_480)
        XCTAssertNil(search.sort)
    }

    func testFoldersActShelvesAndDoc() throws {
        let folders = try wire("folders", as: LibraryActIndexPage.self)
        XCTAssertEqual(folders.items.first?.tabCounts?["rules"], 2)
        XCTAssertEqual(folders.items.first?.aliases, ["IPC"])
        XCTAssertEqual(folders.letters.first?.letter, "#")
        XCTAssertEqual(folders.jurisdictions.last?.value, "none")

        let act = try wire("act", as: LibraryActBundle.self)
        XCTAssertEqual(act.resolvedKind, "act")
        XCTAssertEqual(act.selectedTab, "rules")
        XCTAssertEqual(act.tabs.map(\.key), ["act", "rules", "amendments"])
        XCTAssertEqual(act.tabs[1].docs.last?.repealed, true)
        XCTAssertEqual(act.tabs[1].docs.first?.copies, [3001])

        let shelf = try wire("shelf", as: LibraryShelf.self)
        XCTAssertEqual(shelf.day, 20_261_027)
        XCTAssertEqual(shelf.items.first?.hasCover, true)

        let series = try wire("series", as: LibrarySeriesShelves.self)
        XCTAssertEqual(series.seriesTotal, 41)
        XCTAssertEqual(series.shelves.first?.series, "All India Reporter")
        XCTAssertEqual(series.standalone?.items.first?.coverWanted, false, "cover: none never asks")

        let doc = try wire("doc", as: LibraryDocResponse.self).doc
        XCTAssertEqual(doc.doc.id, 2479)
        XCTAssertEqual(doc.doc.hasFile, false)
        XCTAssertEqual(doc.childGroups.first?.items.count, 1)
        XCTAssertEqual(doc.editions.map(\.id), [3001])
        XCTAssertEqual(doc.parent?.id, 2478)
    }

    func testJudgmentBlocksIncludingAnUnknownType() throws {
        let j = try wire("judgment", as: LibraryJudgment.self)
        XCTAssertEqual(j.header?.bench ?? [], ["A.K. Patnaik", "Swatanter Kumar"])
        XCTAssertNil(j.header?.citedByCount)
        XCTAssertEqual(j.blocks.count, 9)
        XCTAssertEqual(j.blocks[0].kind, .cause)
        XCTAssertEqual(j.blocks[0].searchableText, "SEETHAMMA ... Appellant\nVersus\nSTATE ... Respondent")
        XCTAssertEqual(j.blocks[1].level, 1)
        XCTAssertEqual(j.blocks[3].n, "2", "a paragraph number sent as a number reads as text")
        XCTAssertEqual(j.blocks[5].marker, "(a)")
        XCTAssertEqual(j.blocks[6].searchableText, "a | b\nc | d")
        XCTAssertEqual(j.blocks[7].role, "date")
        XCTAssertEqual(j.blocks[8].kind, .unknown("footnote"))
        XCTAssertEqual(j.toc.map(\.level), [1, 3])
        XCTAssertEqual(j.stats?.words, 460)
        XCTAssertEqual(LibraryDisplay.citationLine(try XCTUnwrap(j.doc), header: j.header),
                       "Seethamma v. State of Karnataka, 2012 INSC 410 (Supreme Court, 31 Oct 2012)")
    }

    // MARK: - Errors

    func testErrorCodesMapToLibraryErrors() throws {
        let cases = try XCTUnwrap(JSONSerialization.jsonObject(with: parityFixture("library", "wire/errors")) as? [[String: Any]])
        for c in cases {
            let status = try XCTUnwrap(c["status"] as? Int)
            let body = try JSONSerialization.data(withJSONObject: c["body"] as Any)
            let mapped = LibraryError.from(APIError.classify(status: status, body: body))
            let expect = c["expect"] as? String ?? ""
            switch expect {
            case "catalogueUnavailable": XCTAssertEqual(mapped as? LibraryError, .catalogueUnavailable)
            case "notAnAct": XCTAssertEqual(mapped as? LibraryError, .notAnAct)
            case "notFound": XCTAssertEqual(mapped as? LibraryError, .notFound)
            case "fileMissing": XCTAssertEqual(mapped as? LibraryError, .fileMissing)
            case "tooLarge": XCTAssertEqual(mapped as? LibraryError, .tooLarge)
            case "busy": XCTAssertEqual(mapped as? LibraryError, .busy)
            case "missingQuery": XCTAssertEqual(mapped as? LibraryError, .missingQuery)
            case "other": XCTAssertEqual(mapped as? LibraryError, .other("library_failed"))
            case "invalidCredentials": XCTAssertEqual(mapped as? APIError, .invalidCredentials, "a 401 stays a sign-out")
            default: XCTFail("unknown expectation \(expect)")
            }
        }
        XCTAssertEqual(LibraryError.catalogueUnavailable.message, "The catalogue has not been built on this server yet.")
    }

    // MARK: - Requests

    func testFiltersDropEmptyValues() {
        var f = LibraryFilters(category: "case-law", q: "  ", sort: "", page: 2, pageSize: 20)
        f.court = ""
        f.yearFrom = 2015
        f.publisher = nil
        XCTAssertEqual(f.query, ["category": "case-law", "page": "2", "pageSize": "20", "yearFrom": "2015"])
        f.court = "delhi"
        f.letter = "A"
        XCTAssertEqual(f.activeFilterCount, 3)
        XCTAssertEqual(LibraryActQuery(letter: "", q: "pmla", kind: "all").query, ["q": "pmla", "kind": "all"])
    }

    func testCoverPathIsBuiltFromTheIdNotTheRowsUrl() throws {
        var doc = LibraryDoc(id: 31, title: "x", category: "books-and-law-reports")
        doc.coverUrl = "/api/library/catalogue/cover?id=31&w=320"
        doc.ext = ".pdf"
        XCTAssertEqual(LibraryCovers.path(id: doc.id, width: 640, web: false, attempt: 0),
                       "/library/catalogue/cover?id=31&w=640")
        XCTAssertEqual(LibraryCovers.path(id: doc.id, width: 160, web: true, attempt: 2),
                       "/library/catalogue/cover?id=31&w=160&src=web&r=2")
        XCTAssertEqual(LibraryCovers.width(forPoints: 110, scale: 1), 160)
        XCTAssertEqual(LibraryCovers.width(forPoints: 110, scale: 3), 640)
        XCTAssertEqual(LibraryCovers.width(forPoints: 900, scale: 2), 640)
        XCTAssertEqual(LibraryCovers.result(status: 200, body: Data([1]), retryAfter: nil), .image(Data([1])))
        XCTAssertEqual(LibraryCovers.result(status: 404, body: Data(#"{"error":"cover_pending"}"#.utf8), retryAfter: "5"),
                       .pending(retryAfter: 5))
        XCTAssertEqual(LibraryCovers.result(status: 404, body: Data(#"{"error":"no_cover"}"#.utf8), retryAfter: nil), .none)
        XCTAssertEqual(LibraryCovers.result(status: 503, body: Data(), retryAfter: nil), .pending(retryAfter: 1.5))
    }

    func testRoutesAndQueriesOnTheWire() async throws {
        let service = await makeService()
        HTTPStub.respond { request in
            switch request.path {
            case "/api/library/catalogue/browse":
                return .json(#"{"success":true,"groups":[],"items":[],"total":0,"page":1,"pageSize":6}"#)
            case "/api/library/catalogue/cover":
                return HTTPStub.Reply(status: 200, body: Data([0xFF, 0xD8]), headers: ["Content-Type": "image/jpeg"])
            case "/api/library/catalogue/file":
                return request.httpMethod == "HEAD"
                    ? HTTPStub.Reply(status: 404, body: Data(), headers: [:])
                    : .text("hello")
            default:
                return .json(#"{"error":"unknown_library_route"}"#, status: 404)
            }
        }
        _ = try await service.titleSearch(q: " penal ", perCategory: 6)
        let grouped = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(grouped.queryItems["groupBy"], "category")
        XCTAssertEqual(grouped.queryItems["q"], "penal")
        XCTAssertEqual(grouped.queryItems["pageSize"], "6")
        XCTAssertEqual(grouped.header("Authorization"), "Bearer tok")

        let cover = await service.cover(id: 31, width: 320, web: false, attempt: 0)
        XCTAssertEqual(cover, .image(Data([0xFF, 0xD8])))
        XCTAssertEqual(HTTPStub.lastRequest?.queryItems["w"], "320")

        let head = try await service.fileHead(id: 999)
        XCTAssertEqual(head.status, 404)
        XCTAssertEqual(HTTPStub.lastRequest?.httpMethod, "HEAD")

        let text = try await service.file(id: 19655, prefer: "text")
        XCTAssertEqual(String(decoding: text, as: UTF8.self), "hello")
        XCTAssertEqual(HTTPStub.lastRequest?.queryItems["prefer"], "text")

        do {
            _ = try await service.act(id: 5)
            XCTFail("an unknown route is an error")
        } catch {
            XCTAssertEqual(error as? LibraryError, .other("unknown_library_route"))
        }
    }

    func testABusySearchIsAskedOnceMore() async throws {
        let service = await makeService(retry: 0)
        let counter = Counter()
        HTTPStub.respond { _ in
            counter.next() == 1
                ? .json(#"{"error":"search_busy"}"#, status: 503)
                : .json(#"{"success":true,"items":[],"total":0,"page":1,"pageSize":20,"mode":"body"}"#)
        }
        let page = try await service.searchBodies(LibraryFilters(category: "case-law", q: "bail"))
        XCTAssertEqual(page.total, 0)
        XCTAssertEqual(HTTPStub.seen.count, 2)

        HTTPStub.reset()
        HTTPStub.always(.json(#"{"error":"search_busy"}"#, status: 503))
        do {
            _ = try await service.searchBodies(LibraryFilters(category: "case-law", q: "bail"))
            XCTFail("busy twice is an error")
        } catch {
            XCTAssertEqual(error as? LibraryError, .busy)
        }
        XCTAssertEqual(HTTPStub.seen.count, 2, "only one retry")
    }

    func testCatalogueUnavailableIsItsOwnError() async throws {
        let service = await makeService()
        HTTPStub.always(.json(#"{"error":"catalogue_unavailable","message":"x","hint":"y"}"#, status: 503))
        do {
            _ = try await service.categories()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? LibraryError, .catalogueUnavailable)
        }
    }

    func testWebLinks() {
        let base = URL(string: "https://app.example.test/api")!
        XCTAssertEqual(LibraryLinks.doc(id: 12, anchor: "para-3", apiBaseURL: base).absoluteString,
                       "https://app.example.test/library/doc/12#para-3")
        XCTAssertEqual(LibraryLinks.act(id: 2478, apiBaseURL: base).absoluteString,
                       "https://app.example.test/library/act/2478")
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.withLock { n += 1; return n } }
}
