import XCTest

/// Fetch Orders photographed in both themes: the search, then a case read from its court.
/// Tolerates a missing control, as `ScreenshotTour` does: a tour that stops at the first surprise
/// shows nothing after it.
final class CasesTour: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testFetchOrdersDark() { tour(light: false) }
    func testFetchOrdersLight() { tour(light: true) }

    private func tour(light: Bool) {
        let app = XCUIApplication.launchedSignedIn([], light: light)
        let theme = light ? "light" : "dark"
        var step = 0
        app.openCaseTool("fetchOrders")
        guard app.navigationBars["Fetch Orders"].waitForExistence(timeout: 10) else { return }
        tourSnap(app, theme: theme, step: &step, "fetch-orders-search")

        app.fetchTheSupremeCourtCase(open: false)
        let title = app.descendants(matching: .any)["fetch-dossier-title"].firstMatch
        if title.waitForExistence(timeout: 20) {
            tourSnap(app, theme: theme, step: &step, "fetch-orders-dossier")
        }
    }
}
