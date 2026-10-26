import XCTest

/// OCR job detail (pages, notes) and the plan sheet's standing, meters and inclusions, driven by
/// the stub server's `-UITestOCRNotes` and `-UITestPlanDetail` answers.
final class OCRBillingUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// More → "OCR & Translate", then the Translate side, where the history is listed.
    private func openTranslateHistory(_ app: XCUIApplication) {
        let more = app.tab("More")
        XCTAssertTrue(more.waitForExistence(timeout: 10), "More is not on screen")
        more.tap()
        let row = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "OCR & Translate")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "More has no OCR & Translate row")
        app.reveal(row)
        row.tap()
        let modes = app.segmentedControls.firstMatch
        XCTAssertTrue(modes.waitForExistence(timeout: 10), "the OCR | Translate switch is missing")
        modes.buttons["Translate"].tap()
        XCTAssertTrue(app.navigationBars["Translate"].waitForExistence(timeout: 10))
    }

    func testHistoryRowShowsPagesAndNotes() {
        let app = XCUIApplication.launchedSignedIn(["-UITestOCRNotes"])
        openTranslateHistory(app)

        let notes = app.descendants(matching: .any)["ocr-row-notes-1790000000000"].firstMatch
        var swipes = 0
        while !notes.exists, swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(poll { notes.exists }, "the history row shows no notes")
        XCTAssertTrue(poll { notes.label.contains("Page 4") }, "the first note is missing: \(notes.label)")
        let pages = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "12 pages · 3 scanned")).firstMatch
        XCTAssertTrue(pages.exists, "the row does not give the page breakdown")
    }

    private func openPlanSheet(_ app: XCUIApplication) {
        let pill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Plan,")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "Home has no plan pill")
        XCTAssertFalse(pill.label.contains("Ultra"), "the pill shows an internal tier: \(pill.label)")
        XCTAssertFalse(pill.label.contains("PRO"), "the pill shows a placeholder: \(pill.label)")
        pill.tap()
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 10), "the plan sheet did not open")
    }

    func testPlanSheetShowsStandingAndIncludes() {
        let app = XCUIApplication.launchedSignedIn(["-UITestPlanDetail"])
        openPlanSheet(app)

        let standing = app.descendants(matching: .any)["plan-standing"].firstMatch
        XCTAssertTrue(standing.waitForExistence(timeout: 10), "the plan sheet shows no standing")
        XCTAssertTrue(poll { standing.label.contains("Expires in 5 days") }, "standing: \(standing.label)")

        let storage = app.descendants(matching: .any)["usage-meter-storage"].firstMatch
        var swipes = 0
        while !storage.exists, swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(storage.exists, "no storage meter")
        XCTAssertTrue(storage.label.contains("2.4 GB of 50 GB"), "storage reads: \(storage.label)")

        let includes = app.buttons["plan-includes"].firstMatch
        XCTAssertTrue(includes.waitForExistence(timeout: 10), "no \"What your plan includes\" row")
        app.reveal(includes)
        includes.tap()
        let support = app.staticTexts["Email support"].firstMatch
        XCTAssertTrue(poll { support.exists }, "the inclusions did not open")
        XCTAssertFalse(app.buttons["Upgrade"].exists, "the plan sheet sells")
        XCTAssertFalse(app.staticTexts["Upgrade"].exists, "the plan sheet sells")
    }

    func testPillNeverShowsInternalTier() {
        let app = XCUIApplication.launchedSignedIn(["-UITestPlanDetail"])
        openPlanSheet(app)
    }
}
