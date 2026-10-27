import XCTest
@testable import EmperorCore

/// A Word document the server could not convert, shown as its extracted text; and a folder
/// packed for sharing.
final class ExtractedTextTests: XCTestCase {

    private static func response(
        pages: [(Int, String)], exists: Bool? = true, total: Int? = nil,
        matchedBy: String? = "path", truncated: Bool? = false
    ) -> FileTextResponse {
        FileTextResponse(
            success: true, fileName: "Board_Resolution.docx", fileExists: exists,
            totalPages: total ?? pages.count, matchedBy: matchedBy, truncated: truncated,
            pages: pages.map { FileTextResponse.Page(page: $0.0, content: $0.1) }, error: nil)
    }

    func testLabelsComeFromTheWireNumbers() {
        let pages = ExtractedText.pages(from: Self.response(pages: [(3, "# Resolved"), (4, "Second")]))
        XCTAssertEqual(pages.map(\.label), ["Page 3", "Page 4"])
        XCTAssertTrue(pages[0].html.contains("Resolved"))
        XCTAssertTrue(pages[0].html.contains("<h1"))
    }

    func testAnEmptyPageSaysSo() {
        let pages = ExtractedText.pages(from: Self.response(pages: [(1, "  ")]))
        XCTAssertTrue(pages[0].html.contains("no text on this page"))
    }

    func testJoinedPagesCarryEveryLabel() {
        let html = ExtractedText.joinedHTML(from: Self.response(pages: [(1, "One"), (2, "Two")]))
        XCTAssertTrue(html.contains("Page 1"))
        XCTAssertTrue(html.contains("Page 2"))
    }

    func testNoticeSaysWhatThisIs() {
        let notice = ExtractedText.notice(for: Self.response(pages: [(1, "x")]))
        XCTAssertTrue(notice.hasPrefix("Rebuilt from extracted text — not the original document."))
        XCTAssertFalse(notice.contains("matched by file name"))
        XCTAssertFalse(notice.contains("Only the first"))
    }

    func testNoticeAddsTheNameMatchAndTruncation() {
        let notice = ExtractedText.notice(
            for: Self.response(pages: [(1, "a"), (2, "b")], total: 40, matchedBy: "name", truncated: true),
            conversionNote: "The converter is busy.")
        XCTAssertTrue(notice.hasPrefix("The converter is busy. Rebuilt from extracted text"))
        XCTAssertTrue(notice.contains(
            "The text was matched by file name, so it may come from another copy of a document with this name."))
        XCTAssertTrue(notice.hasSuffix("Only the first 2 of 40 pages are shown here."))
    }

    func testGoneAndNotYetAreTold() {
        XCTAssertNil(ExtractedText.emptyState(for: Self.response(pages: [(1, "x")])))
        XCTAssertEqual(ExtractedText.emptyState(for: Self.response(pages: [], exists: false)), .gone)
        XCTAssertEqual(ExtractedText.emptyState(for: Self.response(pages: [], exists: true)), .notYet)
        XCTAssertEqual(ExtractedText.emptyState(for: Self.response(pages: [], exists: nil)), .notYet)
    }

    // MARK: - The viewer falls back to it

    func testAFailedConversionOpensTheExtractedText() async {
        await viewer(textFails: false) { routes, model in
            await model.load()
            XCTAssertNil(model.data)
            XCTAssertNil(model.errorMessage)
            XCTAssertEqual(model.extractedText?.pages?.count, 1)
            XCTAssertEqual(routes.textRequests.first?.name, "Board_Resolution.docx")
            XCTAssertEqual(routes.textRequests.first?.folderName, "Arora_Holdings")
            XCTAssertTrue(model.extractedNotice?.contains("Rebuilt from extracted text") == true)
        }
    }

    func testWhenTheTextFailsTooTheConvertersReasonIsSaid() async {
        await viewer(textFails: true) { _, model in
            await model.load()
            XCTAssertNil(model.extractedText)
            XCTAssertNotNil(model.errorMessage)
        }
    }

    // MARK: - A folder as one archive

    private static let tree: [FileNode] = [
        folder("Bakshi", [
            .file(readyFile("Bakshi/Plaint.pdf")),
            folder("Bakshi/Orders", [.file(readyFile("Bakshi/Orders/Interim_Order.pdf"))]),
        ]),
        folder("Bakshi_Old", [.file(readyFile("Bakshi_Old/Note.pdf"))]),
        folder("Empty", []),
        .file(readyFile("Loose.pdf")),
    ]

    func testZipEntriesCoverEveryDepthAndNoNeighbour() {
        XCTAssertEqual(MyFilesViewModel.zipEntries(under: "Bakshi", in: Self.tree), [
            ZipEntry(folderName: "Bakshi", fileName: "Plaint.pdf"),
            ZipEntry(folderName: "Bakshi/Orders", fileName: "Interim_Order.pdf"),
        ])
        XCTAssertEqual(
            MyFilesViewModel.zipEntries(under: "", in: Self.tree).last,
            ZipEntry(folderName: ".", fileName: "Loose.pdf"))
        XCTAssertTrue(MyFilesViewModel.zipEntries(under: "Empty", in: Self.tree).isEmpty)
    }

    func testAFolderIsSharedAsItsZip() async {
        await myFiles(Self.tree) { routes, model in
            await model.load()
            let bakshi = FolderSummary(
                name: "Bakshi", path: "Bakshi", created: nil, documentCount: 2,
                subfolderCount: 1, childFolderCount: 1)
            await model.prepareZip(bakshi)
            XCTAssertEqual(routes.zipped.first?.count, 2)
            XCTAssertEqual(model.sharing?.fileName, "Bakshi.zip")
            XCTAssertEqual(model.sharing?.data, routes.zipData)

            let empty = FolderSummary(
                name: "Empty", path: "Empty", created: nil, documentCount: 0,
                subfolderCount: 0, childFolderCount: 0)
            await model.prepareZip(empty)
            XCTAssertEqual(model.actionNotice, MyFilesViewModel.emptyZipNotice)
            XCTAssertEqual(routes.zipped.count, 1)
        }
    }

    func testAZipFailureIsSaid() async {
        await myFiles(Self.tree) { routes, model in
            routes.zipError = APIError.server(status: 404, message: "None of the requested files were found")
            await model.load()
            let bakshi = FolderSummary(
                name: "Bakshi", path: "Bakshi", created: nil, documentCount: 2,
                subfolderCount: 1, childFolderCount: 1)
            await model.prepareZip(bakshi)
            XCTAssertNil(model.sharing)
            XCTAssertEqual(model.actionError, "None of the requested files were found")
        }
    }

    func testTooManyDocumentsAreNotZipped() async {
        let many = (0...MyFilesViewModel.zipLimit).map { FileNode.file(readyFile("Big/f\($0).pdf")) }
        await myFiles([folder("Big", many)]) { routes, model in
            await model.load()
            let big = FolderSummary(
                name: "Big", path: "Big", created: nil, documentCount: many.count,
                subfolderCount: 0, childFolderCount: 0)
            await model.prepareZip(big)
            XCTAssertTrue(routes.zipped.isEmpty)
            XCTAssertEqual(model.actionError, MyFilesViewModel.tooManyToZip)
        }
    }

    // MARK: - Helpers

    private func viewer(
        textFails: Bool, _ body: @MainActor (FakeFileRoutes, SourceDocumentViewModel) async -> Void
    ) async {
        await extractedViewer(textFails: textFails, body)
    }

    private func myFiles(
        _ tree: [FileNode], _ body: @MainActor (FakeFileRoutes, MyFilesViewModel) async -> Void
    ) async {
        await zipFiles(tree, body)
    }
}

private final class RefusingPreviews: OfficePreviewProviding, @unchecked Sendable {
    func preview(fileName: String, folderName: String?) async throws -> OfficePreview.Response {
        OfficePreview.Response(
            success: false, fileName: fileName, pages: nil, cached: nil, reason: "busy", error: nil)
    }

    func previewPDF(fileName: String, folderName: String?) async throws -> Data {
        throw APIError.transport("unused")
    }
}

@MainActor
private func extractedViewer(
    textFails: Bool, _ body: @MainActor (FakeFileRoutes, SourceDocumentViewModel) async -> Void
) async {
    let routes = FakeFileRoutes()
    routes.text = FileTextResponse(
        success: true, fileName: "Board_Resolution.docx", fileExists: true, totalPages: 1,
        matchedBy: "path", truncated: false,
        pages: [FileTextResponse.Page(page: 1, content: "# Resolved")], error: nil)
    if textFails { routes.textError = APIError.server(status: 500, message: "boom") }
    let model = SourceDocumentViewModel(
        attachment: ChatAttachment(name: "Board_Resolution.docx", folderName: "Arora_Holdings"),
        mention: AnnexureMention(fileName: "Board_Resolution.docx", mark: "", startPage: nil, endPage: nil),
        service: FakeFiles(),
        officePreview: RefusingPreviews(),
        fileText: routes)
    await body(routes, model)
}

@MainActor
private func zipFiles(
    _ tree: [FileNode], _ body: @MainActor (FakeFileRoutes, MyFilesViewModel) async -> Void
) async {
    let files = FakeFiles()
    files.tree = tree
    let routes = FakeFileRoutes()
    let model = MyFilesViewModel(service: files, manager: InertFileManager(), fileRoutes: routes)
    await body(routes, model)
}
