import XCTest
@testable import EmperorCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The bytes filing assembly puts on the wire, and how its answers are read.
final class FilingWireTests: XCTestCase {

    private static let config = APIConfig(baseURL: URL(string: "https://example.test/api")!)

    /// Before each test, not only after — see `HTTPStub.reset`.
    override func setUp() {
        super.setUp()
        HTTPStub.reset()
    }

    override func tearDown() {
        HTTPStub.reset()
        super.tearDown()
    }

    private func service() async -> FilingService {
        let client = APIClient(config: Self.config, session: HTTPStub.session())
        await client.setCredentials(Credentials(token: "tok-abc", userID: 42))
        return FilingService(client: client)
    }

    private static let row = #"{"id":3,"user_id":"42","draft_id":null,"chat_id":"c1","mark":"P-3","title":"Order","source_file_path":"/storage/42/Bakshi/Order.pdf","treatment":"typed","sort_order":3,"verify_status":"pending","page_from":null,"page_to":null,"created_at":1790000000000,"updated_at":1790000000000,"pasted_at":null,"duplicate_of":"P-1"}"#

    // MARK: - Reads

    func testDraftsAreReadWithTheCallerAndDecodeBothDateShapes() async throws {
        HTTPStub.always(.json(#"{"success":true,"drafts":[{"id":"canvas_1","title":"Writ","type":"doc","created_at":"2026-10-01 09:00:00","chat_id":"c1"},{"id":"table_2","title":null,"type":"table","created_at":"2026-10-02T09:00:00.000Z","chat_id":"c2"}]}"#))
        let drafts = try await service().drafts()
        let sent = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(sent.httpMethod, "GET")
        XCTAssertEqual(sent.path, "/api/filing/drafts")
        XCTAssertEqual(sent.queryItems["userId"], "42")
        XCTAssertEqual(drafts.map(\.chatID), ["c1", "c2"])
        XCTAssertNotNil(drafts[0].createdAt)
        XCTAssertNotNil(drafts[1].createdAt)
        XCTAssertEqual(drafts[1].displayTitle, "Untitled draft")
    }

    func testAnnexuresAreAskedForWithTheDraftAndItsChat() async throws {
        HTTPStub.always(.json(#"{"success":true,"annexures":[\#(Self.row)]}"#))
        let rows = try await service().annexures(draftID: "canvas_1", chatID: "c1")
        let query = try XCTUnwrap(HTTPStub.lastRequest).queryItems
        XCTAssertEqual(query["draftId"], "canvas_1")
        XCTAssertEqual(query["chatId"], "c1")
        let a = try XCTUnwrap(rows.first)
        XCTAssertNil(a.draftID)
        XCTAssertNil(a.pageRangeLabel)
        XCTAssertEqual(a.fileName, "Order.pdf")
        XCTAssertEqual(a.duplicateOf, "P-1")
        XCTAssertTrue(a.isPendingVerification)
    }

    func testAPageRangeReadsWithAnEnDash() throws {
        let data = Data(Self.row.replacingOccurrences(of: #""page_from":null,"page_to":null"#, with: #""page_from":3,"page_to":7"#).utf8)
        let a = try JSONDecoder().decode(FilingAnnexure.self, from: data)
        XCTAssertEqual(a.pageRangeLabel, "pp. 3–7")
        XCTAssertEqual(a.caption, "Order.pdf · pp. 3–7")
    }

    func testChecklistIsAskedForByDraftAndForum() async throws {
        HTTPStub.always(.json(#"{"success":true,"checklist":{"forum":"High Court","items":[{"id":"prayer","label":"Prayer / reliefs sought","kind":"ai","status":"missing"},{"id":"index","label":"Index","kind":"assembled","status":"auto","note":"Derived folios"}],"blockers":["prayer"],"attention":[]}}"#))
        let list = try await service().checklist(draftID: "canvas_1", forum: "High Court of Delhi")
        let query = try XCTUnwrap(HTTPStub.lastRequest).queryItems
        XCTAssertEqual(query["draftId"], "canvas_1")
        XCTAssertEqual(query["forum"], "High Court of Delhi")
        XCTAssertEqual(list.blockers, ["prayer"])
        XCTAssertEqual(list.groups.map(\.title), ["AI-prepared", "Assembled by system"])
    }

    func testBundlesDecodeEpochMillis() async throws {
        HTTPStub.always(.json(#"{"success":true,"bundles":[{"id":7,"draft_id":"canvas_1","page_count":42,"status":"ok","created_at":1790000000000},{"id":6,"draft_id":"chat:c1","page_count":null,"status":"failed","created_at":1789999000000}]}"#))
        let bundles = try await service().bundles(draftID: "canvas_1")
        XCTAssertEqual(try XCTUnwrap(HTTPStub.lastRequest).queryItems["draftId"], "canvas_1")
        XCTAssertTrue(bundles[0].isReady)
        XCTAssertFalse(bundles[1].isReady)
        XCTAssertEqual(bundles[0].createdDate, Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(bundles[0].title, "Bundle #7 · 42 pages")
    }

    func testABundleThatIsGoneIsAnError() async throws {
        HTTPStub.always(.json(#"{"success":false,"error":"bundle not found"}"#, status: 404))
        do {
            _ = try await service().bundlePDF(id: 9)
            XCTFail("a 404 is not a PDF")
        } catch let error as APIError {
            XCTAssertEqual(error, .server(status: 404, message: "bundle not found"))
        }
        XCTAssertEqual(HTTPStub.lastRequest?.queryItems["bundleId"], "9")
    }

    func testBytesThatAreNotAPDFAreNotShown() async throws {
        HTTPStub.always(.text("<html>oops</html>"))
        do {
            _ = try await service().bundlePDF(id: 9)
            XCTFail("expected an error")
        } catch let error as APIError {
            XCTAssertEqual(error, .server(status: 404, message: "That bundle is no longer available."))
        }
    }

    func testAPDFIsReturnedAsItCame() async throws {
        HTTPStub.always(HTTPStub.Reply(
            status: 200, body: Data("%PDF-1.4 tiny".utf8), headers: ["Content-Type": "application/pdf"]))
        let data = try await service().bundlePDF(id: 7)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "%PDF-1.4 tiny")
    }

    func testAFreeAccountIsRefusedWithACode() async throws {
        HTTPStub.always(.json(#"{"error":"Filing is not on your plan","code":"FEATURE_NOT_IN_PLAN"}"#, status: 402))
        do {
            _ = try await service().drafts()
            XCTFail("expected a refusal")
        } catch let error as APIError {
            XCTAssertEqual(error.refusal?.code, .featureNotInPlan)
        }
    }

    // MARK: - Writes

    func testAddingARootFileSendsTheDotFolder() async throws {
        HTTPStub.always(.json(#"{"success":true,"annexure":\#(Self.row)}"#))
        _ = try await service().addAnnexure(draftID: "canvas_1", folderName: "", fileName: "Engagement_Letter.pdf")
        let sent = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.path, "/api/filing/annexures")
        let body = sent.bodyJSON
        XCTAssertEqual(body["userId"] as? String, "42")
        XCTAssertEqual(body["draftId"] as? String, "canvas_1")
        XCTAssertEqual(body["folderName"] as? String, ".")
        XCTAssertEqual(body["fileName"] as? String, "Engagement_Letter.pdf")
    }

    func testAddingANestedFileSendsItsFolder() async throws {
        HTTPStub.always(.json(#"{"success":true,"annexure":\#(Self.row)}"#))
        _ = try await service().addAnnexure(draftID: "canvas_1", folderName: "Bakshi/Orders", fileName: "Interim_Order.pdf")
        XCTAssertEqual(HTTPStub.lastRequest?.bodyJSON["folderName"] as? String, "Bakshi/Orders")
    }

    func testAnUpdateSendsOnlyWhatChanged() async throws {
        HTTPStub.always(.json(#"{"success":true,"annexure":\#(Self.row)}"#))
        _ = try await service().update(id: 3, title: nil, treatment: .typed, verifyStatus: .pending)
        let sent = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(sent.path, "/api/filing/annexures/update")
        let body = sent.bodyJSON
        XCTAssertEqual(body["id"] as? Int, 3)
        XCTAssertEqual(body["treatment"] as? String, "typed")
        XCTAssertEqual(body["verify_status"] as? String, "pending")
        XCTAssertNil(body["title"])
        XCTAssertEqual(body["userId"] as? String, "42")
    }

    func testARefusedUpdateCarriesTheServersSentence() async throws {
        HTTPStub.always(.json(#"{"success":false,"error":"nothing to update","errors":["nothing to update"]}"#, status: 400))
        do {
            _ = try await service().update(id: 3, title: nil, treatment: nil, verifyStatus: nil)
            XCTFail("expected an error")
        } catch let error as APIError {
            XCTAssertEqual(error, .server(status: 400, message: "nothing to update"))
        }
    }

    func testDeleteAndReorderBodies() async throws {
        HTTPStub.always(.json(#"{"success":true,"orderMatchesMarks":false,"annexures":[\#(Self.row)]}"#))
        try await service().delete(id: 3)
        XCTAssertEqual(HTTPStub.lastRequest?.path, "/api/filing/annexures/delete")
        XCTAssertEqual(HTTPStub.lastRequest?.bodyJSON["id"] as? Int, 3)
        let (matches, rows) = try await service().reorder(draftID: "canvas_1", orderedIDs: [2, 1, 3])
        let sent = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(sent.path, "/api/filing/annexures/reorder")
        XCTAssertEqual(sent.bodyJSON["orderedIds"] as? [Int], [2, 1, 3])
        XCTAssertEqual(sent.bodyJSON["draftId"] as? String, "canvas_1")
        XCTAssertFalse(matches)
        XCTAssertEqual(rows.count, 1)
    }

    func testAssembleSendsTheCoverAndArabicNumbering() async throws {
        HTTPStub.always(.json(#"{"success":true,"bundleId":7,"pageCount":42,"index":[{"label":"Synopsis","folio":1}],"annexures":[{"mark":"P-1","from":20,"to":24}],"checklist":{"forum":"NCLT","items":[],"blockers":[],"attention":[]},"warnings":["P-2: typed copy not verified"],"verify":{"ok":true,"entriesChecked":3,"mismatches":[]}}"#))
        let cover = FilingCover(forum: "NCLT", caseType: "CP (IB)", caseNumber: "123/2026",
                                parties: "A versus B", filingType: "Petition")
        let result = try await service().assemble(draftID: "canvas_1", cover: cover)
        let sent = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(sent.path, "/api/filing/assemble")
        let body = sent.bodyJSON
        XCTAssertEqual(body["userId"] as? String, "42")
        XCTAssertEqual(body["draftId"] as? String, "canvas_1")
        XCTAssertEqual((body["options"] as? [String: Any])?["numbering"] as? String, "arabic")
        let sentCover = try XCTUnwrap(body["cover"] as? [String: String])
        XCTAssertEqual(sentCover, ["forum": "NCLT", "caseType": "CP (IB)", "caseNumber": "123/2026",
                                   "parties": "A versus B", "filingType": "Petition"])
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.index?.first?.folio, 1)
        XCTAssertEqual(result.verifyLine, "Verified: 3 index entries checked against the final PDF")
        XCTAssertEqual(result.warnings, ["P-2: typed copy not verified"])
    }

    func testAFailedAssemblyIsAnAnswerNotAnError() async throws {
        HTTPStub.always(.json(#"{"success":false,"errors":["P-1: source file missing"],"warnings":[],"bundleId":8}"#))
        let result = try await service().assemble(draftID: "canvas_1", cover: FilingCover(forum: "NCLT"))
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorLines, ["P-1: source file missing"])
        XCTAssertEqual(HTTPStub.seen.count, 1)
    }

    func testARejectedAssemblyKeepsEveryReason() async throws {
        HTTPStub.always(.json(#"{"success":false,"error":"P-1: source file missing","errors":["P-1: source file missing","P-4: page range outside the file"]}"#, status: 400))
        let result = try await service().assemble(draftID: "canvas_1", cover: FilingCover(forum: "NCLT"))
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorLines, ["P-1: source file missing", "P-4: page range outside the file"])
        XCTAssertEqual(HTTPStub.seen.count, 1)
    }

    func testAnAssemblyThatCannotBeSentIsNotRetried() async throws {
        HTTPStub.always(.json(#"{"success":false,"error":"internal error: boom"}"#, status: 500))
        do {
            _ = try await service().assemble(draftID: "canvas_1", cover: FilingCover(forum: "NCLT"))
            XCTFail("expected an error")
        } catch {}
        XCTAssertEqual(HTTPStub.seen.count, 1)
    }

    // MARK: - A conversation's annexures

    func testAConversationsAssemblySendsExactlyItsKeys() async throws {
        HTTPStub.always(.json(#"{"success":true,"bundleId":9,"pageCount":12}"#))
        let result = try await service().assemble(
            chatID: "c1", html: "<p>Draft</p>", title: "Writ", cover: FilingCover(forum: "NCLT"))
        let sent = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(sent.path, "/api/filing/assemble")
        let body = sent.bodyJSON
        XCTAssertEqual(Set(body.keys), ["userId", "chatId", "draftHtml", "draftTitle", "cover", "options"])
        XCTAssertEqual(body["chatId"] as? String, "c1")
        XCTAssertEqual(body["draftHtml"] as? String, "<p>Draft</p>")
        XCTAssertEqual(body["draftTitle"] as? String, "Writ")
        XCTAssertEqual((body["options"] as? [String: Any])?["numbering"] as? String, "arabic")
        XCTAssertEqual(result.bundleId, 9)
        XCTAssertEqual(HTTPStub.seen.count, 1)
    }

    func testAConversationsFileIsAddedByTheConversationFromTheRootAsDot() async throws {
        HTTPStub.always(.json(#"{"success":true,"annexure":\#(Self.row)}"#))
        _ = try await service().addAnnexure(chatID: "c1", folderName: "", fileName: "Root.pdf")
        let body = try XCTUnwrap(HTTPStub.lastRequest).bodyJSON
        XCTAssertEqual(Set(body.keys), ["userId", "chatId", "folderName", "fileName"])
        XCTAssertEqual(body["chatId"] as? String, "c1")
        XCTAssertEqual(body["folderName"] as? String, ".")
    }

    func testATypedCopyOrWhyThereIsNone() async throws {
        HTTPStub.always(.json(#"{"success":true,"html":"<p>copy</p>","mark":"P-2"}"#))
        let copy = try await service().typedCopy(chatID: "c1", mark: "P-2")
        let query = try XCTUnwrap(HTTPStub.lastRequest).queryItems
        XCTAssertEqual(query["chatId"], "c1")
        XCTAssertEqual(query["mark"], "P-2")
        XCTAssertEqual(copy, FilingTypedCopy(html: "<p>copy</p>", skipped: false, reason: nil))

        HTTPStub.always(.json(#"{"success":true,"skipped":true,"reason":"P-1 is attached as its original"}"#))
        let skipped = try await service().typedCopy(chatID: "c1", mark: "P-1")
        XCTAssertEqual(skipped, FilingTypedCopy(html: nil, skipped: true, reason: "P-1 is attached as its original"))
    }

    func testAnOriginalCarriesItsTypeAndAnUnshowableOneSaysSo() async throws {
        HTTPStub.always(HTTPStub.Reply(
            status: 200, body: Data("%PDF-1.4".utf8), headers: ["Content-Type": "application/pdf"]))
        let original = try await service().original(chatID: "c1", mark: "P-1")
        XCTAssertEqual(try XCTUnwrap(HTTPStub.lastRequest).path, "/api/filing/annexures/original")
        XCTAssertEqual(original.mime, "application/pdf")
        XCTAssertTrue(original.isPDF)

        HTTPStub.always(HTTPStub.Reply(
            status: 200, body: Data([0x89, 0x50]), headers: ["Content-Type": "image/png; charset=binary"]))
        let image = try await service().original(chatID: "c1", mark: "P-2")
        XCTAssertEqual(image.mime, "image/png")
        XCTAssertTrue(image.isImage)

        HTTPStub.always(.json(#"{"success":false,"error":"preview not available for .heic"}"#, status: 415))
        do {
            _ = try await service().original(chatID: "c1", mark: "P-9")
            XCTFail("expected unpreviewable")
        } catch let error as FilingPreviewError {
            XCTAssertEqual(error, .unpreviewable)
        }
    }

    func testOriginalPagesAreReadWhateverTheStatus() async throws {
        HTTPStub.always(.json(#"{"success":true,"pages":[{"base64":"QQ==","mime":"image/jpeg"}]}"#))
        let pages = try await service().originalPages(chatID: "c1", mark: "P-1")
        XCTAssertEqual(pages.pages.count, 1)

        HTTPStub.always(.json(#"{"success":true,"duplicate_of":"P-1","pages":[]}"#))
        let repeated = try await service().originalPages(chatID: "c1", mark: "P-3")
        XCTAssertEqual(repeated.duplicateOf, "P-1")

        HTTPStub.always(.json(#"{"success":false,"error":"original-page rendering not available for .heic"}"#, status: 415))
        let refused = try await service().originalPages(chatID: "c1", mark: "P-9")
        XCTAssertFalse(refused.success)
        XCTAssertEqual(refused.error, "original-page rendering not available for .heic")
    }

    func testTypedCopiesAreOnePieceOfHTML() async throws {
        HTTPStub.always(.json(#"{"success":true,"html":"<h3>P-2</h3>","marks":["P-2"]}"#))
        let html = try await service().typedCopies(chatID: "c1")
        XCTAssertEqual(try XCTUnwrap(HTTPStub.lastRequest).path, "/api/filing/annexures/typed-copies")
        XCTAssertEqual(html, "<h3>P-2</h3>")
    }
}
