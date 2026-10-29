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

    // MARK: - Helpers

    private func viewer(
        textFails: Bool, _ body: @MainActor (FakeFileRoutes, SourceDocumentViewModel) async -> Void
    ) async {
        await extractedViewer(textFails: textFails, body)
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
