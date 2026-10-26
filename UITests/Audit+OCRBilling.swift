import XCTest

/// The plan sheet with "What your plan includes" open, and the OCR history with its notes.
extension AccessibilityAuditTests {

    func testThePlanSheetWithItsInclusionsPassesTheAudit() {
        let app = launch("-UITestPlanDetail")
        guard signIn(app) else { return }
        let pill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Plan,")).firstMatch
        guard reached(pill, "Home's plan pill") else { return }
        pill.tap()
        let bar = app.navigationBars["Plan"]
        guard reached(bar, "the plan sheet") else { return }
        let includes = app.buttons["plan-includes"].firstMatch
        guard reached(includes, "the inclusions row") else { return }
        app.reveal(includes)
        includes.tap()
        _ = app.staticTexts["Email support"].firstMatch.waitForExistence(timeout: 5)
        audit("plan-includes", in: app, sheet: bar)
    }

    func testTheOCRHistoryWithNotesPassesTheAudit() {
        let app = launch("-UITestOCRNotes")
        guard signIn(app) else { return }
        let more = app.tab("More")
        guard reached(more, "the More tab") else { return }
        more.tap()
        let row = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "OCR & Translate")).firstMatch
        guard reached(row, "the OCR & Translate row") else { return }
        app.reveal(row)
        row.tap()
        let modes = app.segmentedControls.firstMatch
        guard reached(modes, "the OCR | Translate switch") else { return }
        modes.buttons["Translate"].tap()
        let bar = app.navigationBars["Translate"]
        guard reached(bar, "the Translate screen") else { return }
        let notes = app.descendants(matching: .any)["ocr-row-notes-1790000000000"].firstMatch
        var swipes = 0
        while !notes.exists, swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        guard reached(notes, "the history row's notes") else { return }
        audit("ocr-history-notes", in: app, sheet: bar)
    }
}
