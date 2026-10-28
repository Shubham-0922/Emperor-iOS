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

    /// Drags the filing list down a little, at most three times, while `element` sits under the
    /// sheet's bar or within a touch of it. A list scrolled to bring a row on screen can leave
    /// it beneath the bar, where it still reads as hittable but a tap lands on the bar (as on an
    /// iPad's form sheet). The drag starts at the row's own height but beside it, at the list's
    /// trailing edge, so it never presses the control itself.
    func bringBelowBar(_ element: XCUIElement, bar: XCUIElement) {
        let list = filingElement("filing-screen")
        for _ in 0..<3 {
            guard element.exists, bar.exists, list.exists else { return }
            let row = element.frame
            guard row.minY < bar.frame.maxY + 24 else { return }
            let edge = list.frame
            let origin = coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            let y = max(row.midY, bar.frame.maxY + 30)
            let start = origin.withOffset(CGVector(dx: edge.maxX - 24, dy: y))
            let end = origin.withOffset(CGVector(dx: edge.maxX - 24, dy: y + 120))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
    }
}

/// Filing from a drafted document in a conversation (`FilingStubs`, `-UITestFilingChat`): the
/// assembler opened on the draft with its cover read from the cause title, and a file of the
/// conversation added in one tap.
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
        let bar = app.navigationBars["Assemble court-ready filing"]
        app.bringBelowBar(seed, bar: bar)
        seed.tap()

        // The screen scrolls the new row on screen itself, so it is waited for without swiping:
        // a swipe down on a sheet already at its top would close it. A tap that did not land is
        // given once more, clear of the bar — the same file again answers with the annexure it
        // already is, so it cannot add a second one (checked below).
        let added = app.filingElement("filing-annexure-3")
        if !added.waitForExistence(timeout: 8), seed.exists, seed.isHittable, seed.isEnabled {
            app.bringBelowBar(seed, bar: bar)
            seed.tap()
        }
        XCTAssertTrue(added.waitForExistence(timeout: 15), "the file did not become an annexure")
        XCTAssertTrue(poll { added.label.contains("P-10") }, "label: \(added.label)")
        XCTAssertTrue(app.waitGone(seed), "the file was still offered once added")
        XCTAssertFalse(app.filingElement("filing-annexure-4").exists, "the file was added twice")
    }
}
