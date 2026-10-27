import XCTest

/// Fetch Orders and the High Courts on their own portals, against the stub server: a case read
/// from its court, a number the court does not have, Add to Matters, and the Delhi High Court
/// searched on its own route. Polled throughout, never slept on.
final class CasesUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testFetchOrdersReadsCase() {
        let app = XCUIApplication.launchedSignedIn()
        app.fetchTheSupremeCourtCase()
        let order = app.descendants(matching: .any)["fetch-order-0"].firstMatch
        XCTAssertTrue(app.waitAndReveal(order, timeout: 20), "the court's orders were not shown")
        let title = app.descendants(matching: .any)["fetch-dossier-title"].firstMatch
        XCTAssertTrue(title.exists, "the dossier has no title")
        // The second order carries no copy online.
        let second = app.descendants(matching: .any)["fetch-order-1"].firstMatch
        XCTAssertTrue(app.waitAndReveal(second, timeout: 5))
        XCTAssertTrue(app.staticTexts["No copy online"].firstMatch.exists)
    }

    func testFetchOrdersNotFoundHasNoRetry() {
        let app = XCUIApplication.launchedSignedIn(["-UITestLookupNotFound"])
        app.fetchTheSupremeCourtCase()
        let title = app.staticTexts["The court has nothing under that number."].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 20), "the not-found card was not shown")
        XCTAssertFalse(app.buttons["fetch-retry"].exists, "a number the court lacks offers Try again")
        let again = app.buttons["fetch-search-again"].firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        again.tap()
        XCTAssertTrue(
            app.buttons["court-picker"].firstMatch.waitForExistence(timeout: 10),
            "Search again did not go back to the search")
    }

    func testFetchOrdersAddToMattersOpensMatter() {
        let app = XCUIApplication.launchedSignedIn()
        app.fetchTheSupremeCourtCase()
        let cta = app.buttons["fetch-cta"].firstMatch
        XCTAssertTrue(app.waitAndReveal(cta, timeout: 20), "no Add to Matters")
        XCTAssertTrue(poll { cta.label.contains("Add to Matters") }, "cta: \(cta.label)")
        cta.tap()

        let add = app.buttons["add-to-matters-add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the Add to Matters sheet did not open")
        XCTAssertTrue(poll { add.isEnabled }, "Add to Matters stayed disabled")
        add.tap()
        XCTAssertTrue(app.waitGone(add, timeout: 20), "the sheet did not close")
        XCTAssertTrue(
            app.waitGone(app.navigationBars["Fetch Orders"], timeout: 10), "Fetch Orders did not close")

        let matter = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Ramesh Kumar")).firstMatch
        XCTAssertTrue(matter.waitForExistence(timeout: 15), "the new matter was not opened")
    }

    func testDelhiHighCourtSearchesDedicated() {
        let app = XCUIApplication.launchedSignedIn()
        let matters = app.tab("Matters")
        XCTAssertTrue(matters.waitForExistence(timeout: 10))
        matters.tap()
        let addMatter = app.buttons["Add a matter"].firstMatch
        XCTAssertTrue(app.waitAndReveal(addMatter, timeout: 10), "no Add a matter")
        addMatter.tap()
        XCTAssertTrue(app.navigationBars["Find a case"].waitForExistence(timeout: 10))

        app.chooseCourt("Delhi", id: "court-hc-delhi")

        let caseType = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Case type")).firstMatch
        XCTAssertTrue(caseType.waitForExistence(timeout: 10), "the Delhi case types did not load")
        // A dedicated portal asks for no eCourts bench, and has no filing-number lookup.
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bench")).firstMatch.exists,
            "a Bench row was offered for the Delhi High Court")
        XCTAssertFalse(app.buttons["By filing number"].exists, "a filing-number mode was offered")

        caseType.tap()
        let option = app.buttons["W.P.(C)"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "the case type menu did not open")
        option.tap()

        app.enter("4410", into: app.textFields["Case number"].firstMatch)
        app.enter("2025", into: app.textFields["Year"].firstMatch)
        let search = app.buttons["Search the court"].firstMatch
        XCTAssertTrue(app.waitAndReveal(search, timeout: 5))
        search.tap()

        let found = app.staticTexts["Mehta Traders vs. Union of India"].firstMatch
        XCTAssertTrue(app.waitAndReveal(found, timeout: 20), "the Delhi case was not found")
    }
}

extension XCUIApplication {

    /// More → Fetch Orders (unless `open` is false: already there), then the stub's Supreme Court
    /// case by diary number, then "Fetch this case".
    func fetchTheSupremeCourtCase(open: Bool = true) {
        if open { openCaseTool("fetchOrders") }
        XCTAssertTrue(navigationBars["Fetch Orders"].waitForExistence(timeout: 10), "Fetch Orders did not open")
        chooseCourt("Supreme", id: "court-sc")

        let diary = buttons["By diary number"].firstMatch
        XCTAssertTrue(waitAndReveal(diary, timeout: 5), "no diary-number mode")
        diary.tap()
        enter("52650", into: textFields["Diary number"].firstMatch)
        enter("2023", into: textFields["Year"].firstMatch)

        let search = buttons["Search the court"].firstMatch
        XCTAssertTrue(waitAndReveal(search, timeout: 5))
        search.tap()

        let fetch = buttons["court-result-pick"].firstMatch
        XCTAssertTrue(waitAndReveal(fetch, timeout: 20), "no Fetch this case on the result")
        fetch.tap()
    }

    /// Opens the court picker, filters it by `filter`, and chooses the court `id` names.
    func chooseCourt(_ filter: String, id: String) {
        let picker = buttons["court-picker"].firstMatch
        XCTAssertTrue(waitAndReveal(picker, timeout: 10), "no court picker")
        picker.tap()
        XCTAssertTrue(navigationBars["Court"].waitForExistence(timeout: 5), "the court picker did not open")
        let search = searchFields["Search courts"].firstMatch
        if search.waitForExistence(timeout: 5) {
            search.focusForTyping()
            search.typeText(filter)
        }
        let court = buttons[id].firstMatch
        XCTAssertTrue(court.waitForExistence(timeout: 5), "no \(id) in the picker")
        court.tap()
        XCTAssertTrue(waitGone(navigationBars["Court"], timeout: 5), "the picker did not close")
    }

    /// Focuses a field (scrolled to first) and types into it.
    func enter(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(waitAndReveal(field, timeout: 10), "no field \(field)")
        field.focusForTyping()
        field.typeText(text)
    }
}
