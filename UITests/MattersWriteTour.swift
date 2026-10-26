import XCTest

/// The matter forms photographed in both themes: New matter, Edit details, a payment being
/// entered with its amount in words, and a fee receipt. Tolerates a missing control, as
/// `ScreenshotTour` does.
final class MattersWriteTour: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testTheMatterFormsDark() { tour(light: false) }
    func testTheMatterFormsLight() { tour(light: true) }

    private func tour(light: Bool) {
        let app = XCUIApplication.launchedSignedIn([], light: light)
        let theme = light ? "light" : "dark"
        var step = 0

        app.openAllMatters()
        guard app.matterRow("prj-writ").waitForExistence(timeout: 10) else { return }
        let create = app.openSheet(app.matterElement("matters-new"), showing: "new-matter-create")
        if create.exists {
            tourSnap(app, theme: theme, step: &step, "new-matter")
            app.buttons["Cancel"].firstMatch.tap()
            app.waitGone(create)
        }

        let row = app.matterRow("prj-writ")
        app.reveal(row)
        row.tap()
        guard app.matterElement("matter-header").waitForExistence(timeout: 10) else { return }
        let save = app.openMatterMenuItem("matter-edit", label: "Edit details", showing: "matter-details-save")
        if save.exists {
            tourSnap(app, theme: theme, step: &step, "matter-details")
            app.buttons["Cancel"].firstMatch.tap()
            app.waitGone(save)
        }

        app.openSection("fees")
        let ledger = app.openSheet(app.matterElement("fees-add-payment"), showing: "ledger-save")
        if ledger.exists {
            app.type("125000.50", into: app.matterElement("ledger-amount"))
            tourSnap(app, theme: theme, step: &step, "ledger-entry")
            app.buttons["Cancel"].firstMatch.tap()
            app.waitGone(ledger)
        }

        let receipt = app.matterElement("ledger-receipt-led-payment")
        if receipt.waitForExistence(timeout: 5) {
            app.reveal(receipt)
            receipt.tap()
            if app.matterElement("receipt-preview").waitForExistence(timeout: 15) {
                tourSnap(app, theme: theme, step: &step, "receipt-preview")
            }
        }
    }
}
