import XCTest

/// Photographs an answer citing one of the reader's documents and the document opened at the
/// quoted words, in the dark theme and the light one.
final class CitationTour: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testTheDarkCitationTour() { tour(light: false) }
    func testTheLightCitationTour() { tour(light: true) }

    private func tour(light: Bool) {
        let app = XCUIApplication.launchedSignedIn(["-UITestCitedSource"], light: light)
        let theme = light ? "light" : "dark"
        var step = 0
        guard app.openCitedConversation(), let chip = app.citedOpenChip() else {
            tourSnap(app, theme: theme, step: &step, "citation-launch-failed")
            return
        }
        let line = app.descendants(matching: .any).matching(identifier: "citation-meta-m2").firstMatch
        poll(timeout: 10) { line.exists && line.label.contains("checked against source") }
        tourSnap(app, theme: theme, step: &step, "citation-answer")

        chip.tap()
        let note = app.descendants(matching: .any).matching(identifier: "source-cited-note").firstMatch
        _ = app.citedPageIsShowing()
        poll(timeout: 15) { note.exists && note.label.contains("highlighted") }
        tourSnap(app, theme: theme, step: &step, "citation-source-highlight")
    }
}
