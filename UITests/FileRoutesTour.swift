import XCTest

/// Photographs a Word document shown as its extracted text, and Home's maintenance notice, in the
/// dark theme and the light one.
final class FileRoutesTour: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testTheDarkFileRoutesTour() { tour(light: false) }
    func testTheLightFileRoutesTour() { tour(light: true) }

    private func tour(light: Bool) {
        let theme = light ? "light" : "dark"
        var step = 0

        let files = XCUIApplication.launchedSignedIn(["-UITestOfficeFails"], light: light)
        if files.openBoardResolution(),
           files.fileRouteElement("file-text-banner").waitForExistence(timeout: 15) {
            tourSnap(files, theme: theme, step: &step, "extracted-text")
        } else {
            tourSnap(files, theme: theme, step: &step, "extracted-text-not-reached")
        }
        files.terminate()

        let home = XCUIApplication.launchedSignedIn(["-UITestMaintenance"], light: light)
        _ = home.descendants(matching: .any).matching(identifier: "maintenance-banner").firstMatch
            .waitForExistence(timeout: 15)
        tourSnap(home, theme: theme, step: &step, "maintenance")
    }
}
