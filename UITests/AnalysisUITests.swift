import XCTest

/// Devil's Advocate, Doc Index and List of Dates against the stub server: a run on documents
/// picked from My Files, each tool's result, History, and a plan refusal. Polled throughout,
/// never slept on.
final class AnalysisUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testDocIndexRunsOnMyFilesDocuments() {
        let app = XCUIApplication.launchedSignedIn()
        app.openCaseTool("docIndex")
        runOnBakshi(app)
        let table = element(app, "di-table")
        XCTAssertTrue(table.waitForExistence(timeout: 15), "the index did not arrive")
        XCTAssertTrue(poll { rows(app).count == 3 }, "rows: \(rows(app).count)")

        // The search field wraps, so it may read as a text view rather than a text field.
        let placeholder = "Search every column"
        let field = app.textViews[placeholder].exists
            ? app.textViews[placeholder] : app.textFields[placeholder]
        app.reveal(field)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no search field")
        field.focusForTyping()
        field.typeText("notice")
        XCTAssertTrue(poll { rows(app).count == 1 }, "search left \(rows(app).count) rows")
    }

    func testListOfDatesFiltersAndCopies() {
        let app = XCUIApplication.launchedSignedIn()
        app.openCaseTool("listOfDates")
        runOnBakshi(app)
        let chart = element(app, "ld-chart")
        XCTAssertTrue(chart.waitForExistence(timeout: 15), "the list of dates did not arrive")
        let count = element(app, "ld-count")
        XCTAssertTrue(poll { count.label == "5 of 5" }, "count: \(count.label)")

        let adverse = app.buttons["ld-filter-adverse"].firstMatch
        app.reveal(adverse)
        adverse.tap()
        XCTAssertTrue(poll { count.label == "1 of 5" }, "count after the chip: \(count.label)")
        XCTAssertTrue(element(app, "ld-entry-1").waitForExistence(timeout: 5), "the adverse entry is not shown")

        let copy = app.buttons["ld-copy"].firstMatch
        app.reveal(copy)
        copy.tap()
        XCTAssertTrue(app.staticTexts["Copied"].waitForExistence(timeout: 5), "no Copied toast")
    }

    func testDevilsAdvocatePinJumpsToSpotAndChecklistCounts() {
        let app = XCUIApplication.launchedSignedIn()
        app.openCaseTool("devilsAdvocate")
        runOnBakshi(app)
        let report = element(app, "da-report")
        XCTAssertTrue(report.waitForExistence(timeout: 15), "the report did not arrive")

        let pin = app.buttons["da-pin-2"].firstMatch
        app.reveal(pin)
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "no pin for weak spot 2")
        pin.tap()
        let spot = element(app, "da-spot-2")
        XCTAssertTrue(poll { spot.exists && spot.isHittable }, "the pin did not bring weak spot 2 into view")
        let fix = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "File the postal receipt")).firstMatch
        XCTAssertTrue(fix.waitForExistence(timeout: 5), "weak spot 2 did not open")

        let counter = element(app, "da-checklist-count")
        app.reveal(counter)
        XCTAssertTrue(poll { counter.label == "1 of 3 done" }, "checklist: \(counter.label)")
        let check = app.switches["da-check-c2"].firstMatch
        app.reveal(check)
        XCTAssertTrue(check.waitForExistence(timeout: 5), "no checklist item c2")
        // The switch itself, at the trailing edge: a tap on the row's words does not toggle it.
        check.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertTrue(poll { counter.label == "2 of 3 done" }, "checklist after a tick: \(counter.label)")
    }

    func testHistoryOpensSavedRunAndDeletes() {
        let app = XCUIApplication.launchedSignedIn()
        app.openCaseTool("docIndex")
        let history = app.buttons["analysis-history"].firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 10), "no History button")
        history.tap()
        let seed = element(app, "analysis-history-row-anr_seed_doc-index")
        XCTAssertTrue(seed.waitForExistence(timeout: 10), "the seeded run is not listed")

        let open = app.buttons["analysis-history-open-anr_seed_doc-index"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(element(app, "analysis-history-banner").waitForExistence(timeout: 10), "no history banner")
        XCTAssertTrue(element(app, "di-table").exists, "the stored index is not shown")

        XCTAssertTrue(app.waitGone(seed), "the History sheet did not close")
        // Again, up to three taps: the first can land while the sheet is still leaving.
        for _ in 0..<3 where !seed.exists {
            if history.isHittable { history.tap() }
            if seed.waitForExistence(timeout: 5) { break }
        }
        XCTAssertTrue(seed.exists, "History did not open again")
        let delete = app.buttons["analysis-history-delete-anr_seed_doc-index"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no confirmation")
        confirm.tap()
        XCTAssertTrue(app.waitGone(seed), "the run was not deleted")
    }

    func testQueryLimitOffersPlansNotRetry() {
        let app = XCUIApplication.launchedSignedIn(["-UITestAnalysisLimit"])
        app.openCaseTool("listOfDates")
        runOnBakshi(app)
        let error = element(app, "analysis-error")
        XCTAssertTrue(error.waitForExistence(timeout: 15), "no refusal")
        XCTAssertFalse(app.buttons["analysis-retry"].exists, "a plan refusal offered Try again")
        XCTAssertTrue(app.buttons["analysis-start-over"].exists)
    }

    func testRunNeedsADocument() {
        let app = XCUIApplication.launchedSignedIn()
        app.openCaseTool("devilsAdvocate")
        let run = app.buttons["analysis-run"].firstMatch
        app.reveal(run)
        XCTAssertTrue(run.waitForExistence(timeout: 10), "no run button")
        XCTAssertFalse(run.isEnabled, "the run button works with no document")
        XCTAssertTrue(app.staticTexts["Choose at least one document to begin."].exists)
    }

    // MARK: - Steps

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func rows(_ app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "di-row-"))
            .allElementsBoundByIndex
    }

    /// Chooses every document in the stub's Bakshi folder, attaches them, and runs the tool.
    private func runOnBakshi(_ app: XCUIApplication) {
        let choose = app.buttons["analysis-choose-files"].firstMatch
        XCTAssertTrue(choose.waitForExistence(timeout: 10), "no Choose from My Files")
        choose.tap()
        let picker = app.navigationBars["Documents"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "the My Files picker did not open")
        let folder = app.buttons["Choose every document in Bakshi"].firstMatch
        app.reveal(folder)
        XCTAssertTrue(folder.waitForExistence(timeout: 10), "no Bakshi folder")
        folder.tap()
        let attach = picker.buttons["Attach"]
        XCTAssertTrue(attach.waitForExistence(timeout: 5), "nothing to attach")
        attach.tap()
        XCTAssertTrue(app.waitGone(picker), "the picker did not close")
        let run = app.buttons["analysis-run"].firstMatch
        app.reveal(run)
        XCTAssertTrue(poll { run.exists && run.isEnabled }, "the run button stayed off")
        run.tap()
    }
}
