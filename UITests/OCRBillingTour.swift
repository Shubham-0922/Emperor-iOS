import XCTest

/// Photographs the OCR history with its page breakdown and notes, and the plan sheet closed and
/// with its inclusions open, in the dark theme and the light one.
final class OCRBillingTour: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testTheDarkTour() { tour(light: false) }
    func testTheLightTour() { tour(light: true) }

    private func tour(light: Bool) {
        let theme = light ? "light" : "dark"
        var step = 0

        let ocr = XCUIApplication.launchedSignedIn(["-UITestOCRNotes"], light: light)
        let more = ocr.tab("More")
        if more.waitForExistence(timeout: 10) {
            more.tap()
            let row = ocr.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "OCR & Translate")).firstMatch
            if row.waitForExistence(timeout: 10) {
                ocr.reveal(row)
                row.tap()
                let modes = ocr.segmentedControls.firstMatch
                if modes.waitForExistence(timeout: 10) { modes.buttons["Translate"].tap() }
                let notes = ocr.descendants(matching: .any)["ocr-row-notes-1790000000000"].firstMatch
                var swipes = 0
                while !notes.exists, swipes < 4 {
                    ocr.swipeUp()
                    swipes += 1
                }
                _ = notes.waitForExistence(timeout: 5)
                tourSnap(ocr, theme: theme, step: &step, "ocr-history-notes")
            }
        }
        ocr.terminate()

        let plan = XCUIApplication.launchedSignedIn(["-UITestPlanDetail"], light: light)
        let pill = plan.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Plan,")).firstMatch
        guard pill.waitForExistence(timeout: 10) else { return }
        pill.tap()
        guard plan.navigationBars["Plan"].waitForExistence(timeout: 10) else { return }
        _ = plan.descendants(matching: .any)["plan-standing"].firstMatch.waitForExistence(timeout: 10)
        tourSnap(plan, theme: theme, step: &step, "plan-sheet")
        let includes = plan.buttons["plan-includes"].firstMatch
        if includes.waitForExistence(timeout: 5) {
            plan.reveal(includes)
            includes.tap()
            _ = plan.staticTexts["Email support"].firstMatch.waitForExistence(timeout: 5)
            tourSnap(plan, theme: theme, step: &step, "plan-includes-open")
        }
    }
}
