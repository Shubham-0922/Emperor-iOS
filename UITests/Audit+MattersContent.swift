import XCTest

/// A matter's content under Xcode's accessibility audit: its conversations, its files, Attach
/// from My Files, and the chronology proposed from its documents.
extension AccessibilityAuditTests {

    func testTheMatterContentPassesTheAudit() { auditMatterContent(light: false) }
    func testTheMatterContentPassesTheAuditInLight() { auditMatterContent(light: true) }

    private func auditMatterContent(light: Bool) {
        let app = light ? launch("-UITestLight") : launch()
        guard signIn(app) else { return }
        let theme = light ? "light-" : ""

        app.openMatter("prj-writ")
        guard reached(app.matterElement("matter-header"), "the matter's workspace") else { return }

        app.openSection("ask")
        guard reached(app.matterElement("matter-chat-chat-writ"), "Ask Emperor") else { return }
        audit(theme + "matter-ask", in: app)

        app.openSection("files")
        guard reached(app.matterElement("matter-file-Writ_Petition.pdf"), "Files") else { return }
        audit(theme + "matter-files", in: app)

        let confirm = app.openSheet(app.matterElement("matter-attach"), showing: "attach-confirm")
        guard reached(confirm, "Attach from My Files") else { return }
        _ = app.matterElement("attach-file-Plaint.pdf").waitForExistence(timeout: 10)
        audit(theme + "attach-sheet", in: app)
        app.buttons["Cancel"].firstMatch.tap()
        app.waitGone(confirm)

        app.openSection("chronology")
        let read = app.openSheet(app.matterElement("chronology-build"), showing: "chronology-build-read")
        guard reached(read, "Build from documents") else { return }
        read.tap()
        guard reached(app.matterElement("chronology-build-review"), "the proposed events", timeout: 15) else { return }
        audit(theme + "chronology-build", in: app)
    }
}
