import XCTest

extension XCUIApplication {

    /// Opens the stub's conversation from Home, where it is one row on every device (History
    /// on an iPad shows it beside its list, with no Back). Under `-UITestCitedSource` its answer
    /// cites page 2 of the reader's lease. Returns whether the conversation opened.
    func openCitedConversation() -> Bool {
        let home = tab("Home")
        guard home.waitForExistence(timeout: 10) else { return false }
        home.tap()
        let row = stubConversationRow
        guard waitAndReveal(row, timeout: 10) else { return false }
        row.tap()
        return navigationBars["Conversation"].waitForExistence(timeout: 10)
    }

    /// The reference's Open chip, scrolled to.
    func citedOpenChip() -> XCUIElement? {
        let chip = buttons["cite-open-1"].firstMatch
        guard waitAndReveal(chip, timeout: 15) else { return nil }
        return chip
    }

    /// The cited-page sheet is up, on page 2 of 3.
    func citedPageIsShowing(timeout: TimeInterval = 15) -> Bool {
        staticTexts["Page 2 of 3"].firstMatch.waitForExistence(timeout: timeout)
    }
}

/// A reference to one of the reader's documents opens it at the quoted words.
final class CitationUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The Open chip under the reference opens the lease at page 2 with the words marked, and
    /// the sheet says so.
    func testReferenceChipOpensQuotedPage() {
        let app = XCUIApplication.launchedSignedIn(["-UITestCitedSource"])
        XCTAssertTrue(app.openCitedConversation(), "the conversation did not open")
        let chip = app.citedOpenChip()
        XCTAssertNotNil(chip, "the reference has no Open chip")
        XCTAssertEqual(chip?.label, "Open Lease Agreement.pdf at page 2")
        chip?.tap()

        XCTAssertTrue(app.citedPageIsShowing(), "the document did not open at the cited page")
        let note = app.descendants(matching: .any).matching(identifier: "source-cited-note").firstMatch
        XCTAssertTrue(
            poll(timeout: 15) { note.exists && note.label.contains("The quoted words are highlighted.") },
            "the quoted words were not found and marked")
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "source-quote-note").firstMatch.exists,
            "no warning when the words are on the cited page")
    }

    /// The reference's number badge keeps its card to copy, and the card offers the document:
    /// "Open document" opens it once the card has gone.
    ///
    /// The badge inside the answer's sentence is not tapped here: where it falls in wrapped text
    /// differs by device and text size, and a guessed coordinate is not a deterministic test. It
    /// goes through the same `openCitedDocument` as the chip.
    func testBadgeOpensDocument() {
        let app = XCUIApplication.launchedSignedIn(["-UITestCitedSource"])
        XCTAssertTrue(app.openCitedConversation(), "the conversation did not open")
        XCTAssertNotNil(app.citedOpenChip(), "the answer did not load")
        let badge = app.buttons["Reference 1"].firstMatch
        XCTAssertTrue(app.waitAndReveal(badge, timeout: 10), "the reference has no number badge")
        badge.tap()

        let open = app.buttons["cite-card-open"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10), "the card does not offer the document")
        XCTAssertTrue(app.buttons["Copy"].firstMatch.exists, "the card lost its Copy")
        open.tap()
        XCTAssertTrue(app.citedPageIsShowing(), "the card did not open the document")
    }

    /// Under the answer, the line says its one citation was checked against its source.
    func testMetaLineSaysChecked() {
        let app = XCUIApplication.launchedSignedIn(["-UITestCitedSource"])
        XCTAssertTrue(app.openCitedConversation(), "the conversation did not open")
        let line = app.descendants(matching: .any).matching(identifier: "citation-meta-m2").firstMatch
        XCTAssertTrue(app.waitAndReveal(line, timeout: 15), "the answer has no citation line")
        XCTAssertTrue(
            poll(timeout: 15) { line.label.contains("1 citation · checked against source") },
            "the line says: \(line.label)")
    }

    /// A cited file the server cannot find is named, in the web's words, and nothing opens.
    func testMissingFileAlert() {
        let app = XCUIApplication.launchedSignedIn(["-UITestCitedSourceMissing"])
        XCTAssertTrue(app.openCitedConversation(), "the conversation did not open")
        app.citedOpenChip()?.tap()
        let alert = app.alerts["Cannot open that source"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "no alert for a missing file")
        XCTAssertTrue(
            alert.staticTexts[
                "“Lease_Agreement.pdf” is not among your documents, so it cannot be opened."
            ].exists,
            "the alert does not name the file as the web does")
        alert.buttons["OK"].tap()
        XCTAssertTrue(app.waitGone(alert))
        XCTAssertFalse(app.staticTexts["Page 2 of 3"].exists)
    }
}
