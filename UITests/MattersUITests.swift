import XCTest

/// Matters → All matters and a matter's workspace, against the stub server (`MattersStubs`):
/// the matters above the tracked cases, the status filter, the workspace's banner and sections,
/// and a matter that is not there. Polled throughout, never slept on.
final class MattersUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testAllMattersListsMattersAboveTrackedCases() {
        let app = XCUIApplication.launchedSignedIn()
        app.openAllMatters()

        let matter = app.matterRow("prj-writ")
        XCTAssertTrue(matter.waitForExistence(timeout: 10), "the matter is not listed")
        let docket = app.descendants(matching: .any).matching(identifier: "case-row-case1").firstMatch
        XCTAssertTrue(docket.waitForExistence(timeout: 10), "the tracked cases are gone")
        XCTAssertLessThan(matter.frame.minY, docket.frame.minY, "the matters are not above the tracked cases")
        XCTAssertTrue(app.labelled("Tracked cases").exists, "the tracked cases are not headed")
        XCTAssertFalse(app.matterRow("prj-old").exists, "an archived matter is shown under Active")
    }

    func testMatterStatusFilterShowsArchived() {
        let app = XCUIApplication.launchedSignedIn()
        app.openAllMatters()
        XCTAssertTrue(app.matterRow("prj-writ").waitForExistence(timeout: 10))

        let status = app.buttons["matters-status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5), "there is no status menu")
        status.tap()
        let archived = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Archived")).firstMatch
        XCTAssertTrue(archived.waitForExistence(timeout: 5), "the status menu has no Archived")
        archived.tap()

        XCTAssertTrue(app.matterRow("prj-old").waitForExistence(timeout: 5), "the archived matter did not appear")
        XCTAssertTrue(poll { !app.matterRow("prj-writ").exists }, "an active matter is shown under Archived")
    }

    func testOpeningAMatterShowsItsBannerAndSections() {
        let app = XCUIApplication.launchedSignedIn()
        app.openMatter("prj-writ")

        XCTAssertTrue(app.matterElement("matter-header").waitForExistence(timeout: 10), "the banner is missing")
        XCTAssertTrue(app.matterElement("matter-next-hearing").exists, "the next hearing is not on the banner")
        for section in ["overview", "chronology", "court", "tasks", "fees", "people"] {
            XCTAssertTrue(app.matterElement("matter-section-\(section)").exists, "no \(section) section")
        }
        XCTAssertFalse(app.matterElement("matter-section-files").exists, "Files is offered before it works")
        XCTAssertTrue(app.matterElement("matter-standing").waitForExistence(timeout: 5), "the overview is empty")
    }

    func testEachSectionRenders() {
        let app = XCUIApplication.launchedSignedIn()
        app.openMatter("prj-writ")
        XCTAssertTrue(app.matterElement("matter-header").waitForExistence(timeout: 10))

        let rows: [(String, String)] = [
            ("chronology", "matter-entry-u:upd-1"),
            ("court", "matter-court-row-ch-hearing"),
            ("tasks", "matter-task-tsk-limitation"),
            ("fees", "matter-fee-led-payment"),
            ("people", "matter-person-ppl-client"),
            ("overview", "matter-standing"),
        ]
        for (section, row) in rows {
            app.openSection(section)
            XCTAssertTrue(app.matterElement(row).waitForExistence(timeout: 5), "the \(section) section shows nothing")
        }
    }

    func testAMissingMatterSaysSo() {
        let app = XCUIApplication.launchedSignedIn()
        app.openMatter("prj-gone")
        XCTAssertTrue(app.labelled("Matter not found").waitForExistence(timeout: 10),
                      "a matter the server does not have did not say so")
    }
}

extension XCUIApplication {

    /// Matters → All matters.
    func openAllMatters() {
        let matters = tab("Matters")
        guard matters.waitForExistence(timeout: 10) else { return }
        matters.tap()
        _ = navigationBars["Matters"].waitForExistence(timeout: 10)
        let all = buttons["All matters"].firstMatch
        guard all.waitForExistence(timeout: 10) else { return }
        all.tap()
    }

    /// A matter's row on All matters.
    func matterRow(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: "matter-\(id)").firstMatch
    }

    /// Anything, by its identifier.
    func matterElement(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Anything whose words include `text` — matched on the label, as a combined row reads.
    func labelled(_ text: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// All matters, then the matter's workspace.
    func openMatter(_ id: String) {
        openAllMatters()
        let row = matterRow(id)
        guard row.waitForExistence(timeout: 10) else { return }
        reveal(row)
        row.tap()
    }

    /// A workspace section, by its key; the bar is dragged sideways until the chip can be tapped.
    func openSection(_ key: String) {
        let chip = matterElement("matter-section-\(key)")
        guard chip.waitForExistence(timeout: 5) else { return }
        var drags = 0
        let keys = ["overview", "chronology", "court", "tasks", "fees", "people"]
        while !chip.isHittable, drags < 4 {
            // Dragged from a chip that is on screen, towards the one wanted.
            guard let visible = keys.map({ matterElement("matter-section-\($0)") })
                .first(where: { $0.exists && $0.isHittable }) else { break }
            let towardsRight = chip.frame.minX > visible.frame.minX
            visible.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05,
                       thenDragTo: visible.coordinate(
                        withNormalizedOffset: CGVector(dx: towardsRight ? -1.5 : 2.5, dy: 0.5)))
            drags += 1
        }
        chip.tap()
    }
}
