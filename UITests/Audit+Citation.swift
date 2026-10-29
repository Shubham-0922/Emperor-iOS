import XCTest

extension AccessibilityAuditTests {

    /// An answer citing one of the reader's documents: its reference with the Open chip and the
    /// line saying the citation was checked.
    func testTheCitedAnswerPassesTheAudit() {
        let app = launch("-UITestCitedSource")
        guard signIn(app) else { return }
        guard app.openCitedConversation() else {
            XCTFail("could not reach the conversation, so it was not audited")
            return
        }
        guard let chip = app.citedOpenChip() else {
            XCTFail("could not reach the reference's Open chip, so it was not audited")
            return
        }
        let line = app.descendants(matching: .any).matching(identifier: "citation-meta-m2").firstMatch
        poll(timeout: 10) { line.exists && line.label.contains("checked against source") }
        XCTAssertTrue(chip.isHittable)
        audit("cited-answer", in: app)
    }

    /// The cited document opened at the quoted words, marked, with the note under the page.
    func testTheCitedSourcePassesTheAudit() {
        let app = launch("-UITestCitedSource")
        guard signIn(app) else { return }
        guard app.openCitedConversation(), let chip = app.citedOpenChip() else {
            XCTFail("could not reach the reference's Open chip, so it was not audited")
            return
        }
        chip.tap()
        guard reached(app.staticTexts["Page 2 of 3"].firstMatch, "the cited page") else { return }
        let note = app.descendants(matching: .any).matching(identifier: "source-cited-note").firstMatch
        poll(timeout: 15) { note.exists && note.label.contains("highlighted") }
        audit("cited-source", in: app)
    }
}
