import XCTest

/// Photographs a draft being edited and a Word document shown as its extracted text, in the dark
/// theme and the light one.
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

        let drafts = XCUIApplication.launchedSignedIn(["-UITestDraftEdit"], light: light)
        if drafts.openStubDraft(), drafts.editStubDraft(typing: " amended") {
            tourSnap(drafts, theme: theme, step: &step, "draft-editing")
        } else {
            tourSnap(drafts, theme: theme, step: &step, "draft-editing-not-reached")
        }
        drafts.terminate()

        let files = XCUIApplication.launchedSignedIn(["-UITestOfficeFails"], light: light)
        if files.openBoardResolution(),
           files.fileRouteElement("file-text-banner").waitForExistence(timeout: 15) {
            tourSnap(files, theme: theme, step: &step, "extracted-text")
        } else {
            tourSnap(files, theme: theme, step: &step, "extracted-text-not-reached")
        }
    }
}
