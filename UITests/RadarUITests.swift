import XCTest

/// The Limitation Radar, against the stub server: the form's refusal, the amber and red answers,
/// and a refusal worded by the server. Polled throughout, never slept on.
final class RadarUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testRunWithoutDatesSaysWhatIsMissing() {
        let app = XCUIApplication.launchedSignedIn()
        app.openCaseTool("limitationRadar")
        run(app)
        let error = element(app, "radar-error")
        XCTAssertTrue(error.waitForExistence(timeout: 10), "no message about the missing dates")
        XCTAssertEqual(error.label, "Enter the date time began to run and the filing date.")
    }

    func testAuditShowsBannerFindingsAndSteps() {
        let app = XCUIApplication.launchedSignedIn()
        app.openCaseTool("limitationRadar")
        addDates(app)
        run(app)
        let banner = element(app, "radar-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "no outcome banner")
        XCTAssertTrue(
            poll { banner.label.contains("remaining with it") }, "banner: \(banner.label)")
        XCTAssertTrue(element(app, "radar-step-1").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "radar-findings").exists)
    }

    func testBarredProfileShowsRedOutcome() {
        let app = XCUIApplication.launchedSignedIn()
        app.openCaseTool("limitationRadar")
        choose("Any other suit (residuary)", in: app)
        addDates(app)
        run(app)
        let banner = element(app, "radar-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "no outcome banner")
        XCTAssertTrue(
            poll { banner.label.contains("LEGALLY BARRED") }, "banner: \(banner.label)")
    }

    func testServerRefusalMessageIsShown() {
        let app = XCUIApplication.launchedSignedIn()
        app.openCaseTool("limitationRadar")
        choose("Any other declaration", in: app)
        addDates(app)
        run(app)
        let error = element(app, "radar-error")
        XCTAssertTrue(error.waitForExistence(timeout: 10), "the refusal was not shown")
        XCTAssertTrue(
            poll { error.label.contains("earlier than the cause of action") },
            "message: \(error.label)")
    }

    func testDoneClosesTheScreen() {
        let app = XCUIApplication.launchedSignedIn()
        app.openCaseTool("limitationRadar")
        let bar = app.navigationBars["Limitation Radar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        bar.buttons["Done"].tap()
        XCTAssertTrue(app.waitGone(bar), "Done did not close the screen")
    }

    // MARK: - Steps

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func addDates(_ app: XCUIApplication) {
        for id in ["radar-cause", "radar-filing"] {
            let add = app.buttons[id].firstMatch
            XCTAssertTrue(app.waitAndReveal(add, timeout: 10), "no \(id) field")
            add.tap()
            // The button is replaced by a date picker and its clear button.
            XCTAssertTrue(
                element(app, "\(id)-clear").waitForExistence(timeout: 10),
                "\(id) did not take a date")
        }
    }

    private func choose(_ prefix: String, in app: XCUIApplication) {
        let menu = app.buttons["radar-profile"].firstMatch
        XCTAssertTrue(app.waitAndReveal(menu, timeout: 10), "no suit picker")
        menu.tap()
        let option = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10), "no option \(prefix)")
        option.tap()
    }

    private func run(_ app: XCUIApplication) {
        let button = app.buttons["radar-run"].firstMatch
        XCTAssertTrue(app.waitAndReveal(button, timeout: 10), "no run button")
        button.tap()
    }
}
