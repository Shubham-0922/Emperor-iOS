import XCTest

/// Fetch Orders under Xcode's accessibility audit: the search, then a case read from its court.
extension AccessibilityAuditTests {

    func testFetchOrdersPassesTheAudit() { auditFetchOrders(light: false) }
    func testFetchOrdersPassesTheAuditInLight() { auditFetchOrders(light: true) }

    private func auditFetchOrders(light: Bool) {
        let app = light ? launch("-UITestLight") : launch()
        guard signIn(app) else { return }
        app.openCaseTool("fetchOrders")
        let bar = app.navigationBars["Fetch Orders"]
        guard reached(bar, "Fetch Orders") else { return }
        let theme = light ? "light-" : ""
        audit(theme + "fetch-orders-search", in: app, sheet: bar)

        app.fetchTheSupremeCourtCase(open: false)
        let title = app.descendants(matching: .any)["fetch-dossier-title"].firstMatch
        guard reached(title, "the case read from the court", timeout: 20) else { return }
        audit(theme + "fetch-orders-dossier", in: app, sheet: bar)
    }
}
