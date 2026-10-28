import XCTest

/// The OCR history with its page breakdown and notes.
extension AccessibilityAuditTests {

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
        let notes = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Page 4 could not be read")).firstMatch
        var swipes = 0
        while !notes.exists, swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        guard reached(notes, "the history row's notes") else { return }
        audit("ocr-history-notes", in: app, sheet: bar)
    }
}
