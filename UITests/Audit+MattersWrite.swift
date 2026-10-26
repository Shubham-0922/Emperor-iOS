import XCTest

/// The matter forms under Xcode's accessibility audit: New matter, a payment being entered, and
/// Delete matter.
extension AccessibilityAuditTests {

    func testTheMatterFormsPassTheAudit() { auditMatterForms(light: false) }
    func testTheMatterFormsPassTheAuditInLight() { auditMatterForms(light: true) }

    private func auditMatterForms(light: Bool) {
        let app = light ? launch("-UITestLight") : launch()
        guard signIn(app) else { return }
        let theme = light ? "light-" : ""

        app.openAllMatters()
        guard reached(app.matterRow("prj-writ"), "All matters") else { return }
        let create = app.openSheet(app.matterElement("matters-new"), showing: "new-matter-create")
        guard reached(create, "New matter") else { return }
        audit(theme + "new-matter", in: app)
        app.buttons["Cancel"].firstMatch.tap()
        app.waitGone(create)

        let row = app.matterRow("prj-writ")
        app.reveal(row)
        row.tap()
        guard reached(app.matterElement("matter-header"), "the matter's workspace") else { return }
        app.openSection("fees")
        let ledger = app.openSheet(app.matterElement("fees-add-payment"), showing: "ledger-save")
        guard reached(ledger, "Add payment") else { return }
        audit(theme + "ledger-entry", in: app)
        app.buttons["Cancel"].firstMatch.tap()
        app.waitGone(ledger)

        let confirm = app.openMatterMenuItem("matter-delete", label: "Delete…", showing: "delete-matter-confirm")
        guard reached(confirm, "Delete matter") else { return }
        audit(theme + "delete-matter", in: app)
    }
}
