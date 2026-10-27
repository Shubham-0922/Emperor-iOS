import XCTest
@testable import EmperorCore

/// The cloud drive routes on the wire, through the real client.
final class CloudDriveServiceTests: XCTestCase {

    /// Before each test, not only after: see `HTTPStub.reset`.
    override func setUp() {
        super.setUp()
        HTTPStub.reset()
    }

    override func tearDown() {
        HTTPStub.reset()
        super.tearDown()
    }

    private func service() async -> CloudDriveService {
        let client = APIClient(
            config: APIConfig(baseURL: URL(string: "https://example.test/api")!),
            session: HTTPStub.session())
        await client.setCredentials(Credentials(token: "tok", userID: 7))
        return CloudDriveService(client: client)
    }

    // MARK: - /cloud/connections

    func testConnectionsAreReadPerProvider() async throws {
        HTTPStub.always(.json(
            #"{"success":true,"providers":{"google":{"label":"Google Drive","configured":true,"connected":true,"email":"a@b.in"},"microsoft":{"label":"OneDrive","configured":false,"connected":false,"email":null},"dropbox":{"configured":true}}}"#))
        let connections = try await service().connections()

        let request = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.path, "/api/cloud/connections")
        XCTAssertEqual(request.queryItems["userId"], "7")
        XCTAssertEqual(request.header("Authorization"), "Bearer tok")
        XCTAssertEqual(connections.count, 2)
        XCTAssertEqual(connections[.google]?.email, "a@b.in")
        XCTAssertEqual(connections[.google]?.isConnected, true)
        XCTAssertEqual(connections[.microsoft]?.isConfigured, false)
    }

    // MARK: - /cloud/connect

    func testConnectAsksForTheProviderAndAnswersItsPage() async throws {
        HTTPStub.always(.json(#"{"success":true,"url":"https://accounts.google.com/o/oauth2/v2/auth?state=s"}"#))
        let url = try await service().connectURL(.google)

        let request = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(request.path, "/api/cloud/connect")
        XCTAssertEqual(request.queryItems["provider"], "google")
        XCTAssertEqual(request.queryItems["userId"], "7")
        XCTAssertEqual(url.host, "accounts.google.com")
    }

    func testConnectAcceptsMicrosoftsSignInHost() async throws {
        HTTPStub.always(.json(#"{"success":true,"url":"https://login.microsoftonline.com/common/oauth2/v2.0/authorize?x=1"}"#))
        let url = try await service().connectURL(.microsoft)
        XCTAssertEqual(HTTPStub.lastRequest?.queryItems["provider"], "microsoft")
        XCTAssertEqual(url.host, "login.microsoftonline.com")
    }

    func testConnectRefusesAPlainHTTPPage() async {
        HTTPStub.always(.json(#"{"success":true,"url":"http://accounts.google.com/o/oauth2/v2/auth"}"#))
        await assertRefused { try await self.service().connectURL(.google) }
    }

    func testConnectRefusesAForeignHost() async {
        HTTPStub.always(.json(#"{"success":true,"url":"https://accounts.google.com.example.net/auth"}"#))
        await assertRefused { try await self.service().connectURL(.google) }
    }

    func testSignInURLRules() {
        XCTAssertNotNil(CloudDriveService.signInURL("https://ACCOUNTS.google.com/x"))
        XCTAssertNil(CloudDriveService.signInURL(nil))
        XCTAssertNil(CloudDriveService.signInURL("emperor://cloud"))
        XCTAssertNil(CloudDriveService.signInURL("https://evil.test/accounts.google.com"))
    }

    func testConnectNotConfiguredIsTheServersSentence() async {
        HTTPStub.always(.json(#"{"success":false,"error":"Google Drive is not configured on this server"}"#, status: 400))
        do {
            _ = try await service().connectURL(.google)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(
                error as? APIError,
                .server(status: 400, message: "Google Drive is not configured on this server"))
        }
    }

    // MARK: - /cloud/disconnect

    func testDisconnectPostsTheProvider() async throws {
        HTTPStub.always(.json(#"{"success":true}"#))
        try await service().disconnect(.microsoft)
        let request = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.path, "/api/cloud/disconnect")
        XCTAssertEqual(request.bodyJSON["userId"] as? String, "7")
        XCTAssertEqual(request.bodyJSON["provider"] as? String, "microsoft")
    }

    // MARK: - /cloud/list

    func testListDecodesFilesWithAndWithoutType() async throws {
        HTTPStub.always(.json(
            #"{"success":true,"files":[{"id":"f1","name":"a.pdf","mime":"application/pdf","size":2048,"modified":"2026-10-01T09:00:00.000Z"},{"id":"f2","name":"b.docx","mime":null,"size":0,"modified":null}]}"#))
        let files = try await service().list(.google)

        let request = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(request.path, "/api/cloud/list")
        XCTAssertEqual(request.queryItems["provider"], "google")
        XCTAssertEqual(files.map(\.id), ["f1", "f2"])
        XCTAssertNil(files[1].mime)
        XCTAssertNotNil(files[0].modified)
        XCTAssertEqual(files[0].detailLine, "2.0 KB · 1 Oct 2026")
        XCTAssertNil(files[1].detailLine)
    }

    func testListNotConnectedSaysWhereToConnectOnThePhone() async {
        HTTPStub.always(.json(
            #"{"success":false,"error":"Google Drive is not connected — connect it in Settings → Connected services"}"#,
            status: 409))
        do {
            _ = try await service().list(.google)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(
                error as? APIError,
                .server(status: 409, message: "Google Drive is not connected — connect it in Account → Connected services"))
        }
    }

    func testExpiredSessionTextIsPassedThroughForTheApp() async {
        HTTPStub.always(.json(
            #"{"success":false,"error":"OneDrive session expired — please reconnect in Settings"}"#, status: 409))
        do {
            _ = try await service().list(.microsoft)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(
                error as? APIError,
                .server(status: 409, message: "OneDrive session expired — please reconnect in Account → Connected services"))
        }
    }

    // MARK: - /cloud/import

    func testImportSendsTheFileAndTheFolder() async throws {
        HTTPStub.always(.json(#"{"success":true,"fileName":"a.pdf","folderName":"Bakshi","size":2048}"#))
        let result = try await service().importFile(
            .google, file: CloudFile(id: "f1", name: "a.pdf"), into: "Bakshi")

        let request = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.path, "/api/cloud/import")
        let body = request.bodyJSON
        XCTAssertEqual(body["userId"] as? String, "7")
        XCTAssertEqual(body["provider"] as? String, "google")
        XCTAssertEqual(body["fileId"] as? String, "f1")
        XCTAssertEqual(body["fileName"] as? String, "a.pdf")
        XCTAssertEqual(body["folderName"] as? String, "Bakshi")
        XCTAssertEqual(result.folderName, "Bakshi")
        XCTAssertEqual(HTTPStub.seen.count, 1, "a write is never retried")
    }

    func testImportIntoTheTopLevelSendsADot() async throws {
        HTTPStub.always(.json(#"{"success":true,"fileName":"a.pdf","folderName":"","size":1}"#))
        _ = try await service().importFile(.google, file: CloudFile(id: "f1", name: "a.pdf"), into: nil)
        XCTAssertEqual(HTTPStub.lastRequest?.bodyJSON["folderName"] as? String, ".")
    }

    func testImportDocumentLimitIsARefusal() async {
        HTTPStub.always(.json(
            #"{"success":false,"error":"Upgrade to upload more documents","code":"DOCUMENT_LIMIT"}"#, status: 402))
        do {
            _ = try await service().importFile(.google, file: CloudFile(id: "f1", name: "a.pdf"), into: nil)
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual((error as? APIError)?.refusal?.code, .documentLimit)
            XCTAssertEqual(HTTPStub.seen.count, 1)
        }
    }

    func testImportStorageLimitIsARefusal() async {
        HTTPStub.always(.json(
            #"{"success":false,"error":"Storage full","code":"STORAGE_LIMIT"}"#, status: 413))
        do {
            _ = try await service().importFile(.google, file: CloudFile(id: "f1", name: "a.pdf"), into: nil)
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual((error as? APIError)?.refusal?.code, .storageLimit)
        }
    }

    // MARK: - /cloud/export

    func testExportSendsNameAndFolder() async throws {
        HTTPStub.always(.json(#"{"success":true,"id":"x","name":"Plaint.pdf","url":"https://drive.google.com/file/d/x/view"}"#))
        let result = try await service().export(.google, name: "Plaint.pdf", folder: nil)

        let request = try XCTUnwrap(HTTPStub.lastRequest)
        XCTAssertEqual(request.path, "/api/cloud/export")
        let body = request.bodyJSON
        XCTAssertEqual(body["userId"] as? String, "7")
        XCTAssertEqual(body["provider"] as? String, "google")
        XCTAssertEqual(body["fileName"] as? String, "Plaint.pdf")
        XCTAssertEqual(body["folderName"] as? String, ".")
        XCTAssertEqual(result.url, "https://drive.google.com/file/d/x/view")
    }

    func testExportNotFound() async {
        HTTPStub.always(.json(#"{"success":false,"error":"File not found"}"#, status: 404))
        do {
            _ = try await service().export(.google, name: "x.pdf", folder: "A")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 404, message: "File not found"))
        }
    }

    func testSuccessFalseOn200IsAnError() async {
        HTTPStub.always(.json(#"{"success":false,"error":"Unknown provider"}"#))
        do {
            try await service().disconnect(.google)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 200, message: "Unknown provider"))
        }
    }

    // MARK: - Copy

    func testMessagesPointAtAccount() {
        XCTAssertEqual(
            CloudCopy.forApp("Google Drive read access was not granted — Disconnect and reconnect Google Drive in Settings"),
            "Google Drive read access was not granted — Disconnect and reconnect Google Drive in Account → Connected services")
        XCTAssertEqual(CloudCopy.forApp("File not found"), "File not found")
    }

    private func assertRefused(
        _ body: @escaping () async throws -> URL, file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await body()
            XCTFail("expected the page to be refused", file: file, line: line)
        } catch {
            guard case .server(200, let message)? = error as? APIError else {
                return XCTFail("unexpected \(error)", file: file, line: line)
            }
            XCTAssertTrue(message.contains("could not be opened"), message, file: file, line: line)
        }
    }
}
