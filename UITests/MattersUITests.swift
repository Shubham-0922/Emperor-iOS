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
            XCTAssertTrue(app.revealSection(section).exists, "no \(section) section")
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
        guard waitAndReveal(row) else { return }
        row.tap()
    }

    /// A workspace section's chip: by its identifier, or, should the identifier not reach the
    /// tree, by its name — the chip reads its name, then any count ("Tasks, 3, one or more
    /// overdue").
    func sectionChip(_ key: String) -> XCUIElement {
        let byID = buttons.matching(identifier: "matter-section-\(key)").firstMatch
        if byID.exists { return byID }
        let title = key.prefix(1).uppercased() + key.dropFirst()
        let predicate = NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, "\(title), ")
        return buttons.matching(predicate).firstMatch
    }

    /// A workspace section, by its key. The bar scrolls sideways and centres the chosen chip, so
    /// on a phone a chip far from it is off screen — and may not be in the tree at all until the
    /// bar is dragged towards it. Dragged from the chip nearest that side, a bounded number of
    /// times, until the wanted chip can be tapped.
    func openSection(_ key: String) {
        let chip = revealSection(key)
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "no \(key) chip on the section bar")
        XCTAssertTrue(chip.isHittable, "the \(key) chip could not be scrolled on screen")
        chip.tap()
    }

    /// A section's chip, the bar dragged sideways (bounded) until it can be tapped; not tapped.
    @discardableResult
    func revealSection(_ key: String) -> XCUIElement {
        // The bar's order, left to right.
        let keys = ["overview", "chronology", "court", "tasks", "fees", "people"]
        let target = keys.firstIndex(of: key) ?? 0
        _ = matterElement("matter-header").waitForExistence(timeout: 10)
        var drags = 0
        while drags < 8 {
            let chip = sectionChip(key)
            if chip.waitForExistence(timeout: 1), chip.isHittable { break }
            let onScreen = keys.indices.filter { index in
                let other = sectionChip(keys[index])
                return other.exists && other.isHittable
            }
            guard let first = onScreen.first, let last = onScreen.last else { break }
            // Wanted to the right of everything shown: drag the rightmost chip left, and the
            // other way round.
            let towardsRight = target > last
            let from = sectionChip(keys[towardsRight ? last : first])
            let end = CGVector(dx: towardsRight ? -1.5 : 2.5, dy: 0.5)
            from.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: from.coordinate(withNormalizedOffset: end))
            drags += 1
        }
        return sectionChip(key)
    }
}
