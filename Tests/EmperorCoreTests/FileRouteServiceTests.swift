import XCTest
@testable import EmperorCore

/// The six small file routes on the wire, through the real client.
final class FileRouteServiceTests: XCTestCase {

    /// Before each test, not only after: see `HTTPStub.reset`.
    override func setUp() {
        super.setUp()
        HTTPStub.reset()
    }

    override func tearDown() {
        HTTPStub.reset()
        super.tearDown()
    }

    private func service() async -> FileRouteService {
        let client = APIClient(
            config: APIConfig(baseURL: URL(string: "https://example.test/api")!),
            session: HTTPStub.session())
        await client.setCredentials(Credentials(token: "tok", userID: 7))
        return FileRouteService(client: client)
    }

    private static func bytes(_ data: Data, type: String, status: Int = 200) -> HTTPStub.Reply {
        HTTPStub.Reply(status: status, body: data, headers: ["Content-Type": type])
    }

    // MARK: - /save-document

    func testSaveSendsTheRowsOwnIdKindAndConversation() async throws {
        HTTPStub.always(.json(#"{"success":true,"id":"d9","type":"doc","deduped":true,"reclassified":false}"#))
        let result = try await service().saveDocument(
            id: "d1", title: "Plaint", content: "<p>x</p>", type: "doc", chatId: "c1")

        let request = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.path, "/api/save-document")
        XCTAssertEqual(request.header("Authorization"), "Bearer tok")
        let body = request.bodyJSON
        XCTAssertEqual(body["userId"] as? String, "7")
        XCTAssertEqual(body["id"] as? String, "d1")
        XCTAssertEqual(body["title"] as? String, "Plaint")
        XCTAssertEqual(body["content"] as? String, "<p>x</p>")
        XCTAssertEqual(body["type"] as? String, "doc")
        XCTAssertEqual(body["source"] as? String, "draft")
        XCTAssertEqual(body["chatId"] as? String, "c1")
        XCTAssertEqual(result.id, "d9")
        XCTAssertEqual(result.deduped, true)
    }

    func testSaveWithoutAConversationLeavesTheKeyOut() async throws {
        HTTPStub.always(.json(#"{"success":true,"id":"d1"}"#))
        _ = try await service().saveDocument(id: "d1", title: "T", content: "c", type: "doc", chatId: nil)
        XCTAssertNil(HTTPStub.lastRequest?.bodyJSON["chatId"])
    }

    func testSaveRefusalIsTheServersSentence() async throws {
        HTTPStub.always(.json(#"{"success":false,"error":"Not your document"}"#, status: 403))
        do {
            _ = try await service().saveDocument(id: "d1", title: "T", content: "c", type: "doc", chatId: nil)
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 403, message: "Not your document"))
        }
    }

    // MARK: - /download-files

    func testZipSendsTheEntriesAndAnswersTheArchive() async throws {
        let archive = Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00])
        HTTPStub.always(Self.bytes(archive, type: "application/zip"))
        let data = try await service().zip([
            ZipEntry(folderName: "Bakshi", fileName: "Plaint.pdf"),
            ZipEntry(folderName: ".", fileName: "Loose.pdf"),
        ])

        let request = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(request.path, "/api/download-files")
        XCTAssertEqual(request.bodyJSON["userId"] as? String, "7")
        let files = try XCTUnwrap(request.bodyJSON["files"] as? [[String: String]])
        XCTAssertEqual(files, [
            ["folderName": "Bakshi", "fileName": "Plaint.pdf"],
            ["folderName": ".", "fileName": "Loose.pdf"],
        ])
        XCTAssertEqual(data, archive)
    }

    func testZipErrorIsClassifiedFromItsJSON() async throws {
        HTTPStub.always(.json(#"{"error":"None of the requested files were found"}"#, status: 404))
        do {
            _ = try await service().zip([ZipEntry(folderName: ".", fileName: "x.pdf")])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(
                error as? APIError,
                .server(status: 404, message: "None of the requested files were found"))
        }
    }

    func testZipThatIsNotAnArchiveIsRefused() async throws {
        HTTPStub.always(Self.bytes(Data("<html>".utf8), type: "text/html"))
        do {
            _ = try await service().zip([ZipEntry(folderName: ".", fileName: "x.pdf")])
            XCTFail("expected an error")
        } catch {
            guard case .server(200, let message)? = error as? APIError else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertTrue(message.contains("damaged"))
        }
    }

    // MARK: - /file-text

    func testFileTextAsksForTheRootAsDot() async throws {
        HTTPStub.always(.json(
            ##"{"success":true,"fileName":"Brief.docx","fileExists":true,"totalPages":2,"matchedBy":"path","truncated":false,"pages":[{"page":1,"content":"# One"},{"page":2,"content":"Two"}]}"##))
        let response = try await service().fileText(name: "Brief.docx", folderName: nil)

        let request = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.path, "/api/file-text")
        XCTAssertEqual(request.queryItems, ["userId": "7", "fileName": "Brief.docx", "folderName": "."])
        XCTAssertEqual(response.pages?.map(\.page), [1, 2])
        XCTAssertEqual(response.matchedBy, "path")
    }

    func testFileTextKeepsANestedFolder() async throws {
        HTTPStub.always(.json(#"{"success":true,"pages":[]}"#))
        _ = try await service().fileText(name: "a.docx", folderName: "Arora_Holdings/2025")
        XCTAssertEqual(HTTPStub.lastRequest?.queryItems["folderName"], "Arora_Holdings/2025")
    }

    func testFileTextRefusalThrows() async throws {
        HTTPStub.always(.json(#"{"success":false,"error":"Missing parameters"}"#, status: 400))
        do {
            _ = try await service().fileText(name: "a.docx", folderName: "X")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 400, message: "Missing parameters"))
        }
    }

    // MARK: - /print-pdf

    func testPrintSendsTheHTMLTitleAndPaper() async throws {
        HTTPStub.always(Self.bytes(Data("%PDF-1.7\n".utf8), type: "application/pdf"))
        let data = try await service().printPDF(html: "<p>x</p>", title: "Plaint", pageSetup: PageSetup())

        let request = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(request.path, "/api/print-pdf")
        XCTAssertEqual(request.timeoutInterval, FileRouteService.printTimeout)
        let body = request.bodyJSON
        XCTAssertEqual(body["html"] as? String, "<p>x</p>")
        XCTAssertEqual(body["title"] as? String, "Plaint")
        let setup = try XCTUnwrap(body["pageSetup"] as? [String: Any])
        XCTAssertEqual(setup["size"] as? String, "a4")
        XCTAssertEqual(setup["orientation"] as? String, "portrait")
        let margins = try XCTUnwrap(setup["margins"] as? [String: Double])
        XCTAssertEqual(margins, ["top": 25, "right": 20, "bottom": 25, "left": 25])
        XCTAssertTrue(FileRouteService.isPDF(data))
    }

    func testPrintThatIsNotAPDFIsRefused() async throws {
        HTTPStub.always(Self.bytes(Data("oops".utf8), type: "application/pdf"))
        do {
            _ = try await service().printPDF(html: "x", title: "T", pageSetup: PageSetup())
            XCTFail("expected an error")
        } catch {
            guard case .server(200, _)? = error as? APIError else { return XCTFail("unexpected \(error)") }
        }
    }

    func testPrintFailureCarriesTheServersWords() async throws {
        HTTPStub.always(.json(#"{"error":"Failed to render PDF: timeout"}"#, status: 500))
        do {
            _ = try await service().printPDF(html: "x", title: "T", pageSetup: PageSetup())
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 500, message: "Failed to render PDF: timeout"))
        }
    }

    // MARK: - /set-preferred-model and /maintenance

    func testSetPreferredModelSendsTheRawValue() async throws {
        HTTPStub.always(.json(#"{"success":true}"#))
        try await service().setPreferredModel(.thinking)
        let request = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(request.path, "/api/set-preferred-model")
        XCTAssertEqual(request.bodyJSON["userId"] as? String, "7")
        XCTAssertEqual(request.bodyJSON["model"] as? String, "thinking")
    }

    func testSetPreferredModelFailureThrows() async throws {
        HTTPStub.always(.json(#"{"success":false,"error":"Failed to save preferred model"}"#, status: 500))
        do {
            try await service().setPreferredModel(.fast)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 500, message: "Failed to save preferred model"))
        }
    }

    func testMaintenanceIsReadAndOnlyActiveShows() async throws {
        HTTPStub.always(.json(
            #"{"enabled":true,"message":"Back at 6","since":"2026-10-27T10:00:00.000Z","bypass":false,"active":true,"reloadToken":null,"buildId":"abc"}"#))
        let state = try await service().maintenance()
        XCTAssertEqual(HTTPStub.lastRequest?.path, "/api/maintenance")
        XCTAssertEqual(state.active, true)
        XCTAssertEqual(state.message, "Back at 6")
        XCTAssertTrue(MaintenanceNotice.shouldShow(state))
        XCTAssertEqual(MaintenanceNotice.message(for: state), "Back at 6")

        XCTAssertFalse(MaintenanceNotice.shouldShow(MaintenanceState(enabled: true, active: false, bypass: true)))
        XCTAssertFalse(MaintenanceNotice.shouldShow(nil))
    }

    func testMaintenanceToleratesAnOddlyTypedField() throws {
        let state = try JSONDecoder().decode(
            MaintenanceState.self, from: Data(#"{"enabled":false,"since":1730000000000,"active":false,"message":null}"#.utf8))
        XCTAssertNil(state.since)
        XCTAssertEqual(state.active, false)
        XCTAssertEqual(MaintenanceNotice.message(for: MaintenanceState(active: true)),
                       "Emperor is down for maintenance. Some things may not work until it is back.")
    }

    // MARK: - Golden

    /// `PageSetup()` is the web's `normalizePageSetup({size:'a4'})`, from the platform's own code.
    func testDefaultPageSetupMatchesTheWeb() throws {
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try parityFixture("14-X", "page-setup")) as? [String: Any])
        let ours = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(PageSetup())) as? NSDictionary)
        XCTAssertEqual(ours, fixture["a4"] as? NSDictionary)
        XCTAssertEqual(ours, fixture["default"] as? NSDictionary)

        var letter = PageSetup()
        letter.size = "letter"
        let theirs = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(letter)) as? NSDictionary)
        XCTAssertEqual(theirs, fixture["letter"] as? NSDictionary)
    }
}
