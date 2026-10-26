import XCTest

/// The Limitation Radar under Xcode's accessibility audit: the empty form, then the amber answer.
extension AccessibilityAuditTests {

    func testTheLimitationRadarPassesTheAudit() { auditRadar(light: false) }
    func testTheLimitationRadarPassesTheAuditInLight() { auditRadar(light: true) }

    private func auditRadar(light: Bool) {
        let app = light ? launch("-UITestLight") : launch()
        guard signIn(app) else { return }
        app.openCaseTool("limitationRadar")
        let bar = app.navigationBars["Limitation Radar"]
        guard reached(bar, "the Limitation Radar") else { return }
        let theme = light ? "light-" : ""
        audit(theme + "radar-empty", in: app, sheet: bar)

        for id in ["radar-cause", "radar-filing"] {
            let add = app.buttons[id].firstMatch
            app.reveal(add)
            guard reached(add, "the \(id) field") else { return }
            add.tap()
            _ = app.descendants(matching: .any)["\(id)-clear"].firstMatch
                .waitForExistence(timeout: 5)
        }
        let run = app.buttons["radar-run"].firstMatch
        app.reveal(run)
        guard reached(run, "the run button") else { return }
        run.tap()
        let banner = app.descendants(matching: .any)["radar-banner"].firstMatch
        guard reached(banner, "the audit's banner") else { return }
        audit(theme + "radar-result", in: app, sheet: bar)
    }
}
