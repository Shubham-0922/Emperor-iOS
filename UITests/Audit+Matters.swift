import XCTest

/// A matter's workspace under Xcode's accessibility audit: the overview, then the court record
/// and the tasks, of the stub's linked matter. All matters itself is audited with the Matters tab.
extension AccessibilityAuditTests {

    func testTheMatterWorkspacePassesTheAudit() { auditMatterWorkspace(light: false) }
    func testTheMatterWorkspacePassesTheAuditInLight() { auditMatterWorkspace(light: true) }

    private func auditMatterWorkspace(light: Bool) {
        let app = light ? launch("-UITestLight") : launch()
        guard signIn(app) else { return }
        app.openMatter("prj-writ")
        guard reached(app.matterElement("matter-header"), "the matter's workspace") else { return }
        let theme = light ? "light-" : ""
        audit(theme + "matter-overview", in: app)

        for (section, row) in [("court", "matter-court-row-ch-hearing"), ("tasks", "matter-task-tsk-limitation")] {
            app.openSection(section)
            guard reached(app.matterElement(row), "the \(section) section") else { return }
            audit(theme + "matter-\(section)", in: app)
        }
    }
}
