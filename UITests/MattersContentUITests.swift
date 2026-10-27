import XCTest

/// A matter's content against the stub server (`MattersStubs`): its conversations, a new one
/// starting with the matter's readable files, its folders, attaching from My Files, the
/// chronology read out of its documents, and a docket case opened as its matter. Polled
/// throughout, never slept on.
final class MattersContentUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTheAskSectionListsTheMattersConversations() {
        let app = XCUIApplication.launchedSignedIn()
        app.openMatter("prj-writ")
        XCTAssertTrue(app.matterElement("matter-header").waitForExistence(timeout: 10))
        app.openSection("ask")

        let row = app.matterElement("matter-chat-chat-writ")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the matter's conversation is not listed")
        XCTAssertTrue(app.labelled("Draft the rejoinder").exists)
        XCTAssertTrue(app.matterElement("matter-chat-new").exists, "there is no way to start one")
        XCTAssertTrue(app.labelled("They are not listed in History").exists)
    }

    func testANewConversationStartsWithTheMattersFilesStaged() {
        let app = XCUIApplication.launchedSignedIn(["-UITestFreshChats"])
        app.openMatter("prj-writ")
        XCTAssertTrue(app.matterElement("matter-header").waitForExistence(timeout: 10))
        app.openSection("ask")

        let new = app.matterElement("matter-chat-new")
        XCTAssertTrue(new.waitForExistence(timeout: 10))
        app.reveal(new)
        new.tap()
        XCTAssertTrue(app.matterElement("matter-chat-intro").waitForExistence(timeout: 10), "the intro is not shown")
        XCTAssertTrue(app.labelled("Summarise where this matter stands.").exists)
        XCTAssertTrue(app.labelled("Writ Petition.pdf").waitForExistence(timeout: 10), "a ready file was not staged")
        XCTAssertTrue(app.labelled("Court Fee Receipt.pdf").exists, "a ready file was not staged")
        XCTAssertFalse(app.labelled("Counter Affidavit.pdf").exists, "a file still being read was staged")
    }

    func testFilesShowStandardFoldersFirst() {
        let app = XCUIApplication.launchedSignedIn()
        app.openMatter("prj-writ")
        XCTAssertTrue(app.matterElement("matter-header").waitForExistence(timeout: 10))
        app.openSection("files")

        let pleadings = app.matterElement("matter-folder-Pleadings")
        XCTAssertTrue(pleadings.waitForExistence(timeout: 10), "the folders are not shown")
        let order = ["Pleadings", "Orders", "Evidence", "Correspondence", "Receipts"]
        let chips = order.map { app.matterElement("matter-folder-\($0)") }
        XCTAssertTrue(chips.allSatisfy { $0.exists }, "a standard folder is missing")
        for (left, right) in zip(chips, chips.dropFirst()) {
            XCTAssertLessThan(left.frame.minX, right.frame.minX, "the standard folders are out of order")
        }
        XCTAssertTrue(app.matterElement("matter-file-Writ_Petition.pdf").waitForExistence(timeout: 10))
        XCTAssertTrue(app.labelled("Being read").exists, "a file still being read does not say so")
        XCTAssertTrue(app.labelled("Documents come into a matter from My Files").exists)
    }

    func testAttachingFromMyFilesReportsEachFile() {
        let app = XCUIApplication.launchedSignedIn()
        app.openMatter("prj-writ")
        XCTAssertTrue(app.matterElement("matter-header").waitForExistence(timeout: 10))
        app.openSection("files")

        let confirm = app.openSheet(app.matterElement("matter-attach"), showing: "attach-confirm")
        XCTAssertTrue(confirm.exists, "Attach from My Files did not open")
        for name in ["Plaint.pdf", "Engagement_Letter.pdf"] {
            let row = app.matterElement("attach-file-\(name)")
            XCTAssertTrue(row.waitForExistence(timeout: 10), "\(name) is not offered")
            app.reveal(row)
            row.tap()
        }
        XCTAssertTrue(poll { confirm.isEnabled }, "nothing is selected")
        confirm.tap()

        let skipped = app.matterElement("attach-outcome-Engagement_Letter.pdf")
        XCTAssertTrue(skipped.waitForExistence(timeout: 10), "the skipped file is not reported")
        XCTAssertTrue(app.labelled("Still being read in My Files").exists, "the reason is not given")
        XCTAssertTrue(app.matterElement("attach-outcome-Plaint.pdf").exists, "the attached file is not reported")
    }

    func testBuildFromDocumentsProposesAndSaves() {
        let app = XCUIApplication.launchedSignedIn()
        app.openMatter("prj-writ")
        XCTAssertTrue(app.matterElement("matter-header").waitForExistence(timeout: 10))
        app.openSection("chronology")

        let read = app.openSheet(app.matterElement("chronology-build"), showing: "chronology-build-read")
        XCTAssertTrue(read.exists, "Build from documents did not open")
        read.tap()
        XCTAssertTrue(app.matterElement("chronology-build-review").waitForExistence(timeout: 15), "nothing was proposed")
        XCTAssertTrue(app.labelled("3 found · 2 ticked").exists, "the duplicate was ticked")
        XCTAssertTrue(app.labelled("Already on the record").exists)

        let save = app.matterElement("chronology-build-save")
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.waitGone(save, timeout: 15), "the sheet stayed up")
        XCTAssertTrue(app.labelled("Tender cancelled by the Department").waitForExistence(timeout: 10),
                      "the proposal is not on the record")
    }

    func testACaseOpensAsItsMatter() {
        let app = XCUIApplication.launchedSignedIn()
        app.openAllMatters()
        let row = app.matterElement("case-row-case-sc")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the docket case is not listed")
        app.reveal(row)
        row.tap()

        let open = app.matterElement("case-open-as-matter")
        XCTAssertTrue(open.waitForExistence(timeout: 10), "the case offers no matter")
        XCTAssertTrue(poll { open.isEnabled && open.isHittable }, "Open as matter cannot be tapped")
        open.tap()
        XCTAssertTrue(app.matterElement("matter-header").waitForExistence(timeout: 15), "the matter did not open")
        XCTAssertTrue(app.labelled("Matter from the court").exists, "it is not the new matter")
    }
}
