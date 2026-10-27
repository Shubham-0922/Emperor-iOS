import XCTest

extension XCUIApplication {

    /// Opens the stub conversation whose answer carries a drafted writ petition
    /// (`-UITestFilingChat`), and the draft full screen. Returns whether the draft opened, with
    /// "Assemble filing" in its bar.
    func openFilingChatDraft() -> Bool {
        let home = tab("Home")
        guard home.waitForExistence(timeout: 10) else { return false }
        home.tap()
        let row = stubConversationRow
        guard waitAndReveal(row, timeout: 10) else { return false }
        row.tap()
        guard navigationBars["Conversation"].waitForExistence(timeout: 10) else { return false }
        let card = buttons.matching(NSPredicate(
            format: "identifier == %@ OR label BEGINSWITH %@", "artifact-card", "Draft:")).firstMatch
        guard waitAndReveal(card, timeout: 15) else { return false }
        card.tap()
        return buttons["artifact-assemble-filing"].firstMatch.waitForExistence(timeout: 10)
    }

    /// From the open draft, "Assemble filing" and its sheet.
    func openChatFiling() -> Bool {
        let assemble = buttons["artifact-assemble-filing"].firstMatch
        guard assemble.waitForExistence(timeout: 10) else { return false }
        assemble.tap()
        return navigationBars["Assemble court-ready filing"].waitForExistence(timeout: 10)
    }

    /// Opens one annexure's card under the draft; answers whether its viewer came up.
    func openAnnexureCard(_ mark: String) -> Bool {
        let card = buttons["filing-annexure-card-\(mark)"].firstMatch
        guard waitAndReveal(card, timeout: 15) else { return false }
        card.tap()
        return filingElement("filing-viewer").waitForExistence(timeout: 10)
    }

    /// Closes the annexure viewer by its Done.
    func closeAnnexureViewer(_ mark: String) {
        let bar = navigationBars["Annexure \(mark)"]
        guard bar.waitForExistence(timeout: 5) else { return }
        bar.buttons["Done"].tap()
        _ = waitGone(bar)
    }
}

/// Filing from a drafted document in a conversation (`FilingStubs`, `-UITestFilingChat`): the
/// assembler opened on the draft with its cover read from the cause title, a file of the
/// conversation added in one tap, each annexure opened from its card, and the filing-ready PDF.
final class FilingChatUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testAssembleFromArtifactPrefillsCover() {
        let app = XCUIApplication.launchedSignedIn(["-UITestFilingChat"])
        XCTAssertTrue(app.openFilingChatDraft(), "the draft did not open with Assemble filing")
        XCTAssertTrue(app.openChatFiling(), "the assembler did not open on the draft")

        XCTAssertTrue(
            app.waitAndReveal(app.filingElement("filing-annexure-101"), timeout: 15),
            "the conversation's annexures were not listed")
        XCTAssertFalse(app.buttons["filing-change-draft"].exists, "a draft list was offered")
        XCTAssertFalse(app.buttons["filing-reorder"].exists, "the conversation's order was offered for change")

        let forum = app.textFields["filing-forum"].firstMatch
        XCTAssertTrue(app.waitAndReveal(forum, timeout: 10), "no forum field")
        XCTAssertTrue(
            poll { (forum.value as? String) == "HIGH COURT" },
            "the forum was not read from the cause title: \(String(describing: forum.value))")
        let number = app.textFields["filing-case-number"].firstMatch
        XCTAssertTrue(
            poll { (number.value as? String) == "W.P.(C) No. 1234 of 2026" },
            "the case number was not read: \(String(describing: number.value))")

        XCTAssertTrue(app.assembleFiling(), "Assemble did not become available")
        let ok = app.filingElement("filing-result-ok")
        XCTAssertTrue(app.waitForFilingResult(ok), "no assembled bundle")
        XCTAssertTrue(poll { ok.label.contains("42 pages") }, "title: \(ok.label)")
    }

    func testSeedChipAddsAnnexure() {
        let app = XCUIApplication.launchedSignedIn(["-UITestFilingChat"])
        XCTAssertTrue(app.openFilingChatDraft())
        XCTAssertTrue(app.openChatFiling())

        let seed = app.buttons["filing-seed-Reply_Affidavit.pdf"].firstMatch
        XCTAssertTrue(app.waitAndReveal(seed, timeout: 15), "the conversation's file was not offered")
        XCTAssertFalse(
            app.buttons["filing-seed-Plaint.pdf"].exists, "a file already an annexure was offered")
        seed.tap()

        // The new row lands above the chips, on screen: waited for without scrolling, as a swipe
        // down on a sheet already at its top would close it. A tap the sheet swallowed is given
        // once more — the same file again answers with the annexure it already is, so it cannot
        // add a second one (checked below).
        let added = app.filingElement("filing-annexure-3")
        if !added.waitForExistence(timeout: 8), seed.exists, seed.isHittable, seed.isEnabled {
            seed.tap()
        }
        XCTAssertTrue(app.waitAndReveal(added, timeout: 15), "the file did not become an annexure")
        XCTAssertTrue(poll { added.label.contains("P-10") }, "label: \(added.label)")
        XCTAssertTrue(app.waitGone(seed), "the file was still offered once added")
        XCTAssertFalse(app.filingElement("filing-annexure-4").exists, "the file was added twice")
    }

    func testAnnexureViewerTypedAndOriginal() {
        let app = XCUIApplication.launchedSignedIn(["-UITestFilingChat"])
        XCTAssertTrue(app.openFilingChatDraft())

        XCTAssertTrue(app.openAnnexureCard("P-2"), "the typed copy did not open")
        XCTAssertTrue(
            app.filingElement("filing-viewer-typed").waitForExistence(timeout: 15),
            "the typed copy was not shown")
        app.closeAnnexureViewer("P-2")

        XCTAssertTrue(app.openAnnexureCard("P-1"), "the original did not open")
        XCTAssertTrue(
            app.filingElement("filing-viewer-pdf").waitForExistence(timeout: 15),
            "the original's PDF was not shown")
        app.closeAnnexureViewer("P-1")

        XCTAssertTrue(app.openAnnexureCard("P-9"), "the photograph did not open")
        let unpreviewable = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ OR label CONTAINS %@",
            "filing-viewer-unpreviewable", "can't be previewed here")).firstMatch
        XCTAssertTrue(
            unpreviewable.waitForExistence(timeout: 15), "no word that the file cannot be shown")
    }

    func testFilingReadyPDFProducesShare() {
        let app = XCUIApplication.launchedSignedIn(["-UITestFilingChat"])
        XCTAssertTrue(app.openFilingChatDraft())

        let menu = app.buttons["Download this document"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "no download menu")
        menu.tap()
        let item = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "filing-ready-pdf", "Filing ready · PDF")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), "no Filing ready · PDF in the menu")
        item.tap()

        let share = app.buttons["filing-export-share"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 45), "the filing-ready PDF was not offered to share")
    }
}
