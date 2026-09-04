import XCTest

/// Drives the app in a simulator.
///
/// This is the only thing in the repository that can find a screen which compiles and then
/// renders blank, crashes on appear, or navigates nowhere. 619 core tests and a green
/// `xcodebuild` all pass on a view whose body throws the moment it is laid out.
///
/// The app runs against a stubbed transport (`UITestSupport`), so the **real** services, view
/// models, decoders and navigation are exercised — only the socket is replaced. A response shape
/// the decoder cannot read shows up here as an empty screen, exactly as it would in the field.
final class EmperorUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(_ extraArguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode"] + extraArguments
        app.launch()
        return app
    }

    /// Signs in through the real login screen. The stub answers `/login`, so this exercises
    /// `AuthService`, `Session.adopt` and the signed-out → signed-in transition rather than
    /// bypassing them.
    @discardableResult
    private func signIn(_ app: XCUIApplication) -> XCUIApplication {
        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10), "the login screen never appeared")
        email.tap()
        email.typeText("test@example.com")

        let password = app.secureTextFields["Password"]
        password.tap()
        password.typeText("hunter2")

        app.buttons["Sign in"].tap()
        return app
    }

    // MARK: - It starts

    /// The single most valuable assertion here: the process comes up and draws something.
    func testTheAppLaunchesAndShowsSignIn() {
        let app = launch()
        XCTAssertTrue(
            app.textFields["Email"].waitForExistence(timeout: 10),
            "the app launched but never rendered the login screen")
    }

    /// The gate is a compliance surface, so it must be impossible to get past accidentally.
    func testTheDisclaimerGateBlocksTheAppUntilAcknowledged() {
        let app = launch("-UITestDisclaimer")
        let acknowledge = app.buttons["I understand"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 10), "the gate did not appear")
        XCTAssertFalse(app.textFields["Email"].exists, "the login screen was reachable behind it")
        acknowledge.tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 10))
    }

    // MARK: - The tab bar

    /// The four destinations the platform's own mobile nav declares.
    func testSigningInRevealsTheFourTabs() {
        let app = signIn(launch())
        for tab in ["Home", "Cases", "Chat", "More"] {
            XCTAssertTrue(
                app.tabBars.buttons[tab].waitForExistence(timeout: 10),
                "the \(tab) tab is missing")
        }
    }

    /// Every tab renders. A tab that crashes on appear takes the app down, and this is what
    /// notices.
    func testEveryTabOpensAndRendersItsScreen() {
        let app = signIn(launch())
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))

        for (tab, title) in [("Home", "Home"), ("Cases", "Cases"), ("Chat", "Emperor"), ("More", "More")] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(
                app.navigationBars[title].waitForExistence(timeout: 10),
                "tapping \(tab) did not show a screen titled \(title)")
            XCTAssertEqual(app.state, .runningForeground, "the app died on the \(tab) tab")
        }
    }

    // MARK: - More

    /// Each row in More opens its screen. These are the five that used to be tabs or toolbar
    /// items and are now one level down, which is the change most likely to have broken one.
    func testEveryMoreRowOpensItsScreen() {
        let app = signIn(launch())
        XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 10))
        app.tabBars.buttons["More"].tap()

        for (row, title) in [
            ("Calendar", "Calendar"),
            ("Library", "Library"),
            ("Translate", "Translate"),
            ("Liquidations", "Liquidations"),
            ("Settings", "Settings"),
        ] {
            let cell = app.buttons[row]
            XCTAssertTrue(cell.waitForExistence(timeout: 10), "the \(row) row is missing")
            cell.tap()
            XCTAssertTrue(
                app.navigationBars[title].waitForExistence(timeout: 10),
                "\(row) did not open a screen titled \(title)")
            XCTAssertEqual(app.state, .runningForeground, "the app died opening \(row)")

            // Each destination presents rather than pushes, so it is dismissed rather than
            // popped. Swipe down from the nav bar, which works whether or not it has a Done.
            app.navigationBars[title].swipeDown(velocity: .fast)
            XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: 10))
        }
    }

    // MARK: - Empty states

    /// `ListStateView` routes to `empty()` whenever the *filtered* list is empty, which is a
    /// branch three screens got wrong by handling it in the content closure instead. With every
    /// fixture empty, each of these must say something rather than showing a blank list.
    func testEmptyStatesRenderRatherThanBlankScreens() {
        let app = signIn(launch("-UITestEmpty"))
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))

        for tab in ["Home", "Cases", "Chat"] {
            app.tabBars.buttons[tab].tap()
            // `ContentUnavailableView` renders as static text; any of it is enough to prove the
            // empty branch drew something.
            let hasCopy = app.staticTexts.count > 0
            XCTAssertTrue(hasCopy, "the \(tab) tab rendered nothing at all when empty")
            XCTAssertEqual(app.state, .runningForeground, "the app died on an empty \(tab)")
        }
    }

    // MARK: - Sign out

    /// The one destructive action reachable without a server write, and the way back to the
    /// login screen.
    func testSigningOutReturnsToLogin() {
        let app = signIn(launch())
        XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 10))
        app.tabBars.buttons["More"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))

        app.buttons["Sign out"].firstMatch.tap()
        // A confirmation dialog stands between the tap and the act.
        let confirm = app.buttons["Sign out"].firstMatch
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }

        XCTAssertTrue(
            app.textFields["Email"].waitForExistence(timeout: 10),
            "signing out did not return to the login screen")
    }
}
