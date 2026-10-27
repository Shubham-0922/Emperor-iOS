import XCTest

/// A matter's content photographed in both themes: its conversations, its files, Attach from My
/// Files, and the chronology proposed from its documents. Tolerates a missing control, as
/// `ScreenshotTour` does.
final class MattersContentTour: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testTheMatterContentDark() { tour(light: false) }
    func testTheMatterContentLight() { tour(light: true) }

    private func tour(light: Bool) {
        let app = XCUIApplication.launchedSignedIn([], light: light)
        let theme = light ? "light" : "dark"
        var step = 0

        app.openMatter("prj-writ")
        guard app.matterElement("matter-header").waitForExistence(timeout: 10) else { return }

        app.openSection("ask")
        if app.matterElement("matter-chat-chat-writ").waitForExistence(timeout: 10) {
            tourSnap(app, theme: theme, step: &step, "matter-ask")
        }

        app.openSection("files")
        if app.matterElement("matter-file-Writ_Petition.pdf").waitForExistence(timeout: 10) {
            tourSnap(app, theme: theme, step: &step, "matter-files")
        }

        let confirm = app.openSheet(app.matterElement("matter-attach"), showing: "attach-confirm")
        if confirm.exists {
            _ = app.matterElement("attach-file-Plaint.pdf").waitForExistence(timeout: 10)
            tourSnap(app, theme: theme, step: &step, "attach-sheet")
            app.buttons["Cancel"].firstMatch.tap()
            app.waitGone(confirm)
        }

        app.openSection("chronology")
        let read = app.openSheet(app.matterElement("chronology-build"), showing: "chronology-build-read")
        if read.exists {
            read.tap()
            if app.matterElement("chronology-build-review").waitForExistence(timeout: 15) {
                tourSnap(app, theme: theme, step: &step, "chronology-build")
            }
        }
    }
}
