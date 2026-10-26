import XCTest

extension AccessibilityAuditTests {

    /// The Team sheet with the invite picker on screen: a created team makes a second one that
    /// the account may invite to.
    func testTheTeamsScreenPassesTheAudit() {
        let app = launch()
        guard signIn(app) else { return }
        guard app.openTeams() else {
            XCTFail("the Team sheet did not open")
            return
        }
        let first = app.descendants(matching: .any).matching(identifier: "team-row-team_1").firstMatch
        guard reached(first, "the team list") else { return }

        let field = app.textFields["team-new-name"]
        app.reveal(field)
        field.focusForTyping()
        field.typeText("Litigation Team")
        let create = app.buttons["team-create"]
        app.reveal(create)
        create.tap()
        let picker = app.descendants(matching: .any).matching(identifier: "team-invite-target").firstMatch
        guard reached(picker, "the invite picker") else { return }

        audit("teams", in: app, sheet: app.navigationBars["Team"])
    }
}
