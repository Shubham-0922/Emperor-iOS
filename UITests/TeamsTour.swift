import XCTest

/// Photographs the Team screen, in the dark theme and the light one.
final class TeamsTour: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testTheDarkTeamsTour() { tour(light: false) }
    func testTheLightTeamsTour() { tour(light: true) }

    private func tour(light: Bool) {
        let app = XCUIApplication.launchedSignedIn(light: light)
        let theme = light ? "light" : "dark"
        var step = 0
        guard app.openTeams() else {
            tourSnap(app, theme: theme, step: &step, "teams-launch-failed")
            return
        }
        _ = app.descendants(matching: .any).matching(identifier: "team-row-team_1")
            .firstMatch.waitForExistence(timeout: 10)
        tourSnap(app, theme: theme, step: &step, "teams-list")

        let field = app.textFields["team-new-name"]
        guard field.waitForExistence(timeout: 5) else { return }
        app.reveal(field)
        field.focusForTyping()
        field.typeText("Litigation Team")
        let create = app.buttons["team-create"]
        app.reveal(create)
        create.tap()
        _ = app.descendants(matching: .any).matching(identifier: "team-row-team_new_1")
            .firstMatch.waitForExistence(timeout: 10)
        tourSnap(app, theme: theme, step: &step, "teams-after-create")
    }
}
