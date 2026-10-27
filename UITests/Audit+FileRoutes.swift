import XCTest

extension AccessibilityAuditTests {

    /// A saved draft's reader in edit mode: the editable page, Cancel and Save.
    func testTheDraftEditorPassesTheAudit() {
        let app = launch("-UITestDraftEdit")
        guard signIn(app) else { return }
        guard app.openStubDraft() else {
            XCTFail("the draft did not open in its reader")
            return
        }
        app.buttons["draft-edit"].tap()
        guard reached(app.buttons["draft-save"], "the draft editor") else { return }
        audit("draft-editing", in: app, sheet: app.navigationBars["Plaint"])
    }

    /// A Word document the server could not convert, shown as its extracted text.
    func testTheExtractedTextPassesTheAudit() {
        let app = launch("-UITestOfficeFails")
        guard signIn(app) else { return }
        guard app.openBoardResolution() else {
            XCTFail("the Word document did not open")
            return
        }
        let banner = app.descendants(matching: .any).matching(identifier: "file-text-banner").firstMatch
        guard reached(banner, "the extracted text", timeout: 15) else { return }
        audit("extracted-text", in: app)
    }
}
