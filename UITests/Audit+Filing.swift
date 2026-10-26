import XCTest

/// Filing Assembly under Xcode's accessibility audit: the draft list, a draft's annexures, then
/// an assembled bundle.
extension AccessibilityAuditTests {

    func testFilingAssemblyPassesTheAudit() { auditFiling(light: false) }
    func testFilingAssemblyPassesTheAuditInLight() { auditFiling(light: true) }

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
