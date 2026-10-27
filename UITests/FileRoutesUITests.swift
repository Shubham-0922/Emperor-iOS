import XCTest

extension XCUIApplication {

    func fileRouteElement(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The toast after a save — matched by label, since the toast combines its icon and words
    /// into one element of no particular type.
    var draftSavedToast: XCUIElement {
        descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Saved to your drafts")).firstMatch
    }

    /// More → History → Your drafts, waiting for the list's bar. History's row is tapped again,
    /// up to three taps in all, while no sheet has come up.
    @discardableResult
    func openYourDrafts() -> Bool {
        let more = tab("More")
        guard more.waitForExistence(timeout: 10) else { return false }
        more.tap()
        let history = buttons["History"].firstMatch
        guard history.waitForExistence(timeout: 10) else { return false }
        reveal(history)
        let conversations = navigationBars["Conversations"]
        for _ in 0..<3 {
            guard history.exists, history.isHittable else { break }
            history.tap()
            if conversations.waitForExistence(timeout: 5) { break }
        }
        let drafts = buttons["Your drafts"].firstMatch
        guard drafts.waitForExistence(timeout: 10) else { return false }
        drafts.tap()
        return navigationBars["Your drafts"].waitForExistence(timeout: 10)
    }

    /// Your drafts → the stub's one draft, open in its reader with Edit on screen.
    @discardableResult
    func openStubDraft() -> Bool {
        guard openYourDrafts() else { return false }
        let row = buttons["draft-row-d1"].firstMatch
        guard row.waitForExistence(timeout: 10) else { return false }
        let edit = buttons["draft-edit"].firstMatch
        for _ in 0..<3 {
            guard row.exists, row.isHittable else { break }
            row.tap()
            if edit.waitForExistence(timeout: 5) { break }
        }
        // Until the reader has finished arriving: its bar slides up with it, and a tap aimed at
        // a control still moving lands where the control no longer is.
        return edit.waitForExistence(timeout: 10) && waitUntilSettled(edit)
    }

    /// Waits until `element` is hittable and has stopped moving — the same frame on two reads in
    /// a row — and answers whether it did. A bar arriving with a full-screen cover, or one
    /// riding the keyboard up, is hittable before it is where it will stay.
    @discardableResult
    func waitUntilSettled(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var last: CGRect?
        while Date() < deadline {
            if element.exists, element.isHittable {
                let frame = element.frame
                if let last, last == frame { return true }
                last = frame
            } else {
                last = nil
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    /// Edit, then type into the editable page: the web view is tapped until the keyboard is up,
    /// at most three times — a tap on a page still loading can be lost.
    @discardableResult
    func editStubDraft(typing text: String) -> Bool {
        let edit = buttons["draft-edit"].firstMatch
        guard edit.waitForExistence(timeout: 10) else { return false }
        edit.tap()
        guard buttons["draft-save"].waitForExistence(timeout: 10) else { return false }
        let page = webViews.firstMatch
        guard page.waitForExistence(timeout: 10) else { return false }
        let field = page.textViews.firstMatch
        let heading = page.staticTexts["Draft text"].firstMatch
        _ = field.waitForExistence(timeout: 5) || heading.waitForExistence(timeout: 10)
        for _ in 0..<3 {
            if field.exists, field.isHittable {
                field.tap()
            } else if heading.exists, heading.isHittable {
                heading.tap()
            } else {
                page.tap()
            }
            if keyboards.firstMatch.waitForExistence(timeout: 5) { break }
        }
        guard keyboards.firstMatch.exists else { return false }
        typeText(text)
        return true
    }

    /// The system share sheet, however this iOS names it.
    func shareSheetShows(timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if otherElements["ActivityListView"].exists
                || buttons["Copy"].exists || cells["Copy"].exists
                || buttons["Save to Files"].exists || cells["Save to Files"].exists {
                return true
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    /// More → Files, on the library's top level.
    @discardableResult
    func openMyFiles() -> Bool {
        let more = tab("More")
        guard more.waitForExistence(timeout: 10) else { return false }
        more.tap()
        let files = buttons["Files"].firstMatch
        guard files.waitForExistence(timeout: 10) else { return false }
        reveal(files)
        files.tap()
        return navigationBars["Files"].waitForExistence(timeout: 10)
    }

    /// Files → Arora_Holdings → Board Resolution.docx, in the viewer.
    @discardableResult
    func openBoardResolution() -> Bool {
        guard openMyFiles() else { return false }
        let folder = buttons["folder-Arora_Holdings"]
        guard folder.waitForExistence(timeout: 10) else { return false }
        reveal(folder)
        folder.tap()
        guard navigationBars["Arora Holdings"].waitForExistence(timeout: 10)
            || navigationBars["Arora_Holdings"].waitForExistence(timeout: 2) else { return false }
        let document = staticTexts["Board Resolution.docx"]
        guard document.waitForExistence(timeout: 10) else { return false }
        document.tap()
        return true
    }
}

/// The small file routes: editing a saved draft, a folder shared as a zip, a Word document shown
/// as its extracted text, the server's PDF, and the maintenance notice.
final class FileRoutesUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The toast is kept on screen (`-UITestLongToasts`): saving swaps the editing page for the
    /// reader's, and the simulator can still be settling when a toast of seconds has gone. What
    /// was saved is then read where it stays — the reader shows the edited words.
    func testEditDraftSaves() {
        let app = XCUIApplication.launchedSignedIn(["-UITestDraftEdit", "-UITestLongToasts"])
        XCTAssertTrue(app.openStubDraft(), "the draft did not open in its reader")
        XCTAssertTrue(app.editStubDraft(typing: " amended"), "the draft could not be typed into")

        // Save is tapped once its bar has stopped riding the keyboard up, and again — at most
        // three taps in all — while nothing has come of it: no reader back, no reason given.
        // A second save of the same text is no edit, so it cannot save twice.
        let save = app.buttons["draft-save"].firstMatch
        let reader = app.buttons["draft-edit"].firstMatch
        let failure = app.fileRouteElement("draft-save-error")
        let toast = app.draftSavedToast
        for _ in 0..<3 {
            guard app.waitUntilSettled(save) else { break }
            save.tap()
            if poll(timeout: 8, until: { toast.exists || reader.exists || failure.exists }) { break }
        }
        XCTAssertFalse(failure.exists, "the save was refused: \(failure.label)")
        XCTAssertTrue(poll(timeout: 15) { toast.exists }, "no word that the draft was saved")
        XCTAssertTrue(reader.waitForExistence(timeout: 10), "the reader did not come back")
        let edited = app.webViews.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "amended")).firstMatch
        XCTAssertTrue(edited.waitForExistence(timeout: 10), "the reader does not show the saved edit")
    }

    func testCancelEditKeepsOriginal() {
        let app = XCUIApplication.launchedSignedIn(["-UITestDraftEdit"])
        XCTAssertTrue(app.openStubDraft(), "the draft did not open in its reader")
        XCTAssertTrue(app.editStubDraft(typing: " struck out"), "the draft could not be typed into")
        app.buttons["draft-cancel-edit"].tap()

        XCTAssertTrue(app.buttons["draft-edit"].waitForExistence(timeout: 10), "Cancel did not end editing")
        XCTAssertFalse(app.buttons["draft-save"].exists)
        XCTAssertTrue(
            app.webViews.staticTexts["Draft text"].waitForExistence(timeout: 10),
            "the draft as saved is not what the reader shows")
        XCTAssertFalse(app.draftSavedToast.exists, "nothing was to be saved")
    }

    func testFolderZipShares() {
        let app = XCUIApplication.launchedSignedIn()
        XCTAssertTrue(app.openMyFiles(), "Files did not open")
        let folder = app.buttons["folder-Bakshi"]
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        let share = app.buttons["Share folder as .zip"]
        for _ in 0..<3 {
            folder.press(forDuration: 1.2)
            if share.waitForExistence(timeout: 5) { break }
        }
        XCTAssertTrue(share.exists, "the folder's menu has no zip")
        share.tap()
        XCTAssertTrue(app.shareSheetShows(), "the archive was not offered to share")
    }

    func testWordFallbackShowsExtractedText() {
        let app = XCUIApplication.launchedSignedIn(["-UITestOfficeFails"])
        XCTAssertTrue(app.openBoardResolution(), "the Word document did not open")
        let banner = app.fileRouteElement("file-text-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "the extracted text did not stand in")
        XCTAssertTrue(banner.label.contains("Rebuilt from extracted text"), banner.label)
        XCTAssertTrue(app.fileRouteElement("file-text-page-1").exists)
        XCTAssertTrue(app.fileRouteElement("file-text-page-2").exists)
    }

    /// The export menu's PDF is the server's: the share sheet comes up with no word of a copy
    /// laid out on the phone. Reached from a draft's reader, which carries the same menu as a
    /// chat's drafted document.
    func testPdfExportUsesServer() {
        let app = XCUIApplication.launchedSignedIn(["-UITestDraftEdit"])
        XCTAssertTrue(app.openStubDraft(), "the draft did not open in its reader")
        let menu = app.buttons["Download this document"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "the reader has no download menu")
        // By identifier or by its words. The menu is tapped once the reader has stopped moving,
        // and again, up to three taps in all, while it has not opened: a tap as the full-screen
        // reader is still arriving can be lost. A menu that did open leaves its button
        // unhittable, which ends the loop rather than closing it again.
        let pdf = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "export-pdf", "PDF")).firstMatch
        for _ in 0..<3 {
            guard app.waitUntilSettled(menu, timeout: 5) else { break }
            menu.tap()
            if pdf.waitForExistence(timeout: 5) { break }
        }
        XCTAssertTrue(
            app.buttons["draft-edit"].exists || pdf.exists, "the reader closed instead of opening its menu")
        XCTAssertTrue(pdf.exists, "the menu has no PDF")
        pdf.tap()
        XCTAssertTrue(app.shareSheetShows(), "the PDF was not offered to share")
        XCTAssertFalse(app.fileRouteElement("export-pdf-local").exists, "the server's PDF was not used")
    }

    func testMaintenanceBanner() {
        let app = XCUIApplication.launchedSignedIn(["-UITestMaintenance"])
        let banner = app.fileRouteElement("maintenance-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "no maintenance notice on Home")
        XCTAssertTrue(banner.label.contains("Back at 6"), banner.label)
    }
}
