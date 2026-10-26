import XCTest

extension XCUIApplication {

    /// Opens Team from More: the tab, the row scrolled to, tapped — again, up to three taps in
    /// all, while no sheet has come up. The sheet's "Done" in a bar is the sheet having opened.
    @discardableResult
    func openTeams() -> Bool {
        let more = tab("More")
        guard more.waitForExistence(timeout: 10) else { return false }
        more.tap()
        let row = buttons["workspace-row-teams"].firstMatch
        guard row.waitForExistence(timeout: 10) else { return false }
        reveal(row)
        let done = navigationBars.buttons["Done"].firstMatch
        for _ in 0..<3 {
            guard row.exists, row.isHittable else { break }
            row.tap()
            if done.waitForExistence(timeout: 5) { break }
        }
        return navigationBars["Team"].waitForExistence(timeout: 10)
    }
}

/// Team: the list, creating a team, adding a member.
final class TeamsUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func open() -> XCUIApplication {
        let app = XCUIApplication.launchedSignedIn()
        XCTAssertTrue(app.openTeams(), "the Team sheet should open from More")
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func typeInto(_ field: XCUIElement, _ text: String, app: XCUIApplication) {
        app.reveal(field)
        field.focusForTyping()
        field.typeText(text)
    }

    func testTeamRowOpensAndListsTeams() {
        let app = open()
        XCTAssertTrue(element(app, "team-row-team_1").waitForExistence(timeout: 10))
        let member = element(app, "team-row-team_2")
        XCTAssertTrue(member.waitForExistence(timeout: 10))
        XCTAssertTrue(member.label.contains("Member"), "the member-role team says so: \(member.label)")
    }

    func testCreateTeamThenInviteTargetsIt() {
        let app = open()
        XCTAssertTrue(element(app, "team-row-team_1").waitForExistence(timeout: 10))
        typeInto(app.textFields["team-new-name"], "Litigation Team", app: app)
        let create = app.buttons["team-create"]
        app.reveal(create)
        create.tap()

        let message = element(app, "team-message")
        XCTAssertTrue(poll { message.exists && message.label.contains("Team created.") })
        XCTAssertTrue(element(app, "team-row-team_new_1").waitForExistence(timeout: 10))
        let picker = element(app, "team-invite-target")
        app.reveal(picker)
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertTrue(
            poll { "\(picker.value ?? "")\(picker.label)".contains("Litigation Team") },
            "the new team is the invite target")
    }

    func testInviteUnknownEmailShowsServerSentence() {
        let app = open()
        XCTAssertTrue(element(app, "team-row-team_1").waitForExistence(timeout: 10))
        typeInto(app.textFields["team-invite-email"], "nobody@example.com", app: app)
        let invite = app.buttons["team-invite"]
        app.reveal(invite)
        invite.tap()
        let message = element(app, "team-message")
        XCTAssertTrue(poll { message.exists && message.label.contains("No user with that email") })
    }

    func testInviteAddsMemberAndUpdatesCount() {
        let app = open()
        let row = element(app, "team-row-team_1")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("1 member"), row.label)
        typeInto(app.textFields["team-invite-email"], "colleague@example.com", app: app)
        let invite = app.buttons["team-invite"]
        app.reveal(invite)
        invite.tap()
        XCTAssertTrue(poll { self.element(app, "team-message").label.contains("Member added.") })
        let updated = element(app, "team-row-team_1")
        app.reveal(updated)
        XCTAssertTrue(poll { updated.label.contains("2 members") }, updated.label)
    }
}
