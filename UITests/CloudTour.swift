import XCTest

/// Photographs Connected services (not connected, then connected) and the import sheet, in the
/// dark theme and the light one.
final class CloudTour: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testTheDarkCloudTour() { tour(light: false) }
    func testTheLightCloudTour() { tour(light: true) }

    private func tour(light: Bool) {
        let theme = light ? "light" : "dark"
        var step = 0

        let app = XCUIApplication.launchedSignedIn(light: light)
        guard app.openConnectedServices() else {
            tourSnap(app, theme: theme, step: &step, "cloud-account-failed")
            return
        }
        tourSnap(app, theme: theme, step: &step, "cloud-account")

        let connect = app.buttons["cloud-connect-google"]
        if app.waitAndReveal(connect) {
            connect.tap()
            let page = app.cloudElement("cloud-browser-stub")
            if page.waitForExistence(timeout: 10) {
                tourSnap(app, theme: theme, step: &step, "cloud-browser")
                app.waitGone(page, timeout: 20)
            }
            _ = app.waitAndReveal(app.buttons["cloud-disconnect-google"])
            tourSnap(app, theme: theme, step: &step, "cloud-account-connected")
        }

        let files = XCUIApplication.launchedSignedIn(["-UITestCloudConnected"], light: light)
        guard files.openBakshiForCloud(), files.openCloudImport() else {
            tourSnap(files, theme: theme, step: &step, "cloud-import-failed")
            return
        }
        files.cloudElement("cloud-file-cf1").tap()
        tourSnap(files, theme: theme, step: &step, "cloud-import")
    }
}
