import XCTest

/// A High Court on its own portal, against the stub server (`CasesStubs`): the Delhi High Court
/// searched on its own route, with no eCourts bench and no filing-number mode. Polled
/// throughout, never slept on.
final class CasesUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testDelhiHighCourtSearchesDedicated() {
        let app = XCUIApplication.launchedSignedIn()
        let matters = app.tab("Matters")
        XCTAssertTrue(matters.waitForExistence(timeout: 10))
        matters.tap()
        let newMatter = app.buttons["New matter"].firstMatch
        XCTAssertTrue(app.waitAndReveal(newMatter, timeout: 10), "no New matter")
        newMatter.tap()
        XCTAssertTrue(app.navigationBars["New matter"].waitForExistence(timeout: 10))
        let find = app.buttons["Find in court records"].firstMatch
        XCTAssertTrue(app.waitAndReveal(find, timeout: 10), "no Find in court records")
        find.tap()
        XCTAssertTrue(
            app.navigationBars["Find the case in court records"].waitForExistence(timeout: 10))

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
