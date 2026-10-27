import XCTest
@testable import EmperorCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A matter's content on the wire: `projectId` on a matter's conversation, History and the
/// Library without matter rows, a matter's drafts, its files, a new folder, attach (its body, its
/// per-file outcomes and its refusals) and the chronology read.
final class MattersContentWireTests: XCTestCase {

    private static let config = APIConfig(baseURL: URL(string: "https://example.test/api")!)

    override func setUp() {
        super.setUp()
        HTTPStub.reset()
    }

    override func tearDown() {
        HTTPStub.reset()
        super.tearDown()
    }

    private func makeClient() async -> APIClient {
        let client = APIClient(config: Self.config, session: HTTPStub.session())
        await client.setCredentials(Credentials(token: "tok-abc", userID: 42))
        return client
    }

    private var last: URLRequest { HTTPStub.lastRequest ?? URLRequest(url: URL(string: "about:blank")!) }

    private func encoded(_ request: ChatRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    // MARK: - Chat

    func testAMattersConversationCarriesTheMatterOnEveryTurn() async throws {
        let service = ChatService(client: await makeClient()).scoped(toProject: " prj-writ ")
        let first = service.turnBody(
            history: [ChatMessage(role: .user, content: "Summarise")], chatID: "c1", model: .default,
            role: nil, attachments: nil, webSearch: false, userID: "42")
        XCTAssertEqual(try encoded(first)["projectId"] as? String, "prj-writ")
        let later = service.turnBody(
            history: [ChatMessage(role: .user, content: "a"), ChatMessage(role: .assistant, content: "b"),
                      ChatMessage(role: .user, content: "c")],
            chatID: "c1", model: .default, role: nil, attachments: nil, webSearch: false, userID: "42")
        XCTAssertEqual(try encoded(later)["projectId"] as? String, "prj-writ", "not only the first turn")
    }

    func testAnOrdinaryConversationSendsNoProjectKeyAtAll() async throws {
        let service = ChatService(client: await makeClient())
        let body = service.turnBody(
            history: [ChatMessage(role: .user, content: "Hello")], chatID: "c1", model: .default,
            role: nil, attachments: nil, webSearch: false, userID: "42")
        XCTAssertFalse(try encoded(body).keys.contains("projectId"))
        XCTAssertNil(service.scoped(toProject: "  ").projectID, "a blank id scopes nothing")
    }

    func testHistoryLeavesOutTheMattersConversations() async throws {
        HTTPStub.always(.json(#"""
            {"success":true,"chats":[
            {"id":"a","title":"Bail","updatedAt":"2026-10-01 10:00:00","project_id":null},
            {"id":"b","title":"Matter chat","project_id":"prj-writ"},
            {"id":"c","title":"Old row"},
            {"id":"d","title":"Numbered","project_id":17},
            {"id":"e","title":"Blank","project_id":""}]}
            """#))
        let chats = try await ChatService(client: await makeClient()).chats()
        XCTAssertEqual(chats.map(\.id), ["a", "c", "e"])
    }

    // MARK: - Drafts

    private static let draftRows = #"""
        {"success":true,"documents":[
        {"id":"d1","chat_id":"c1","title":"Notice","type":"doc","created_at":"2026-10-01 10:00:00","chat_title":"x","project_id":null},
        {"id":"d2","chat_id":"c2","title":"Rejoinder","type":"doc","created_at":"2026-10-02 10:00:00","chat_title":"y","project_id":"prj-writ"},
        {"id":"d3","chat_id":"c3","title":"Other matter","type":"doc","created_at":"2026-10-02 10:00:00","chat_title":"z","project_id":"prj-arb"}]}
        """#

    func testTheLibraryLeavesOutMatterDrafts() async throws {
        HTTPStub.always(.json(Self.draftRows))
        let drafts = try await DraftHistoryService(client: await makeClient()).drafts(.document)
        XCTAssertEqual(drafts.map(\.id), ["d1"])
        XCTAssertNil(last.queryItems["projectId"])
    }

    func testAMattersDraftsAreAskedForByTheMatterAndOnlyItsRowsKept() async throws {
        HTTPStub.always(.json(Self.draftRows))
        let drafts = try await DraftHistoryService(client: await makeClient()).drafts(.table, projectID: "prj-writ")
        XCTAssertEqual(drafts.map(\.id), ["d2"])
        XCTAssertEqual(drafts.first?.projectID, "prj-writ")
        XCTAssertEqual(last.path, "/api/tables")
        XCTAssertEqual(last.queryItems["projectId"], "prj-writ")
        XCTAssertEqual(last.queryItems["userId"], "42")
    }

    // MARK: - Files

    func testTheListingIsReadIntoFilesAndFolders() async throws {
        HTTPStub.always(.json(#"""
            {"success":true,"root":"_projects/prj-writ","folders":[{"type":"folder","name":"Pleadings",
            "path":"_projects/prj-writ/Pleadings","created":"2026-10-01T10:00:00.000Z","files":[{"type":"file",
            "name":"Petition.pdf","path":"_projects/prj-writ/Pleadings/Petition.pdf","size":10,"status":"ready"}]}],
            "files":[{"type":"file","name":"Loose.pdf","path":"_projects/prj-writ/Loose.pdf","status":"Queued"}]}
            """#))
        let listing = try await MatterFilesService(client: await makeClient()).listing(projectID: "prj-writ")
        XCTAssertEqual(last.httpMethod, "GET")
        XCTAssertEqual(last.path, "/api/project-files")
        XCTAssertEqual(last.queryItems["projectId"], "prj-writ")
        XCTAssertEqual(listing.root, "_projects/prj-writ")
        XCTAssertEqual(listing.folders.count, 1)
        XCTAssertEqual(listing.files.map(\.name), ["Loose.pdf"])
        XCTAssertEqual(listing.receiptChoices.map(\.folder), ["", "Pleadings"])
    }

    func testANewFolderSendsItsNameRelativeToTheMatter() async throws {
        HTTPStub.always(.json(#"{"success":true,"folder":"_projects/prj-writ/Pleadings/Drafts","existed":true}"#))
        let made = try await MatterFilesService(client: await makeClient())
            .createFolder(projectID: "prj-writ", name: "Pleadings/Drafts")
        XCTAssertEqual(made.folder, "_projects/prj-writ/Pleadings/Drafts")
        XCTAssertTrue(made.existed)
        XCTAssertEqual(last.path, "/api/project-folder")
        XCTAssertEqual(last.bodyJSON["name"] as? String, "Pleadings/Drafts")
        XCTAssertEqual(last.bodyJSON["userId"] as? String, "42")
    }

    func testAFolderRefusalIsTheServersSentence() async throws {
        HTTPStub.always(.json(#"{"success":false,"error":"Folders can be nested at most 8 deep"}"#, status: 400))
        do {
            _ = try await MatterFilesService(client: await makeClient()).createFolder(projectID: "p", name: "a/b")
            XCTFail("expected the refusal")
        } catch {
            XCTAssertEqual(DisplayText.message(for: error), "Folders can be nested at most 8 deep")
        }
    }

    func testAttachSendsTheDocumentsAndReadsEveryOutcome() async throws {
        HTTPStub.always(.json(#"""
            {"success":true,"folder":"_projects/prj-writ/Orders","files":[
            {"name":"Plaint.pdf","folder":"_projects/prj-writ/Orders","status":"indexing","source":{"folderName":"Bakshi","fileName":"Plaint.pdf"}},
            {"name":"Scan.pdf","folder":"_projects/prj-writ/Orders","status":"ready","source":{"folderName":"","fileName":"Scan.pdf"}},
            {"name":"Draft.pdf","folder":"_projects/prj-writ/Orders","status":"skipped","source":{"folderName":"Bakshi","fileName":"Draft.pdf"},
             "reason":"Still being read in My Files. Attach it once it shows as ready there.","processing":true,"detail":"still running"},
            {"name":"Order.pdf","folder":"_projects/prj-writ/Orders","status":"skipped","source":{"folderName":"Bakshi","fileName":"Order.pdf"},
             "reason":"Already in this matter (Pleadings/Order.pdf)","already":true,
             "existing":{"folderName":"_projects/prj-writ/Pleadings","fileName":"Order.pdf"}}]}
            """#))
        let result = try await MatterFilesService(client: await makeClient()).attach(
            projectID: "prj-writ",
            files: [MatterFileRef(folderName: "Bakshi", fileName: "Plaint.pdf"), MatterFileRef(folderName: "", fileName: "Scan.pdf")],
            subfolder: "Orders")
        XCTAssertEqual(last.path, "/api/project-attach")
        let body = last.bodyJSON
        XCTAssertEqual(body["projectId"] as? String, "prj-writ")
        XCTAssertEqual(body["subfolder"] as? String, "Orders")
        let files = body["files"] as? [[String: String]]
        XCTAssertEqual(files?.first, ["folderName": "Bakshi", "fileName": "Plaint.pdf"])
        XCTAssertEqual(result.folder, "_projects/prj-writ/Orders")
        XCTAssertEqual(result.rows.map(\.status), ["indexing", "ready", "skipped", "skipped"])
        XCTAssertEqual(result.rows[2].processing, true)
        XCTAssertEqual(result.rows[2].detail, "still running")
        XCTAssertEqual(result.rows[3].existing, MatterFileRef(folderName: "_projects/prj-writ/Pleadings", fileName: "Order.pdf"))
        XCTAssertEqual(AttachFromMyFilesViewModel.summary(result.rows),
                       "2 attached · 2 skipped: Still being read in My Files. Attach it once it shows as ready there.")
    }

    func testAnAttachOverTheSizeCapIsRefusedWhole() async throws {
        HTTPStub.always(.json(#"{"success":false,"error":"These documents come to more than 2048 MB. Attach them in smaller groups."}"#, status: 413))
        do {
            _ = try await MatterFilesService(client: await makeClient()).attach(
                projectID: "p", files: [MatterFileRef(folderName: "", fileName: "A.pdf")], subfolder: "Pleadings")
            XCTFail("expected the refusal")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 413, message: "These documents come to more than 2048 MB. Attach them in smaller groups."))
        }
    }

    func testAFullStorageRefusalKeepsItsCode() async throws {
        HTTPStub.always(.json(#"{"success":false,"error":"Your storage is full. Upgrade your plan.","code":"STORAGE_LIMIT"}"#, status: 402))
        do {
            _ = try await MatterFilesService(client: await makeClient()).attach(
                projectID: "p", files: [MatterFileRef(folderName: "", fileName: "A.pdf")], subfolder: "Pleadings")
            XCTFail("expected the refusal")
        } catch {
            XCTAssertNotNil((error as? APIError)?.refusal, "a coded refusal is a refusal, not a failure")
        }
    }

    // MARK: - Chronology

    func testTheChronologyReadSendsTheChosenFilesAndWaitsLonger() async throws {
        HTTPStub.always(.json(#"""
            {"success":true,"events":[{"date":"05-01-2024","title":"Agreement","details":"Signed","kind":"milestone","sourceRef":"Deed.pdf, p. 1"},
            "garbage",{"date":null,"title":"Undated"}],"files":2,"skipped":["Scan.pdf"],
            "chunks":{"total":3,"failed":1,"notRun":0},"partial":true}
            """#))
        let set = try await MatterFilesService(client: await makeClient()).extractChronology(
            projectID: "prj-writ", files: [MatterFileRef(folderName: "_projects/prj-writ/Pleadings", fileName: "Deed.pdf")])
        XCTAssertEqual(last.path, "/api/project-chronology-extract")
        XCTAssertEqual(last.timeoutInterval, MatterFilesService.extractTimeout)
        XCTAssertEqual((last.bodyJSON["files"] as? [[String: String]])?.first?["fileName"], "Deed.pdf")
        XCTAssertEqual(set.events.count, 2, "a malformed event costs only itself")
        XCTAssertEqual(set.events[0].sourceRef, "Deed.pdf, p. 1")
        XCTAssertEqual(set.files, 2)
        XCTAssertEqual(set.skipped, ["Scan.pdf"])
        XCTAssertTrue(set.partial)
    }

    func testAllDocumentsSendsNoFileList() async throws {
        HTTPStub.always(.json(#"{"success":true,"events":[],"files":0,"skipped":[],"message":"This project has no documents yet."}"#))
        let set = try await MatterFilesService(client: await makeClient()).extractChronology(projectID: "p", files: nil)
        XCTAssertNil(last.bodyJSON["files"])
        XCTAssertEqual(set.message, "This project has no documents yet.")
    }

    func testAnExhaustedAllowanceIsARefusal() async throws {
        HTTPStub.always(.json(#"{"success":false,"error":"This month's chat queries are used up. Upgrade your plan to keep going.","code":"QUERY_LIMIT"}"#, status: 402))
        do {
            _ = try await MatterFilesService(client: await makeClient()).extractChronology(projectID: "p", files: nil)
            XCTFail("expected the refusal")
        } catch {
            XCTAssertNotNil((error as? APIError)?.refusal)
        }
    }
}
