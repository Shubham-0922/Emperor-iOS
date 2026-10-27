import XCTest

extension AccessibilityAuditTests {

    /// Account → Connected services, Google Drive connected and OneDrive not set up: a
    /// Disconnect and a "Not available yet" pill on screen together.
    func testTheConnectedServicesPassTheAudit() {
        let app = launch("-UITestCloudConnected")
        guard signIn(app) else { return }
        guard app.openConnectedServices() else {
            XCTFail("Connected services did not open")
            return
        }
        let disconnect = app.buttons["cloud-disconnect-google"]
        app.waitAndReveal(disconnect)
        guard reached(disconnect, "the connected drive's row") else { return }
        audit("cloud-account", in: app, sheet: app.navigationBars["Account & Profile"])
    }

    /// The import sheet with one file chosen.
    func testTheCloudImportSheetPassesTheAudit() {
        let app = launch("-UITestCloudConnected")
        guard signIn(app) else { return }
        guard app.openBakshiForCloud(), app.openCloudImport() else {
            XCTFail("the import sheet did not open")
            return
        }
        app.cloudElement("cloud-file-cf1").tap()
        guard reached(app.buttons["cloud-import-run"], "the import button") else { return }
        audit("cloud-import", in: app)
    }
}
