import XCTest

/// Writing a matter against the stub server (`MattersStubs.Store`, kept for the launch): New
/// matter, Edit details, Archive, Delete, a task ticked off, a payment and its receipt, a
/// chronology entry, and the court refresh's five-minute wait. Polled throughout, never slept on;
/// a sheet is known to be gone when its action has gone.
final class MattersWriteUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testANewMatterNotFiledYetOpensItsWorkspace() {
        let app = XCUIApplication.launchedSignedIn()
        app.openAllMatters()
        XCTAssertTrue(app.matterRow("prj-writ").waitForExistence(timeout: 10))

        let create = app.openSheet(app.matterElement("matters-new"), showing: "new-matter-create")
        XCTAssertTrue(create.exists, "New matter did not open")
        app.type("Kapoor v. Kapoor", into: app.matterElement("new-matter-name"))
        // Low in the form, under the keyboard the name left up: scrolled to inside the sheet.
        let notFiled = app.buttons["Not filed yet"].firstMatch
        XCTAssertTrue(app.revealInForm(notFiled), "the court case choice has no Not filed yet")
        notFiled.tap()
        XCTAssertTrue(poll(timeout: 5) { notFiled.isSelected }, "Not filed yet was not chosen")
        create.tap()

        XCTAssertTrue(app.waitGone(create), "the sheet stayed up")
        XCTAssertTrue(app.matterElement("matter-header").waitForExistence(timeout: 10), "the new matter did not open")
        XCTAssertTrue(app.labelled("Kapoor v. Kapoor").waitForExistence(timeout: 5))
        XCTAssertTrue(app.labelled("Not filed yet").exists, "the court status was not kept")
    }

    func testEditingDetailsChangesTheHeader() {
        let app = XCUIApplication.launchedSignedIn()
        app.openMatter("prj-arb")
        XCTAssertTrue(app.matterElement("matter-header").waitForExistence(timeout: 10))

        let save = app.openMatterMenuItem("matter-edit", label: "Edit details", showing: "matter-details-save")
        XCTAssertTrue(save.exists, "Edit details did not open")
        app.type("77", into: app.matterElement("matter-field-caseNumber"))
        app.type("2026", into: app.matterElement("matter-field-caseYear"))
        save.tap()

        XCTAssertTrue(app.waitGone(save), "the form stayed up")
        XCTAssertTrue(app.labelled("77/2026").waitForExistence(timeout: 10), "the header does not show the new number")
    }

    func testArchivingMovesTheMatterToArchived() {
        let app = XCUIApplication.launchedSignedIn()
        app.openMatter("prj-arb")
        XCTAssertTrue(app.matterElement("matter-header").waitForExistence(timeout: 10))

        app.tapMatterMenuItem("matter-archive", label: "Archive")
        XCTAssertTrue(app.labelled("Archived").waitForExistence(timeout: 10), "the status did not change")

        let back = app.navigationBars.buttons["Matters"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "there is no way back")
        back.tap()
        XCTAssertTrue(poll { !app.matterRow("prj-arb").exists }, "an archived matter is still under Active")
        let status = app.buttons["matters-status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        status.tap()
        let archived = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Archived")).firstMatch
        XCTAssertTrue(archived.waitForExistence(timeout: 5))
        archived.tap()
        XCTAssertTrue(app.matterRow("prj-arb").waitForExistence(timeout: 5), "the matter is not under Archived")
    }

    func testDeleteNeedsTheExactName() {
        let app = XCUIApplication.launchedSignedIn()
        app.openMatter("prj-arb")
        XCTAssertTrue(app.matterElement("matter-header").waitForExistence(timeout: 10))

        let confirm = app.openMatterMenuItem("matter-delete", label: "Delete…", showing: "delete-matter-confirm")
        XCTAssertTrue(confirm.exists, "Delete did not open")
        let field = app.matterElement("delete-matter-name")
        app.type("Suvarnapatnam Infra", into: field)
        XCTAssertFalse(confirm.isEnabled, "a partial name was accepted")
        app.type(" v. Ashwatth Builders", into: field)
        XCTAssertTrue(poll { confirm.isEnabled }, "the exact name was not accepted")
        confirm.tap()

        XCTAssertTrue(app.waitGone(confirm), "the sheet stayed up")
        XCTAssertTrue(app.matterRow("prj-writ").waitForExistence(timeout: 10), "the list did not come back")
        XCTAssertTrue(poll { !app.matterRow("prj-arb").exists }, "the deleted matter is still listed")
    }

    func testAddingATaskThenTickingItMovesItToDone() {
        let app = XCUIApplication.launchedSignedIn()
        app.openMatter("prj-writ")
        XCTAssertTrue(app.matterElement("matter-header").waitForExistence(timeout: 10))
        app.openSection("tasks")

        let save = app.openSheet(app.matterElement("tasks-add"), showing: "task-save")
        XCTAssertTrue(save.exists, "Add task did not open")
        app.type("Inspect the record", into: app.matterElement("task-title"))
        save.tap()
        XCTAssertTrue(app.waitGone(save), "the form stayed up")

        let tick = app.buttons["Mark Inspect the record done"].firstMatch
        XCTAssertTrue(app.waitAndReveal(tick, timeout: 10), "the new task is not listed")
        tick.tap()
        XCTAssertTrue(app.buttons["Reopen Inspect the record"].firstMatch.waitForExistence(timeout: 10),
                      "the task did not move to Done")
    }

    func testAPaymentShowsTheAmountInWordsAndOffersAReceipt() {
        let app = XCUIApplication.launchedSignedIn()
        app.openMatter("prj-writ")
        XCTAssertTrue(app.matterElement("matter-header").waitForExistence(timeout: 10))
        app.openSection("fees")

        let save = app.openSheet(app.matterElement("fees-add-payment"), showing: "ledger-save")
        XCTAssertTrue(save.exists, "Add payment did not open")
        app.type("25000", into: app.matterElement("ledger-amount"))
        XCTAssertTrue(app.labelled("Rupees Twenty Five Thousand Only").waitForExistence(timeout: 5),
                      "the amount is not in words")
        save.tap()
        XCTAssertTrue(app.waitGone(save), "the form stayed up")

        let receipt = app.matterElement("ledger-receipt-led-payment")
        XCTAssertTrue(app.waitAndReveal(receipt, timeout: 10), "a payment offers no receipt")
        receipt.tap()
        XCTAssertTrue(app.matterElement("receipt-preview").waitForExistence(timeout: 15), "the receipt did not open")
    }

    func testAChronologyEntryAppearsInTheTimeline() {
        let app = XCUIApplication.launchedSignedIn()
        app.openMatter("prj-writ")
        XCTAssertTrue(app.matterElement("matter-header").waitForExistence(timeout: 10))
        app.openSection("chronology")

        let save = app.openSheet(app.matterElement("chronology-add"), showing: "chronology-save")
        XCTAssertTrue(save.exists, "Add entry did not open")
        app.type("Rejoinder served", into: app.matterElement("chronology-title"))
        save.tap()
        XCTAssertTrue(app.waitGone(save), "the form stayed up")
        XCTAssertTrue(app.labelled("Rejoinder served").waitForExistence(timeout: 10), "the entry is not on the record")
    }

    func testRefreshingTwiceSaysToWait() {
        let app = XCUIApplication.launchedSignedIn()
        app.openMatter("prj-writ")
        XCTAssertTrue(app.matterElement("matter-header").waitForExistence(timeout: 10))
        app.openSection("court")

        let refresh = app.matterElement("court-refresh")
        XCTAssertTrue(app.waitAndReveal(refresh, timeout: 10), "there is no refresh")
        refresh.tap()
        XCTAssertTrue(app.labelled("Court record refreshed").waitForExistence(timeout: 10), "the first refresh did not land")

        XCTAssertTrue(poll { refresh.exists && refresh.isEnabled && refresh.isHittable }, "refresh did not come back")
        refresh.tap()
        XCTAssertTrue(app.matterElement("court-refresh-wait").waitForExistence(timeout: 10),
                      "the second refresh did not say to wait")
        XCTAssertTrue(app.labelled("Refresh in").exists)
    }
}

extension XCUIApplication {

    /// Taps `trigger`, again up to three times, until the sheet's `action` is on screen; answers
    /// the action. A tap can be swallowed by a list still settling.
    @discardableResult
    func openSheet(_ trigger: XCUIElement, showing action: String) -> XCUIElement {
        let target = descendants(matching: .any).matching(identifier: action).firstMatch
        guard waitAndReveal(trigger, timeout: 10) else { return target }
        for _ in 0..<3 {
            guard trigger.exists, trigger.isHittable else { break }
            trigger.tap()
            if target.waitForExistence(timeout: 5) { return target }
        }
        return target
    }

    /// The workspace's "…" menu, then one of its items, which opens a sheet with `action`.
    @discardableResult
    func openMatterMenuItem(_ item: String, label: String, showing action: String) -> XCUIElement {
        let target = descendants(matching: .any).matching(identifier: action).firstMatch
        for _ in 0..<3 {
            tapMatterMenuItem(item, label: label)
            if target.waitForExistence(timeout: 5) { return target }
        }
        return target
    }

    /// The workspace's "…" menu, then the item by its identifier — or its label, which a menu
    /// item does not always carry the identifier under.
    func tapMatterMenuItem(_ item: String, label: String) {
        let menu = descendants(matching: .any).matching(identifier: "matter-menu").firstMatch
        guard menu.waitForExistence(timeout: 10) else { return }
        menu.tap()
        let byID = buttons[item].firstMatch
        if byID.waitForExistence(timeout: 3) {
            byID.tap()
        } else {
            let byLabel = buttons[label].firstMatch
            if byLabel.waitForExistence(timeout: 3) { byLabel.tap() }
        }
    }

    /// Focuses a field and types into it. The fields are in a matter form's sheet, so a field
    /// out of sight is scrolled to inside the form (`revealInForm`). On iPad the form sheet can
    /// still be settling when the tap lands, leaving nothing focused, so the field is tapped until
    /// it holds the keyboard (`focusForTyping`) — and again before more is typed, if it let go.
    func type(_ text: String, into field: XCUIElement) {
        guard revealInForm(field) else { return }
        if (field.value(forKey: "hasKeyboardFocus") as? Bool) != true {
            field.focusForTyping()
        }
        field.typeText(text)
    }

    /// Waits for `element` in the open matter form (`MatterFormSheet`, named "matter-form") and
    /// drags the form until it can be tapped, answering whether it can. A form builds only the
    /// rows near what it shows, so a row below the fold is not there until scrolled to; and a
    /// swipe from the middle of the screen — `reveal` — lands on the sheet's footer, the keyboard
    /// or the screen behind the sheet once the keyboard is up, and scrolls nothing. So the drag
    /// is made inside the form, between its top and the keyboard's.
    @discardableResult
    func revealInForm(_ element: XCUIElement, tries: Int = 8) -> Bool {
        if element.waitForExistence(timeout: 3), element.isHittable { return true }
        let named = collectionViews["matter-form"].firstMatch
        let form = named.waitForExistence(timeout: 5)
            ? named : collectionViews.allElementsBoundByIndex.last ?? named
        guard form.exists else { return waitAndReveal(element) }
        var drags = 0
        while !(element.exists && element.isHittable), drags < tries {
            let frame = form.frame
            let keyboard = keyboards.firstMatch
            let keyboardTop: CGFloat = keyboard.exists ? keyboard.frame.minY : frame.maxY
            let bottom: CGFloat = min(frame.maxY, keyboardTop)
            let height: CGFloat = bottom - frame.minY
            guard height > 60 else { break }
            let origin = coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            let start = origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY + height * 0.8))
            let end = origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY + height * 0.25))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            drags += 1
        }
        return element.waitForExistence(timeout: 2) && element.isHittable
    }
}
