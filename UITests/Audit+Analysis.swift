import XCTest

/// The analysis tools under Xcode's accessibility audit: the intake, each tool's result, and the
/// History sheet.
extension AccessibilityAuditTests {

    func testTheAnalysisToolsPassTheAudit() { auditAnalysis(light: false) }
    func testTheAnalysisToolsPassTheAuditInLight() { auditAnalysis(light: true) }

    private func auditAnalysis(light: Bool) {
        let theme = light ? "light-" : ""
        let tools: [(card: String, title: String, result: String, name: String)] = [
            ("devilsAdvocate", "Devil's Advocate", "da-report", "devils-advocate"),
            ("docIndex", "Doc Index", "di-table", "doc-index"),
            ("listOfDates", "List of Dates", "ld-chart", "list-of-dates"),
        ]
        for (index, tool) in tools.enumerated() {
            let app = light ? launch("-UITestLight") : launch()
            guard signIn(app) else { return }
            app.openCaseTool(tool.card)
            let bar = app.navigationBars[tool.title]
            guard reached(bar, "the \(tool.title) screen") else { return }
            if index == 0 {
                audit(theme + "analysis-intake", in: app, sheet: bar)
            }
            guard pickBakshi(app) else { return }
            let run = app.buttons["analysis-run"].firstMatch
            app.reveal(run)
            guard reached(run, "the run button") else { return }
            run.tap()
            let result = app.descendants(matching: .any)[tool.result].firstMatch
            guard reached(result, "the \(tool.title) result", timeout: 15) else { return }
            audit(theme + "analysis-\(tool.name)", in: app, sheet: bar)

            if index == 0 {
                let history = app.buttons["analysis-history"].firstMatch
                guard reached(history, "the History button") else { return }
                history.tap()
                let sheet = app.descendants(matching: .any)["analysis-history-sheet"].firstMatch
                guard reached(sheet, "the History sheet") else { return }
                audit(theme + "analysis-history", in: app)
            }
            app.terminate()
        }
    }

    private func pickBakshi(_ app: XCUIApplication) -> Bool {
        let choose = app.buttons["analysis-choose-files"].firstMatch
        guard reached(choose, "Choose from My Files") else { return false }
        choose.tap()
        let picker = app.navigationBars["Documents"]
        guard reached(picker, "the My Files picker") else { return false }
        let folder = app.buttons["Choose every document in Bakshi"].firstMatch
        app.reveal(folder)
        guard reached(folder, "the Bakshi folder") else { return false }
        folder.tap()
        let attach = picker.buttons["Attach"]
        guard reached(attach, "Attach") else { return false }
        attach.tap()
        return app.waitGone(picker)
    }
}
