import XCTest
@testable import EmperorCore

final class OCRJobDetailTests: XCTestCase {

    private func job(_ json: String) throws -> OCRJob {
        try JSONDecoder().decode(OCRJob.self, from: Data(json.utf8))
    }

    func testALayoutJobCarriesPagesAndNotes() throws {
        let job = try job(#"""
        {"status":"completed","targetLang":"Hindi","engine":"layout","pages":12,"digitalPages":9,"scannedPages":3,
         "warnings":["Page 4 could not be read as text and was kept as an image.","  ","Page 4 could not be read as text and was kept as an image.",
                     "2 passages could not be translated and were kept in the original."],
         "markdownFile":null,"outputFile":"1790000000000_Order_Hindi.docx"}
        """#)
        XCTAssertEqual(job.engine, "layout")
        XCTAssertEqual(job.pageSummary, "12 pages · 3 scanned")
        XCTAssertEqual(job.notes.count, 2, "blank and repeated notes are dropped")
        XCTAssertNil(job.markdownFile)
        XCTAssertTrue(job.translationMayBeIncomplete, "an untranslated passage is a caveat")
    }

    func testPageSummaryWording() throws {
        XCTAssertEqual(try job(#"{"status":"completed","pages":1,"scannedPages":0}"#).pageSummary, "1 page")
        XCTAssertEqual(try job(#"{"status":"completed","pages":4,"scannedPages":0}"#).pageSummary, "4 pages")
        XCTAssertNil(try job(#"{"status":"completed","pages":0,"digitalPages":0,"scannedPages":0}"#).pageSummary,
                     "a Word file reports zero pages")
        XCTAssertNil(try job(#"{"status":"completed"}"#).pageSummary)
    }

    func testTheFallbackPipelineHasNoPageFields() throws {
        let job = try job(#"{"status":"completed","outputFile":"1_a.docx","markdownFile":"1_a.md"}"#)
        XCTAssertEqual(job.markdownFile, "1_a.md")
        XCTAssertNil(job.pageSummary)
        XCTAssertTrue(job.notes.isEmpty)
    }

    func testAStrayWarningElementDoesNotCostTheJob() throws {
        let job = try job(#"{"status":"completed","warnings":["one",2,"three"],"pages":3}"#)
        XCTAssertEqual(job.warnings, ["one", "three"])
        XCTAssertEqual(job.pages, 3)
    }

    func testWarningsAreNotACaveatUnlessUntranslated() throws {
        let job = try job(#"{"status":"completed","targetLang":"Hindi","warnings":["Page 2 could not be read."]}"#)
        XCTAssertFalse(job.translationMayBeIncomplete)
    }
}
