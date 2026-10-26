import XCTest

/// The analysis tools photographed in both themes: the intake, the Devil's Advocate report at its
/// top and at its weak spots, the Doc Index, the List of Dates chart and the History sheet.
/// Tolerates a missing control, as `ScreenshotTour` does: a tour that stops at the first surprise
/// shows nothing after it.
final class AnalysisTour: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testTheAnalysisToolsDark() { tour(light: false) }
    func testTheAnalysisToolsLight() { tour(light: true) }

    private func tour(light: Bool) {
        let theme = light ? "light" : "dark"
        var step = 0

        let app = XCUIApplication.launchedSignedIn([], light: light)
        app.openCaseTool("devilsAdvocate")
        guard app.buttons["analysis-run"].firstMatch.waitForExistence(timeout: 10) else { return }
        tourSnap(app, theme: theme, step: &step, "analysis-intake")
        if runOnBakshi(app), element(app, "da-report").waitForExistence(timeout: 15) {
            tourSnap(app, theme: theme, step: &step, "analysis-da-top")
            let weak = app.buttons["da-contents-weak"].firstMatch
            if weak.waitForExistence(timeout: 5) {
                weak.tap()
                tourSnap(app, theme: theme, step: &step, "analysis-da-weak-spots")
            }
        }
        let history = app.buttons["analysis-history"].firstMatch
        if history.waitForExistence(timeout: 5) {
            history.tap()
            if element(app, "analysis-history-sheet").waitForExistence(timeout: 10) {
                tourSnap(app, theme: theme, step: &step, "analysis-history")
            }
        }
        app.terminate()

        let index = XCUIApplication.launchedSignedIn([], light: light)
        index.openCaseTool("docIndex")
        if runOnBakshi(index), element(index, "di-table").waitForExistence(timeout: 15) {
            tourSnap(index, theme: theme, step: &step, "analysis-doc-index")
        }
        index.terminate()

        let dates = XCUIApplication.launchedSignedIn([], light: light)
        dates.openCaseTool("listOfDates")
        if runOnBakshi(dates), element(dates, "ld-chart").waitForExistence(timeout: 15) {
            tourSnap(dates, theme: theme, step: &step, "analysis-list-of-dates")
        }
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func runOnBakshi(_ app: XCUIApplication) -> Bool {
        let choose = app.buttons["analysis-choose-files"].firstMatch
        guard choose.waitForExistence(timeout: 10) else { return false }
        choose.tap()
        let picker = app.navigationBars["Documents"]
        guard picker.waitForExistence(timeout: 10) else { return false }
        let folder = app.buttons["Choose every document in Bakshi"].firstMatch
        app.reveal(folder)
        guard folder.waitForExistence(timeout: 10) else { return false }
        folder.tap()
        let attach = picker.buttons["Attach"]
        guard attach.waitForExistence(timeout: 5) else { return false }
        attach.tap()
        guard app.waitGone(picker) else { return false }
        let run = app.buttons["analysis-run"].firstMatch
        app.reveal(run)
        guard poll(until: { run.exists && run.isEnabled }) else { return false }
        run.tap()
        return true
    }
}
