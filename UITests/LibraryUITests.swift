import XCTest

extension XCUIApplication {

    /// Opens the Library from More: the tab, the row scrolled to, tapped — again, up to three taps
    /// in all, while the sheet has not come up. The row's label starts with its title and goes on
    /// with its subtitle.
    @discardableResult
    func openLibrary() -> Bool {
        let more = tab("More")
        guard more.waitForExistence(timeout: 10) else { return false }
        more.tap()
        let row = buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Library")).firstMatch
        guard waitAndReveal(row, timeout: 10) else { return false }
        let bar = navigationBars["Library"]
        for _ in 0..<3 {
            guard row.exists, row.isHittable else { break }
            row.tap()
            if bar.waitForExistence(timeout: 5) { break }
        }
        return bar.waitForExistence(timeout: 10)
    }

    /// Anything on screen by its accessibility identifier.
    func library(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// A Record search field by its prompt: a text view while it may wrap, a text field otherwise.
    func recordField(_ prompt: String) -> XCUIElement {
        textViews[prompt].exists ? textViews[prompt] : textFields[prompt]
    }

    /// Opens a document card on a home shelf, the shelf scrolled to first.
    func openShelfDocument(_ id: Int, shelf: String) -> Bool {
        let shelfElement = library("library-shelf-\(shelf)")
        if !shelfElement.waitForExistence(timeout: 5) { reveal(shelfElement) }
        guard shelfElement.waitForExistence(timeout: 15) else { return false }
        let card = library("library-doc-\(id)")
        if !card.waitForExistence(timeout: 15) { reveal(card) }
        guard waitAndReveal(card, timeout: 5) else { return false }
        guard card.isHittable else { return false }
        card.tap()
        return true
    }
}

/// The Library on the catalogue: shelves, search, Case Law's filters and pages, the judgment
/// reader and its fallback, the Act page, a missing file and a busy search — against the stub
/// catalogue in `LibraryStubs`.
final class LibraryUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func open() -> XCUIApplication {
        let app = XCUIApplication.launchedSignedIn()
        XCTAssertTrue(app.openLibrary(), "the Library should open from More")
        return app
    }

    func testHomeShowsShelvesAndOpensACategory() {
        let app = open()
        XCTAssertTrue(app.library("library-shelf-bare-acts").waitForExistence(timeout: 15))
        XCTAssertTrue(app.library("library-doc-2478").waitForExistence(timeout: 15), "the Bare Acts shelf has its Acts")
        let chip = app.library("library-category-case-law")
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.tap()
        XCTAssertTrue(app.navigationBars["Case law"].waitForExistence(timeout: 10))
        let count = app.library("library-count")
        XCTAssertTrue(count.waitForExistence(timeout: 15))
        XCTAssertTrue(poll { count.label.contains("45 judgments") }, "the count says what is there: \(count.label)")
    }

    func testSearchShowsCollectionsAndPassages() {
        let app = open()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.focusForTyping()
        search.typeText("penal\n")
        XCTAssertTrue(app.library("library-passages").waitForExistence(timeout: 15), "passages inside judgments")
        XCTAssertTrue(app.library("library-results-bare-acts").waitForExistence(timeout: 10))
        XCTAssertTrue(app.library("library-results-case-law").exists)
        XCTAssertTrue(app.staticTexts["Inside judgments"].exists || app.staticTexts["INSIDE JUDGMENTS"].exists)
    }

    func testCaseLawCourtFilterAndPaging() {
        let app = open()
        let chip = app.library("library-category-case-law")
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.tap()
        let label = app.library("library-page-label")
        XCTAssertTrue(label.waitForExistence(timeout: 15))
        XCTAssertTrue(poll { label.label.contains("Page 1 of 3") }, label.label)
        let next = app.library("library-page-next")
        for page in 2...3 {
            app.reveal(next)
            next.tap()
            XCTAssertTrue(poll(timeout: 15) { label.exists && label.label.contains("Page \(page) of 3") },
                          "page \(page): \(label.label)")
        }
        XCTAssertFalse(next.isEnabled, "no page after the last")

        let delhi = app.library("library-court-delhi")
        XCTAssertTrue(app.waitAndReveal(delhi, timeout: 10))
        delhi.tap()
        let count = app.library("library-count")
        XCTAssertTrue(poll(timeout: 15) { count.exists && count.label.contains("15 judgments") && count.label.contains("Delhi") },
                      count.label)
        XCTAssertTrue(app.library("library-active-court").waitForExistence(timeout: 5), "the court shows as a removable filter")
    }

    func testJudgmentReaderContentsAndFind() {
        let app = open()
        XCTAssertTrue(app.openShelfDocument(257708, shelf: "case-law"))
        XCTAssertTrue(app.library("judgment-block-h-1").waitForExistence(timeout: 15), "the judgment is typeset")

        let contents = app.library("library-contents")
        XCTAssertTrue(contents.waitForExistence(timeout: 5))
        contents.tap()
        let para10 = app.library("library-contents-para-10")
        XCTAssertTrue(para10.waitForExistence(timeout: 10))
        para10.tap()
        let block = app.library("judgment-block-para-10")
        let window = app.windows.firstMatch
        XCTAssertTrue(poll(timeout: 10) { block.exists && window.frame.intersects(block.frame) }, "Para 10 is scrolled to")

        app.library("library-find-toggle").tap()
        let field = app.recordField("Find in this judgment")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.focusForTyping()
        field.typeText("court")
        let count = app.library("library-find-count")
        XCTAssertTrue(poll(timeout: 10) { count.exists && count.label.hasPrefix("1 of ") }, "the matches are counted")
        app.library("library-find-next").tap()
        XCTAssertTrue(poll(timeout: 5) { count.label.hasPrefix("2 of ") }, count.label)
    }

    func testJudgmentFallsBackToPlainText() {
        let app = open()
        XCTAssertTrue(app.openShelfDocument(19655, shelf: "case-law"))
        XCTAssertTrue(app.library("library-plain-note").waitForExistence(timeout: 15),
                      "a judgment the formatter could not prepare is read as plain text, and says so")
        XCTAssertTrue(app.library("judgment-block-para-3").waitForExistence(timeout: 5))
    }

    func testActPageTabsAndRepealedRule() {
        let app = open()
        XCTAssertTrue(app.openShelfDocument(2478, shelf: "bare-acts"))
        XCTAssertTrue(app.library("library-act").waitForExistence(timeout: 15))
        let rules = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rules")).firstMatch
        XCTAssertTrue(rules.waitForExistence(timeout: 10), "the Rules tab, with its count")
        rules.tap()
        let repealed = app.library("library-instrument-2480")
        XCTAssertTrue(repealed.waitForExistence(timeout: 10))
        XCTAssertTrue(repealed.label.contains("Repealed"), "the repealed rule says so: \(repealed.label)")
        XCTAssertTrue(app.library("library-instrument-2479").label.contains("Latest"), "the latest rule is marked")
    }

    func testMissingPdfSaysNotOnShelf() {
        let app = open()
        XCTAssertTrue(app.openShelfDocument(999, shelf: "books-and-law-reports"))
        XCTAssertTrue(app.staticTexts["This document is not on the shelf yet"].waitForExistence(timeout: 15))
    }

    func testBusySearchRetries() {
        let app = open()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.focusForTyping()
        search.typeText("busy\n")
        // Refused as busy once; asked again after the server's five seconds.
        XCTAssertTrue(app.library("library-passages").waitForExistence(timeout: 25),
                      "a busy search is asked once more and then answers")
    }
}
