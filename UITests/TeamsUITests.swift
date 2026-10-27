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
        guard waitAndReveal(row) else { return false }
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

        // The result is said twice: in the form's last row (below the fold on a phone, behind
        // the keyboard, and not built until scrolled to) and in a toast over the screen. Either
        // will do.
        XCTAssertTrue(saysSo(app, "Team created."), "creating the team did not say it was created")
        let created = element(app, "team-row-team_new_1")
        XCTAssertTrue(app.waitAndReveal(created), "the new team is not listed")
        let picker = element(app, "team-invite-target")
        XCTAssertTrue(app.waitAndReveal(picker), "there is no invite target picker")
        XCTAssertTrue(
            poll { self.reads(picker, "Litigation Team") },
            "the new team is not the invite target: label \(picker.label), value \(String(describing: picker.value))")
    }

    /// Whether `text` is on screen: the message row (scrolled to while it is not built) or the
    /// toast that repeats it. Polled.
    private func saysSo(_ app: XCUIApplication, _ text: String) -> Bool {
        let row = element(app, "team-message")
        let toast = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        var revealed = false
        return poll(timeout: 15) {
            if toast.exists { return true }
            if row.exists, row.label.contains(text) { return true }
            if !revealed {
                revealed = true
                app.reveal(row)
            }
            return row.exists && row.label.contains(text)
        }
    }

    /// Whether a menu picker shows `text` as its choice. iOS versions differ in where it goes:
    /// the value, the label ("Team, Litigation Team"), or the label of a button inside.
    private func reads(_ picker: XCUIElement, _ text: String) -> Bool {
        guard picker.exists else { return false }
        if picker.label.contains(text) { return true }
        if let value = picker.value as? String, value.contains(text) { return true }
        return picker.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.exists
    }

    func testInviteUnknownEmailShowsServerSentence() {
        let app = open()
        XCTAssertTrue(element(app, "team-row-team_1").waitForExistence(timeout: 10))
        typeInto(app.textFields["team-invite-email"], "nobody@example.com", app: app)
        let invite = app.buttons["team-invite"]
        app.reveal(invite)
        invite.tap()
        XCTAssertTrue(saysSo(app, "No user with that email"), "the server's sentence was not shown")
    }

    func testInviteAddsMemberAndUpdatesCount() {
        let app = open()
        let row = element(app, "team-row-team_1")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("1 member"), "the count reads: \(row.label)")
        typeInto(app.textFields["team-invite-email"], "colleague@example.com", app: app)
        let invite = app.buttons["team-invite"]
        app.reveal(invite)
        invite.tap()
        XCTAssertTrue(saysSo(app, "Member added."), "adding the member did not say so")
        let updated = element(app, "team-row-team_1")
        XCTAssertTrue(app.waitAndReveal(updated), "the team is no longer listed")
        XCTAssertTrue(poll { updated.label.contains("2 members") }, "the count reads: \(updated.label)")
    }
}
