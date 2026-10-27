import XCTest
@testable import EmperorCore

/// "Filing ready": the list of annexures, each original attached or a line saying why not, the
/// progress the page reports, and the draft delivered even when the register cannot be reached.
final class FilingReadyExportTests: XCTestCase {

    private static let context = FilingChatContext(
        chatID: "c1", draftTitle: "Writ Petition",
        draftHTML: "<p>Body <@Order.pdf:P-1></p>", attachments: [])

    private static func fake() -> FakeFiling {
        let fake = FakeFiling()
        fake.rows = [
            FilingAnnexure(id: 1, chatID: "c1", mark: "P-1", title: "Order", sourceFilePath: "/s/Order.pdf"),
            FilingAnnexure(id: 2, chatID: "c1", mark: "P-2", title: "Notice", treatment: "typed",
                           verifyStatus: "pending"),
            FilingAnnexure(id: 3, chatID: "c1", mark: "P-3", title: "Order again",
                           duplicateOf: "P-1"),
            FilingAnnexure(id: 4, chatID: "c1", mark: "P-4", title: "Photo"),
        ]
        fake.typedCopiesHTML = "<h3>P-2</h3>"
        fake.originalAnswers = [
            "P-1": FilingOriginal(data: Data("%PDF-1.4".utf8), mime: "application/pdf"),
            "P-4": FilingOriginal(data: Data([0xFF, 0xD8]), mime: "image/jpeg"),
        ]
        fake.pageAnswers = [
            "P-1": FilingOriginalPages(success: true, pages: [.init(base64: "QQ==", mime: "image/jpeg")]),
            "P-3": FilingOriginalPages(success: true, duplicateOf: "P-1"),
            "P-4": FilingOriginalPages(success: false, error: "original-page rendering not available for .heic"),
        ]
        return fake
    }

    // MARK: - Markup

    func testTheListHasARowPerAnnexureInTheRegistersOrder() {
        let rows = [
            FilingAnnexure(id: 2, mark: "R-1", title: "A & B <draft>", treatment: "typed"),
            FilingAnnexure(id: 1, mark: "P-1", title: "Order"),
        ]
        let html = FilingReadyExport.listHTML(rows: rows)
        XCTAssertTrue(html.contains(
            "<tbody><tr><td>1.</td><td>R-1</td><td>A &amp; B &lt;draft&gt;</td><td>Typed copy (attached below)</td></tr>"
            + "<tr><td>2.</td><td>P-1</td><td>Order</td><td>Original (attached below)</td></tr></tbody>"))
        XCTAssertTrue(html.contains("<u>LIST OF ANNEXURES</u>"))
        XCTAssertEqual(FilingReadyExport.listHTML(rows: []), "")
    }

    func testAnOriginalIsItsPagesARepeatOrAFailureLine() {
        let pages = FilingReadyExport.originalHTML(
            mark: "P-1", pages: [.init(base64: "QQ==", mime: "image/png")], duplicateOf: nil, error: nil)
        XCTAssertTrue(pages.hasSuffix("<img src=\"data:image/png;base64,QQ==\" style=\"max-width:100%\"/>"))
        let repeat_ = FilingReadyExport.originalHTML(mark: "P-3", pages: [], duplicateOf: "P-1", error: nil)
        XCTAssertTrue(repeat_.contains("Same document and page range as Annexure P-1 above"))
        let failed = FilingReadyExport.originalHTML(mark: "P-4", pages: [], duplicateOf: nil, error: nil)
        XCTAssertTrue(failed.contains("color:#b00020\">Could not attach the original for this annexure.</p>"))
        XCTAssertTrue(failed.contains("ANNEXURE P-4 (ORIGINAL)"))
    }

    func testTheFileIsNamedForTheDraft() {
        XCTAssertEqual(FilingReadyExport.fileName(title: "Writ", format: .pdf), "Writ (filing ready).pdf")
        XCTAssertEqual(FilingReadyExport.fileName(title: " ", format: .word), "Document (filing ready).docx")
    }

    // MARK: - Building

    func testWordCarriesEveryPieceInOrderWithProgress() async {
        await exportModel(Self.fake()) { fake, model in
            let package = await model.build(.word)
            XCTAssertEqual(package.parts.count, 1)
            let html = package.html
            XCTAssertTrue(html.hasPrefix("<p>Body </p>"), "the draft first, its mentions stripped")
            let order = ["LIST OF ANNEXURES", "<h3>P-2</h3>", "ANNEXURE P-1 (ORIGINAL)",
                         "ANNEXURE P-3 (ORIGINAL)", "ANNEXURE P-4 (ORIGINAL)"]
            let positions = order.compactMap { html.range(of: $0)?.lowerBound }
            XCTAssertEqual(positions.count, order.count)
            XCTAssertEqual(positions, positions.sorted())
            XCTAssertTrue(html.contains("not available for .heic"))
            XCTAssertEqual(model.progressHistory, [8, 25, 45, 55, 65, 75, 75])
            XCTAssertEqual(fake.count("originalPages"), 3, "a typed copy has no original")
        }
    }

    func testAPDFAttachesTheOriginalsThemselves() async {
        await exportModel(Self.fake()) { fake, model in
            let package = await model.build(.pdf)
            XCTAssertEqual(package.parts.count, 4)
            guard case .html(let head) = package.parts[0] else { return XCTFail("no draft first") }
            XCTAssertTrue(head.contains("LIST OF ANNEXURES"))
            XCTAssertTrue(head.contains("<h3>P-2</h3>"))
            XCTAssertEqual(package.parts[1], .original(mark: "P-1", data: Data("%PDF-1.4".utf8), mime: "application/pdf"))
            guard case .html(let repeat_) = package.parts[2] else { return XCTFail("P-3 is not a note") }
            XCTAssertTrue(repeat_.contains("Same document and page range as Annexure P-1"))
            XCTAssertEqual(package.parts[3], .original(mark: "P-4", data: Data([0xFF, 0xD8]), mime: "image/jpeg"))
            XCTAssertEqual(fake.count("original"), 2, "a repeated mark is not fetched again")
        }
    }

    func testAnOriginalThatFailsIsALineNotAGap() async {
        let fake = Self.fake()
        fake.errors["original:P-1"] = APIError.server(status: 404, message: "source file missing on disk")
        fake.errors["original:P-4"] = FilingPreviewError.unpreviewable
        await exportModel(fake) { _, model in
            let package = await model.build(.pdf)
            XCTAssertEqual(package.parts.count, 4)
            guard case .html(let p1) = package.parts[1], case .html(let p4) = package.parts[3] else {
                return XCTFail("a failed original was dropped")
            }
            XCTAssertTrue(p1.contains("source file missing on disk"))
            XCTAssertTrue(p4.contains("ANNEXURE P-4 (ORIGINAL)"))
        }
    }

    func testAnUnreachableRegisterStillGivesTheDraft() async {
        let fake = Self.fake()
        fake.errors["*"] = APIError.transport("offline")
        await exportModel(fake) { _, model in
            let package = await model.build(.word)
            XCTAssertEqual(package.html, "<p>Body </p>")
            XCTAssertEqual(model.progressHistory, [8, 25, 45, 75])
        }
    }

    func testRunReportsTheFileAndAFailure() async {
        await exportModel(Self.fake()) { _, model in
            let url = URL(fileURLWithPath: "/tmp/x.pdf")
            let made = await model.run(.pdf) { package in
                XCTAssertEqual(package.format, .pdf)
                XCTAssertEqual(package.title, "Writ Petition")
                return url
            }
            XCTAssertEqual(made, url)
            XCTAssertEqual(model.result, url)
            XCTAssertEqual(model.progress, 100)
            XCTAssertFalse(model.isRunning)

            let none = await model.run(.word) { _ in nil }
            XCTAssertNil(none)
            XCTAssertEqual(model.failure, "Could not prepare the filing-ready Word file.")
            model.dismiss()
            XCTAssertNil(model.progress)
        }
    }
}

@MainActor
private func exportModel(
    _ fake: FakeFiling, _ body: @MainActor (FakeFiling, FilingReadyExportModel) async -> Void
) async {
    let context = FilingChatContext(
        chatID: "c1", draftTitle: "Writ Petition",
        draftHTML: "<p>Body <@Order.pdf:P-1></p>", attachments: [])
    await body(fake, FilingReadyExportModel(service: fake, context: context))
}
