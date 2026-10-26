import XCTest

/// Filing Assembly photographed in both themes: the draft list, a draft's annexures and cover,
/// and an assembled bundle. Tolerates a missing control, as `ScreenshotTour` does: a tour that
/// stops at the first surprise shows nothing after it.
final class FilingTour: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testFilingAssemblyDark() { tour(light: false) }
    func testFilingAssemblyLight() { tour(light: true) }

    private func tour(light: Bool) {
        let app = XCUIApplication.launchedSignedIn([], light: light)
        let theme = light ? "light" : "dark"
        var step = 0
        guard app.openFilingAssembly() else { return }
        _ = app.buttons["filing-draft-canvas_1"].firstMatch.waitForExistence(timeout: 10)
        tourSnap(app, theme: theme, step: &step, "filing-drafts")

        guard app.pickFilingDraft() else { return }
        tourSnap(app, theme: theme, step: &step, "filing-annexures")

        app.fillFilingField("filing-forum", "NCLT")
        let assemble = app.buttons["filing-assemble"].firstMatch
        app.reveal(assemble)
        tourSnap(app, theme: theme, step: &step, "filing-cover")

        guard app.assembleFiling() else { return }
        let ok = app.filingElement("filing-result-ok")
        if ok.waitForExistence(timeout: 20) {
            app.reveal(ok)
            tourSnap(app, theme: theme, step: &step, "filing-result")
        }
    }
}
