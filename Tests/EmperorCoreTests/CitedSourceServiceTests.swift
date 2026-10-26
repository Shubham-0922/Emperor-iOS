import XCTest
@testable import EmperorCore

/// `/resolve-file` and `/page-words` on the wire, through the real client.
final class CitedSourceServiceTests: XCTestCase {

    /// Before each test, not only after: see `HTTPStub.reset`.
    override func setUp() {
        super.setUp()
        HTTPStub.reset()
    }

    override func tearDown() {
        HTTPStub.reset()
        super.tearDown()
    }

    private func service() async -> CitedSourceService {
        let client = APIClient(
            config: APIConfig(baseURL: URL(string: "https://example.test/api")!),
            session: HTTPStub.session())
        await client.setCredentials(Credentials(token: "tok", userID: 7))
        return CitedSourceService(client: client)
    }

    func testResolveSendsTheNameQuoteAndMatter() async throws {
        HTTPStub.always(.json(
            #"{"found":true,"folderName":"_projects/12/Pleadings","fileName":"Lease_Agreement.pdf","page":12,"quoteStatus":"verified"}"#))
        let resolved = try await service().resolve(
            name: "Lease_Agreement.pdf", quote: "the lessee shall pay", projectID: "12")

        let request = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.path, "/api/resolve-file")
        XCTAssertEqual(request.queryItems, [
            "userId": "7", "name": "Lease_Agreement.pdf", "quote": "the lessee shall pay", "projectId": "12",
        ])
        XCTAssertEqual(request.header("Authorization"), "Bearer tok")
        XCTAssertEqual(resolved.page, 12)
        XCTAssertEqual(resolved.quoteStatus, .verified)
        XCTAssertEqual(
            resolved.attachment,
            ChatAttachment(name: "Lease_Agreement.pdf", folderName: "_projects/12/Pleadings"))
    }

    /// Outside a matter the id is not sent at all, and nor is an absent quote.
    func testNoMatterAndNoQuoteAreLeftOut() async throws {
        HTTPStub.always(.json(#"{"found":true,"folderName":".","fileName":"Notes.pdf","page":null,"quoteStatus":null}"#))
        let resolved = try await service().resolve(name: "Notes.pdf", quote: nil, projectID: nil)

        XCTAssertEqual(HTTPStub.lastRequest?.queryItems, ["userId": "7", "name": "Notes.pdf"])
        XCTAssertNil(resolved.page)
        XCTAssertNil(resolved.quoteStatus)
        XCTAssertEqual(resolved.attachment?.folderName, ".", "the root is kept as the server spells it")
    }

    func testNotFoundHasNoDocument() async throws {
        HTTPStub.always(.json(#"{"found":false}"#))
        let resolved = try await service().resolve(name: "Gone.pdf", quote: nil, projectID: nil)
        XCTAssertFalse(resolved.found)
        XCTAssertNil(resolved.attachment)
    }

    func testEveryQuoteStatusIsRead() throws {
        func status(_ raw: String) throws -> QuoteStatus? {
            try JSONDecoder().decode(
                ResolvedFile.self,
                from: Data(#"{"found":true,"fileName":"a.pdf","quoteStatus":"\#(raw)"}"#.utf8)).quoteStatus
        }
        XCTAssertEqual(try status("verified"), .verified)
        XCTAssertEqual(try status("mismatch"), .mismatch)
        XCTAssertEqual(try status("unlocated"), .unlocated)
        XCTAssertEqual(try status("too_short"), .tooShort)
        XCTAssertNil(try status("something_new"), "a verdict this client does not know is no verdict")
    }

    func testARefusalIsTheServersSentence() async {
        HTTPStub.always(.json(#"{"success":false,"error":"Forbidden"}"#, status: 403))
        do {
            _ = try await service().resolve(name: "a.pdf", quote: nil, projectID: nil)
            XCTFail("a 403 must throw")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 403, message: "Forbidden"))
        }
    }

    func testAServerFaultWithOnlyAnErrorKeyThrows() async {
        HTTPStub.always(.json(#"{"error":"ENOENT: no such file"}"#, status: 500))
        do {
            _ = try await service().resolve(name: "a.pdf", quote: nil, projectID: nil)
            XCTFail("a 500 must throw")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 500, message: "ENOENT: no such file"))
        }
    }

    func testPageWordsDecodeTheSixPartTuples() async throws {
        HTTPStub.always(.json("""
            {"status":"ready","page":{"page":2,"w":595.3,"h":841.9,"rot":0,"lang":"eng+hin",
             "words":[[72.1,100,110.5,112.2,"The",96],[115,100,160,112,"lessee",88],[1,2,3],[1,2,3,4,5,6]]}}
            """))
        let words = try await service().pageWords(folderName: "", fileName: "Lease.pdf", page: 2)

        XCTAssertEqual(HTTPStub.lastRequest?.path, "/api/page-words")
        XCTAssertEqual(HTTPStub.lastRequest?.queryItems, [
            "userId": "7", "folderName": ".", "fileName": "Lease.pdf", "page": "2",
        ])
        XCTAssertEqual(words.status, .ready)
        XCTAssertEqual(words.words.map(\.text), ["The", "lessee"], "malformed entries are skipped")
        XCTAssertEqual(words.words.first?.box, QuoteBox(x0: 72.1, y0: 100, x1: 110.5, y1: 112.2))
    }

    func testAPageWithItsOwnTextHasNoWords() async throws {
        HTTPStub.always(.json(#"{"status":"ready","page":null}"#))
        let ready = try await service().pageWords(folderName: "Bakshi", fileName: "a.pdf", page: 1)
        XCTAssertEqual(ready.status, .ready)
        XCTAssertTrue(ready.words.isEmpty)

        HTTPStub.always(.json(#"{"status":"pending","page":null}"#))
        let pending = try await service().pageWords(folderName: "Bakshi", fileName: "a.pdf", page: 1)
        XCTAssertEqual(pending.status, .pending)
        XCTAssertEqual(HTTPStub.lastRequest?.queryItems["folderName"], "Bakshi")
    }
}

/// The viewer's search order, its sentences, and the word runs of a page's text.
final class CitedSourceViewerRulesTests: XCTestCase {

    func testTheCitedPageIsSearchedFirstThenEitherSide() {
        XCTAssertEqual(CitedSource.searchOrder(target: 5, pageCount: 10), [5, 4, 6])
        XCTAssertEqual(CitedSource.searchOrder(target: 1, pageCount: 10), [1, 2])
        XCTAssertEqual(CitedSource.searchOrder(target: 10, pageCount: 10), [10, 9])
        XCTAssertEqual(CitedSource.searchOrder(target: 40, pageCount: 3), [3, 2], "brought into the document")
        XCTAssertEqual(CitedSource.searchOrder(target: 0, pageCount: 3), [1, 2])
        XCTAssertEqual(CitedSource.searchOrder(target: 1, pageCount: 1), [1])
        XCTAssertEqual(CitedSource.searchOrder(target: 2, pageCount: 0), [])
    }

    func testTheNotesAreTheWebsSentences() {
        XCTAssertNil(CitedSource.note(target: 4, foundOn: 4, pending: false))
        XCTAssertEqual(
            CitedSource.note(target: 4, foundOn: 5, pending: true),
            "The quoted words are on page 5; the citation said page 4.")
        XCTAssertEqual(
            CitedSource.note(target: 4, foundOn: nil, pending: true),
            "This scanned document is still being prepared for highlighting. Showing the cited page; try again in a minute or two.")
        XCTAssertEqual(
            CitedSource.note(target: 4, foundOn: nil, pending: false),
            "Couldn’t find the quoted words on page 4. Showing the cited page.")
    }

    func testWordRunsCarryTheirUTF16Ranges() {
        let runs = CitedSource.wordRuns("  The\u{00A0}lessee\n—shall पाय 😀x ")
        XCTAssertEqual(runs.map(\.word), ["The", "lessee", "—shall", "पाय", "😀x"])
        XCTAssertEqual(runs.map(\.range.location), [2, 6, 13, 20, 24])
        XCTAssertEqual(runs.last?.range.length, 3, "an emoji is two UTF-16 units")
        XCTAssertTrue(CitedSource.wordRuns(" \n ").isEmpty)
    }

    /// A box from `/page-words` is placed on the page as shown, from the top; a PDF annotation
    /// is placed on the page as stored, from the bottom.
    func testBoxesConvertToPageSpaceForEveryRotation() {
        let box = QuoteBox(x0: 10, y0: 20, x1: 30, y1: 25)
        func at(_ rotation: Int) -> QuoteBox {
            CitedSource.pageSpace(box, cropX: 0, cropY: 0, cropWidth: 600, cropHeight: 800, rotation: rotation)
        }
        XCTAssertEqual(at(0), QuoteBox(x0: 10, y0: 775, x1: 30, y1: 780))
        XCTAssertEqual(at(90), QuoteBox(x0: 20, y0: 10, x1: 25, y1: 30))
        XCTAssertEqual(at(180), QuoteBox(x0: 570, y0: 20, x1: 590, y1: 25))
        XCTAssertEqual(at(270), QuoteBox(x0: 575, y0: 770, x1: 580, y1: 790))
        XCTAssertEqual(at(-90), at(270))
        XCTAssertEqual(
            CitedSource.pageSpace(box, cropX: 5, cropY: 7, cropWidth: 600, cropHeight: 800, rotation: 0),
            QuoteBox(x0: 15, y0: 782, x1: 35, y1: 787))
    }
}
