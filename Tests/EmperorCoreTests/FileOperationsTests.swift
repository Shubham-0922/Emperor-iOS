import XCTest
@testable import EmperorCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Moving a folder, reading a document again, and fetching a PDF's searchable copy.
final class FileOperationsWireTests: XCTestCase {

    private static let config = APIConfig(baseURL: URL(string: "https://example.test/api")!)

    override func setUp() {
        super.setUp()
        HTTPStub.reset()
    }

    override func tearDown() {
        HTTPStub.reset()
        super.tearDown()
    }

    private func makeService() async -> FileManagementService {
        let client = APIClient(config: Self.config, session: HTTPStub.session())
        await client.setCredentials(Credentials(token: "tok-abc", userID: 42))
        var service = FileManagementService(client: client)
        service.pollInterval = .milliseconds(1)
        return service
    }

    // MARK: Move folder

    func testMovingAFolderSendsBothPaths() async throws {
        HTTPStub.always(.json(#"{"success":true,"folderName":"Arora/Bakshi"}"#))
        let service = await makeService()

        let moved = try await service.moveFolder(at: "Bakshi", toParent: "Arora")

        let body = HTTPStub.lastRequest?.bodyJSON ?? [:]
        XCTAssertEqual(HTTPStub.lastRequest?.path, "/api/move-folder")
        XCTAssertEqual(body["fromPath"] as? String, "Bakshi")
        XCTAssertEqual(body["toParentPath"] as? String, "Arora")
        XCTAssertEqual(moved, "Arora/Bakshi")
    }

    func testMovingAFolderToTheTopLevelSendsAnEmptyParent() async throws {
        HTTPStub.always(.json(#"{"success":true}"#))
        let service = await makeService()

        let moved = try await service.moveFolder(at: "Bakshi/2025", toParent: nil)

        let body = HTTPStub.lastRequest?.bodyJSON ?? [:]
        XCTAssertEqual(body["toParentPath"] as? String, "", "the root is empty here, never a dot")
        XCTAssertEqual(moved, "2025")
    }

    func testAFolderMoveRefusalCarriesTheServersWords() async {
        HTTPStub.always(.json(#"{"success":false,"error":"Destination exists"}"#, status: 409))
        let service = await makeService()

        do {
            _ = try await service.moveFolder(at: "A", toParent: "B")
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? APIError, .server(status: 409, message: "Destination exists"))
        }
    }

    // MARK: Read again

    func testReadingAgainPostsFolderAndFile() async throws {
        HTTPStub.always(.json(#"{"success":true,"message":"Re-processing started"}"#))
        let service = await makeService()

        try await service.reprocess(name: "Scan.pdf", folderName: "Bakshi")

        let body = HTTPStub.lastRequest?.bodyJSON ?? [:]
        XCTAssertEqual(HTTPStub.lastRequest?.path, "/api/re-ocr")
        XCTAssertEqual(body["folderName"] as? String, "Bakshi")
        XCTAssertEqual(body["fileName"] as? String, "Scan.pdf")
    }

    func testReadingAgainAtTheRootSpellsItWithADot() async throws {
        HTTPStub.always(.json(#"{"success":true}"#))
        let service = await makeService()

        try await service.reprocess(name: "Scan.pdf", folderName: nil)

        XCTAssertEqual(HTTPStub.lastRequest?.bodyJSON["folderName"] as? String, ".")
    }

    func testReadingAgainAMissingDocumentSaysSo() async {
        HTTPStub.always(.json(#"{"error":"File not found"}"#, status: 404))
        let service = await makeService()

        do {
            try await service.reprocess(name: "Gone.pdf", folderName: "Bakshi")
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(
                error as? APIError,
                .server(status: 404, message: "That document is no longer in your library."))
        }
    }

    func testReadingAgainThenFollowsTheStatusUntilItEnds() async throws {
        let counter = Counter()
        HTTPStub.respond { request in
            guard request.url?.path.hasSuffix("/upload-status") == true else {
                return .json(#"{"success":true}"#)
            }
            return counter.next() < 2
                ? .json(#"{"status":"Reading document content..."}"#)
                : .json(#"{"status":"ready"}"#)
        }
        let service = await makeService()

        let state = try await service.awaitIngestion(name: "Scan.pdf", folderName: "Bakshi")

        XCTAssertEqual(state, .ready)
        let polls = HTTPStub.seen.filter { $0.url?.path.hasSuffix("/upload-status") == true }
        XCTAssertEqual(polls.count, 3)
        XCTAssertEqual(polls.first?.queryItems["folderName"], "Bakshi")
        XCTAssertEqual(polls.first?.queryItems["fileName"], "Scan.pdf")
    }

    // MARK: Searchable copy

    func testSearchableCopyAsksForTheNamedPDF() async throws {
        HTTPStub.always(.text("%PDF-1.7"))
        let service = await makeService()

        let data = try await service.downloadSearchable(name: "Order.pdf", folderName: "Bakshi")

        XCTAssertEqual(HTTPStub.lastRequest?.path, "/api/download-searchable")
        XCTAssertEqual(HTTPStub.lastRequest?.queryItems["folderName"], "Bakshi")
        XCTAssertEqual(HTTPStub.lastRequest?.queryItems["fileName"], "Order.pdf")
        XCTAssertEqual(data, Data("%PDF-1.7".utf8))
    }

    func testSearchableCopyAtTheRootSpellsItWithADot() async throws {
        HTTPStub.always(.text("%PDF-1.7"))
        let service = await makeService()

        _ = try await service.downloadSearchable(name: "Order.pdf", folderName: nil)

        XCTAssertEqual(HTTPStub.lastRequest?.queryItems["folderName"], ".")
    }

    func testSearchableCopyNotFoundIsAClearMessage() async {
        HTTPStub.always(.text("File not found", status: 404))
        let service = await makeService()

        do {
            _ = try await service.downloadSearchable(name: "Order.pdf", folderName: "Bakshi")
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(
                error as? APIError,
                .server(status: 404, message: "A searchable copy is not available for this document."))
        }
    }

    func testSearchableCopyOfANonPDFIsRefusedBeforeTheRequest() async {
        HTTPStub.always(.text("x"))
        let service = await makeService()

        do {
            _ = try await service.downloadSearchable(name: "Notes.docx", folderName: "Bakshi")
            XCTFail("expected a refusal")
        } catch {
            XCTAssertTrue(HTTPStub.seen.isEmpty)
        }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { defer { value += 1 }; return value } }
}

// MARK: - The view model

private final class OpsManager: FileManaging, @unchecked Sendable {
    var failure: Error?
    var ingestion: IngestState = .ready
    var searchable = Data("%PDF".utf8)
    private(set) var calls: [String] = []
    private(set) var movedFolders: [(path: String, parent: String?)] = []
    private(set) var reprocessed: [String] = []

    func delete(name: String, folderName: String?) async throws {}
    func rename(name: String, in folderName: String?, to newName: String) async throws
        -> FileOperationResult {
        FileOperationResult(fileName: newName, folderName: folderName ?? "")
    }
    func move(name: String, from folderName: String?, to destination: String?) async throws {}
    func setFavorite(_ favorite: Bool, name: String, folderName: String?) async throws -> Bool {
        favorite
    }
    func createFolder(named path: String) async throws {}
    func renameFolder(at path: String, to newName: String) async throws -> String { newName }
    func deleteFolder(named path: String) async throws {}

    func moveFolder(at path: String, toParent parent: String?) async throws -> String {
        calls.append("moveFolder")
        if let failure { throw failure }
        movedFolders.append((path, parent))
        return path
    }
    func reprocess(name: String, folderName: String?) async throws {
        calls.append("reprocess")
        if let failure { throw failure }
        reprocessed.append(name)
    }
    func awaitIngestion(name: String, folderName: String?) async throws -> IngestState {
        calls.append("await")
        return ingestion
    }
    func downloadSearchable(name: String, folderName: String?) async throws -> Data {
        calls.append("searchable")
        if let failure { throw failure }
        return searchable
    }
}

private func stored(_ path: String, status: String = "ready") -> FileNode.StoredFile {
    FileNode.StoredFile(
        name: String(path.split(separator: "/").last ?? ""), path: path, size: 1,
        modified: nil, status: status, favorite: false)
}

private func folderNode(_ path: String, _ children: [FileNode] = []) -> FileNode {
    .folder(FileNode.Folder(
        name: String(path.split(separator: "/").last ?? ""), path: path, files: children))
}

private let opsTree: [FileNode] = [
    folderNode("Bakshi", [
        .file(stored("Bakshi/Scan.pdf", status: "ERROR: could not read")),
        folderNode("Bakshi/2025"),
    ]),
    folderNode("Arora"),
]

@MainActor
private func withOps(
    _ body: @MainActor (FakeFiles, OpsManager, MyFilesViewModel) async -> Void
) async {
    let files = FakeFiles()
    files.tree = opsTree
    let manager = OpsManager()
    let model = MyFilesViewModel(service: files, manager: manager)
    await model.load()
    await body(files, manager, model)
}

final class FileOperationsViewModelTests: XCTestCase {

    func testMovingAFolderRefetchesTheTree() async {
        await withOps { files, manager, model in
            let before = files.treeCallCount
            await model.moveFolder(model.folder(at: "Bakshi/2025")!, to: model.folder(at: "Arora"))
            XCTAssertEqual(manager.movedFolders.first?.path, "Bakshi/2025")
            XCTAssertEqual(manager.movedFolders.first?.parent, "Arora")
            XCTAssertEqual(files.treeCallCount, before + 1)
            XCTAssertEqual(model.actionNotice, "Moved 2025 to Arora.")
        }
    }

    func testMovingToTheTopLevelSendsAnEmptyParent() async {
        await withOps { _, manager, model in
            await model.moveFolder(model.folder(at: "Bakshi/2025")!, to: nil)
            XCTAssertEqual(manager.movedFolders.first?.parent, "")
        }
    }

    func testAFolderCannotMoveIntoItselfItsChildOrWhereItIs() async {
        await withOps { _, manager, model in
            let bakshi = model.folder(at: "Bakshi")!
            await model.moveFolder(bakshi, to: bakshi)
            await model.moveFolder(bakshi, to: model.folder(at: "Bakshi/2025"))
            await model.moveFolder(bakshi, to: nil)
            XCTAssertTrue(manager.calls.isEmpty)
            let options = model.folderMoveDestinations(for: bakshi).map(\.path)
            XCTAssertEqual(options, ["Arora"])
            XCTAssertFalse(model.canMoveToTopLevel(bakshi))
            XCTAssertTrue(model.canMoveToTopLevel(model.folder(at: "Bakshi/2025")!))
        }
    }

    func testOnlyAFailedDocumentOffersReadingAgain() {
        XCTAssertTrue(MyFilesViewModel.readingFailed(stored("A/x.pdf", status: "ERROR: nope")))
        XCTAssertFalse(MyFilesViewModel.readingFailed(stored("A/x.pdf")))
    }

    func testReadingAgainFollowsTheJobThenRefetches() async {
        await withOps { files, manager, model in
            let before = files.treeCallCount
            await model.readAgain(stored("Bakshi/Scan.pdf", status: "ERROR: x"))
            XCTAssertEqual(manager.calls, ["reprocess", "await"])
            XCTAssertEqual(model.actionNotice, "Scan.pdf was read again.")
            XCTAssertEqual(files.treeCallCount, before + 1)
        }
    }

    func testReadingAgainThatFailsAgainSaysWhy() async {
        await withOps { _, manager, model in
            manager.ingestion = .failed("ERROR: still unreadable")
            await model.readAgain(stored("Bakshi/Scan.pdf", status: "ERROR: x"))
            XCTAssertEqual(model.actionError, "ERROR: still unreadable")
        }
    }

    func testTheSearchableCopyIsHandedToTheShareSheetUnderItsOwnName() async {
        await withOps { _, _, model in
            await model.prepareSearchableCopy(stored("Bakshi/Order.pdf"))
            XCTAssertEqual(model.sharing?.fileName, "Order_searchable.pdf")
            XCTAssertEqual(model.sharing?.data, Data("%PDF".utf8))
        }
    }

    func testAMissingSearchableCopyIsReportedNotShared() async {
        await withOps { _, manager, model in
            manager.failure = APIError.server(
                status: 404, message: "A searchable copy is not available for this document.")
            await model.prepareSearchableCopy(stored("Bakshi/Order.pdf"))
            XCTAssertNil(model.sharing)
            XCTAssertEqual(
                model.actionError, "A searchable copy is not available for this document.")
        }
    }
}
