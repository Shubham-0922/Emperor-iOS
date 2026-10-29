import XCTest

extension XCUIApplication {

    func fileRouteElement(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// More → Files, on the library's top level.
    @discardableResult
    func openMyFiles() -> Bool {
        let more = tab("More")
        guard more.waitForExistence(timeout: 10) else { return false }
        more.tap()
        let files = buttons["Files"].firstMatch
        guard files.waitForExistence(timeout: 10) else { return false }
        reveal(files)
        files.tap()
        return navigationBars["Files"].waitForExistence(timeout: 10)
    }

    /// Files → Arora_Holdings → Board Resolution.docx, in the viewer.
    @discardableResult
    func openBoardResolution() -> Bool {
        guard openMyFiles() else { return false }
        let folder = buttons["folder-Arora_Holdings"]
        guard folder.waitForExistence(timeout: 10) else { return false }
        reveal(folder)
        folder.tap()
        guard navigationBars["Arora Holdings"].waitForExistence(timeout: 10)
            || navigationBars["Arora_Holdings"].waitForExistence(timeout: 2) else { return false }
        let document = staticTexts["Board Resolution.docx"]
        guard document.waitForExistence(timeout: 10) else { return false }
        document.tap()
        return true
    }
}

/// The small file routes: a Word document shown as its extracted text, and the maintenance
/// notice.
final class FileRoutesUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testWordFallbackShowsExtractedText() {
        let app = XCUIApplication.launchedSignedIn(["-UITestOfficeFails"])
        XCTAssertTrue(app.openBoardResolution(), "the Word document did not open")
        let banner = app.fileRouteElement("file-text-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "the extracted text did not stand in")
        XCTAssertTrue(banner.label.contains("Rebuilt from extracted text"), banner.label)
        XCTAssertTrue(app.fileRouteElement("file-text-page-1").exists)
        XCTAssertTrue(app.fileRouteElement("file-text-page-2").exists)
    }

    func testMaintenanceBanner() {
        let app = XCUIApplication.launchedSignedIn(["-UITestMaintenance"])
        let banner = app.fileRouteElement("maintenance-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "no maintenance notice on Home")
        XCTAssertTrue(banner.label.contains("Back at 6"), banner.label)
    }
}
