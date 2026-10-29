import XCTest
@testable import EmperorCore

/// `/file-text`, `/set-preferred-model` and `/maintenance` on the wire, through the real client.
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
}
