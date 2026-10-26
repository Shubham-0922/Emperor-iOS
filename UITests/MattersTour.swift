import XCTest

/// Matters → All matters and a matter's workspace photographed in both themes: the list, then
/// each section of the stub's linked matter. Tolerates a missing control, as `ScreenshotTour`
/// does: a tour that stops at the first surprise shows nothing after it.
final class MattersTour: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testTheMattersDark() { tour(light: false) }
    func testTheMattersLight() { tour(light: true) }

    private func tour(light: Bool) {
        let app = XCUIApplication.launchedSignedIn([], light: light)
        let theme = light ? "light" : "dark"
        var step = 0

        app.openAllMatters()
        guard app.matterRow("prj-writ").waitForExistence(timeout: 10) else { return }
        tourSnap(app, theme: theme, step: &step, "matters-list")

        app.openMatter("prj-writ")
        guard app.matterElement("matter-header").waitForExistence(timeout: 10) else { return }
        tourSnap(app, theme: theme, step: &step, "matter-overview")

        let sections: [(String, String)] = [
            ("chronology", "matter-entry-u:upd-1"),
            ("court", "matter-court-row-ch-hearing"),
            ("tasks", "matter-task-tsk-limitation"),
            ("fees", "matter-fee-led-payment"),
            ("people", "matter-person-ppl-client"),
        ]
        for (section, row) in sections {
            app.openSection(section)
            _ = app.matterElement(row).waitForExistence(timeout: 5)
            tourSnap(app, theme: theme, step: &step, "matter-\(section)")
        }
    }
}
