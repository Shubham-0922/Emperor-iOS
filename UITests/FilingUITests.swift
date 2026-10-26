import XCTest

/// Filing Assembly against the stub server (`FilingStubs`): a draft picked, an annexure added,
/// verified, retyped and reordered, and a bundle assembled — or refused, with every reason.
/// Polled throughout, never slept on.
final class FilingUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testPickDraftShowsAnnexures() {
        let app = XCUIApplication.launchedSignedIn()
        XCTAssertTrue(app.openFilingAssembly(), "the Filing Assembly screen did not open")
        XCTAssertTrue(app.pickFilingDraft(), "the draft's annexures did not load")
        XCTAssertTrue(app.filingElement("filing-annexure-2").waitForExistence(timeout: 10))

        let change = app.buttons["filing-change-draft"].firstMatch
        app.reveal(change)
        XCTAssertTrue(change.waitForExistence(timeout: 5), "no way back to the draft list")
        change.tap()
        XCTAssertTrue(
            app.buttons["filing-draft-canvas_1"].firstMatch.waitForExistence(timeout: 10),
            "Change draft did not return to the list")
        XCTAssertFalse(app.filingElement("filing-annexure-1").exists)
    }

    func testAddAnnexureFromFiles() {
        let app = XCUIApplication.launchedSignedIn()
        XCTAssertTrue(app.openFilingAssembly())
        XCTAssertTrue(app.pickFilingDraft())

        let add = app.buttons["filing-add-annexure"].firstMatch
        app.reveal(add)
        XCTAssertTrue(add.waitForExistence(timeout: 10), "no Add annexure button")
        add.tap()
        // A file at the storage root: sent from the folder ".".
        let file = app.buttons["filing-file-Engagement_Letter.pdf"].firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 15), "the PDFs from My Files were not listed")
        XCTAssertFalse(
            app.buttons["filing-file-Board_Resolution.docx"].exists, "a Word file was offered")
        file.tap()

        let added = app.filingElement("filing-annexure-3")
        XCTAssertTrue(added.waitForExistence(timeout: 15), "the new annexure did not appear")
        XCTAssertTrue(poll { added.label.contains("P-3") }, "label: \(added.label)")
    }

    func testToggleVerifyAndTreatment() {
        let app = XCUIApplication.launchedSignedIn()
        XCTAssertTrue(app.openFilingAssembly())
        XCTAssertTrue(app.pickFilingDraft())

        let verify = app.buttons["filing-verify-2"].firstMatch
        app.reveal(verify)
        XCTAssertTrue(verify.waitForExistence(timeout: 10), "no verify control on the typed copy")
        XCTAssertTrue(verify.label.contains("pending"), "label: \(verify.label)")
        verify.tap()
        XCTAssertTrue(
            poll { verify.label.contains("verified against the original") },
            "the typed copy was not marked verified: \(verify.label)")

        // P-1 goes from its original pages to a typed copy, which then needs its own check.
        let treatment = app.filingElement("filing-treatment-1")
        app.reveal(treatment)
        XCTAssertTrue(treatment.waitForExistence(timeout: 10), "no treatment control")
        let typed = treatment.buttons["Typed copy"].firstMatch
        XCTAssertTrue(typed.waitForExistence(timeout: 5), "no Typed copy segment")
        typed.tap()
        XCTAssertTrue(
            app.buttons["filing-verify-1"].firstMatch.waitForExistence(timeout: 10),
            "a typed copy did not ask to be verified")
    }

    func testReorderShowsOrderWarning() {
        let app = XCUIApplication.launchedSignedIn()
        XCTAssertTrue(app.openFilingAssembly())
        XCTAssertTrue(app.pickFilingDraft())
        XCTAssertFalse(app.filingElement("filing-order-warning").exists)

        let first = app.filingElement("filing-annexure-1")
        app.reveal(first)
        first.press(forDuration: 1.2)
        let moveDown = app.buttons["Move down"].firstMatch
        XCTAssertTrue(moveDown.waitForExistence(timeout: 10), "no Move down in the row's menu")
        moveDown.tap()

        let warning = app.filingElement("filing-order-warning")
        XCTAssertTrue(warning.waitForExistence(timeout: 10), "no warning that the order left the marks")
        XCTAssertTrue(poll { warning.label.contains("(P-1, P-2)") }, "warning: \(warning.label)")
    }

    func testAssembleSuccessOpensBundle() {
        let app = XCUIApplication.launchedSignedIn()
        XCTAssertTrue(app.openFilingAssembly())
        XCTAssertTrue(app.pickFilingDraft())
        app.fillFilingField("filing-forum", "NCLT")
        XCTAssertTrue(app.assembleFiling(), "Assemble did not become available")

        let ok = app.filingElement("filing-result-ok")
        XCTAssertTrue(ok.waitForExistence(timeout: 20), "no assembled bundle")
        XCTAssertTrue(poll { ok.label.contains("42 pages") }, "title: \(ok.label)")
        XCTAssertTrue(app.filingElement("filing-checklist-affidavit").waitForExistence(timeout: 5))

        let open = app.buttons["filing-open-bundle"].firstMatch
        app.reveal(open)
        XCTAssertTrue(open.waitForExistence(timeout: 5), "no Open bundle")
        open.tap()
        let bar = app.navigationBars["Bundle #7"]
        XCTAssertTrue(bar.waitForExistence(timeout: 15), "the bundle did not open")
        XCTAssertTrue(
            app.buttons["filing-share-bundle"].firstMatch.waitForExistence(timeout: 10),
            "the bundle cannot be shared")
        bar.buttons["Done"].tap()
        XCTAssertTrue(app.waitGone(bar), "Done did not close the bundle")
    }

    func testAssembleFailureListsErrors() {
        let app = XCUIApplication.launchedSignedIn()
        XCTAssertTrue(app.openFilingAssembly())
        XCTAssertTrue(app.pickFilingDraft())
        app.fillFilingField("filing-forum", "NCLT")
        // The stub answers this case type as the server answers a missing source file.
        app.fillFilingField("filing-case-type", "Fail")
        XCTAssertTrue(app.assembleFiling())

        let failed = app.filingElement("filing-result-failed")
        XCTAssertTrue(failed.waitForExistence(timeout: 20), "no failure shown")
        let error = app.filingElement("filing-error-0")
        XCTAssertTrue(error.waitForExistence(timeout: 5), "the reason was not listed")
        XCTAssertTrue(
            poll { error.label.contains("source file is missing") }, "error: \(error.label)")
    }

    func testUnsupportedForumDisablesAssemble() {
        let app = XCUIApplication.launchedSignedIn()
        XCTAssertTrue(app.openFilingAssembly())
        XCTAssertTrue(app.pickFilingDraft())
        app.fillFilingField("filing-forum", "Arbitral Tribunal")

        let assemble = app.buttons["filing-assemble"].firstMatch
        app.reveal(assemble)
        XCTAssertTrue(assemble.waitForExistence(timeout: 10))
        XCTAssertTrue(poll { !assemble.isEnabled }, "Assemble stayed available for this forum")
        let hint = app.filingElement("filing-assemble-hint")
        XCTAssertTrue(hint.waitForExistence(timeout: 5), "no reason given")
        XCTAssertEqual(
            hint.label, "Assembly supports NCLT, NCLAT, High Court and Supreme Court covers")
    }
}

extension XCUIApplication {

    func filingElement(_ id: String) -> XCUIElement {
        descendants(matching: .any)[id].firstMatch
    }

    /// More → Filing Assembly, with its bar on screen.
    @discardableResult
    func openFilingAssembly() -> Bool {
        openCaseTool("filingAssembly")
        return navigationBars["Filing Assembly"].waitForExistence(timeout: 10)
    }

    /// Picks the stub's writ petition and waits for its first annexure.
    @discardableResult
    func pickFilingDraft() -> Bool {
        let draft = buttons["filing-draft-canvas_1"].firstMatch
        guard draft.waitForExistence(timeout: 15) else { return false }
        reveal(draft)
        draft.tap()
        return filingElement("filing-annexure-1").waitForExistence(timeout: 15)
    }

    /// Types into one of the cover's fields and ends with Return, which puts the keyboard away.
    func fillFilingField(_ id: String, _ text: String) {
        let field = textFields[id].firstMatch
        reveal(field)
        guard field.waitForExistence(timeout: 10) else { return }
        field.focusForTyping()
        field.typeText(text + "\n")
    }

    /// Taps Assemble once it is available; answers whether it was.
    @discardableResult
    func assembleFiling() -> Bool {
        let button = buttons["filing-assemble"].firstMatch
        reveal(button)
        guard button.waitForExistence(timeout: 10) else { return false }
        let deadline = Date().addingTimeInterval(10)
        while !button.isEnabled, Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
        guard button.isEnabled else { return false }
        button.tap()
        return true
    }
}
