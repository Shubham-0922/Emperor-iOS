import XCTest

/// The Limitation Radar photographed in both themes: empty, amber answer, red answer. Tolerates a
/// missing control, as `ScreenshotTour` does: a tour that stops at the first surprise shows
/// nothing after it.
final class RadarTour: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testTheRadarDark() { tour(light: false) }
    func testTheRadarLight() { tour(light: true) }

    private func tour(light: Bool) {
        let app = XCUIApplication.launchedSignedIn([], light: light)
        let theme = light ? "light" : "dark"
        var step = 0
        app.openCaseTool("limitationRadar")
        guard app.navigationBars["Limitation Radar"].waitForExistence(timeout: 10) else { return }
        tourSnap(app, theme: theme, step: &step, "radar-empty")

        addDates(app)
        run(app)
        let banner = app.descendants(matching: .any)["radar-banner"].firstMatch
        if banner.waitForExistence(timeout: 10) {
            tourSnap(app, theme: theme, step: &step, "radar-result-amber")
        }

        // The residuary answer is the stub's red one.
        let menu = app.buttons["radar-profile"].firstMatch
        app.reveal(menu)
        guard menu.waitForExistence(timeout: 5) else { return }
        menu.tap()
        let option = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Any other suit (residuary)")).firstMatch
        guard option.waitForExistence(timeout: 5) else { return }
        option.tap()
        run(app)
        if poll(until: {
            banner.exists && banner.label.contains("LEGALLY BARRED")
        }) {
            tourSnap(app, theme: theme, step: &step, "radar-result-red")
        }
    }

    private func addDates(_ app: XCUIApplication) {
        for id in ["radar-cause", "radar-filing"] {
            let add = app.buttons[id].firstMatch
            app.reveal(add)
            guard add.waitForExistence(timeout: 5) else { continue }
            add.tap()
            _ = app.descendants(matching: .any)["\(id)-clear"].firstMatch
                .waitForExistence(timeout: 5)
        }
    }

    private func run(_ app: XCUIApplication) {
        let button = app.buttons["radar-run"].firstMatch
        app.reveal(button)
        if button.waitForExistence(timeout: 5) { button.tap() }
    }
}
