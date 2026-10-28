import XCTest

/// Filing Assembly under Xcode's accessibility audit: the draft list, a draft's annexures, then
/// an assembled bundle.
extension AccessibilityAuditTests {

    func testFilingAssemblyPassesTheAudit() { auditFiling(light: false) }
    func testFilingAssemblyPassesTheAuditInLight() { auditFiling(light: true) }

    func testFilingFromAChatPassesTheAudit() { auditChatFiling(light: false) }
    func testFilingFromAChatPassesTheAuditInLight() { auditChatFiling(light: true) }

    /// The assembler opened on a conversation's draft.
    private func auditChatFiling(light: Bool) {
        let app = light ? launch("-UITestFilingChat", "-UITestLight") : launch("-UITestFilingChat")
        guard signIn(app) else { return }
        let theme = light ? "light-" : ""
        guard app.openFilingChatDraft() else {
            XCTFail("could not reach the conversation's draft, so it was not audited")
            return
        }
        guard app.openChatFiling() else {
            XCTFail("Assemble filing did not open, so it was not audited")
            return
        }
        let bar = app.navigationBars["Assemble court-ready filing"]
        guard reached(app.filingElement("filing-annexure-101"), "the conversation's annexures") else { return }
        audit(theme + "filing-chat", in: app, sheet: bar)
    }

    private func auditFiling(light: Bool) {
        let app = light ? launch("-UITestLight") : launch()
        guard signIn(app) else { return }
        app.openCaseTool("filingAssembly")
        let bar = app.navigationBars["Filing Assembly"]
        guard reached(bar, "Filing Assembly") else { return }
        let theme = light ? "light-" : ""

        let draft = app.buttons["filing-draft-canvas_1"].firstMatch
        guard reached(draft, "the draft list") else { return }
        audit(theme + "filing-drafts", in: app, sheet: bar)

        app.reveal(draft)
        draft.tap()
        guard reached(app.filingElement("filing-annexure-1"), "the draft's annexures") else { return }
        audit(theme + "filing-annexures", in: app, sheet: bar)

        app.fillFilingField("filing-forum", "NCLT")
        guard app.assembleFiling() else {
            XCTFail("Assemble did not become available, so the result was not audited")
            return
        }
        guard reached(app.filingElement("filing-result-ok"), "the assembled bundle", timeout: 20)
        else { return }
        audit(theme + "filing-result", in: app, sheet: bar)
    }
}
