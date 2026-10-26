import XCTest

// Shared helpers for the feature UI tests, tours and audits that live in files of their own
// (`<Feature>UITests.swift`, `<Feature>Tour.swift`, `Audit+<Feature>.swift`).

extension XCTestCase {

    /// Polls `until` every quarter second until it holds or `timeout` passes, and returns
    /// whether it held. An expectation would not compile in this target under Swift 6.
    @discardableResult
    func poll(timeout: TimeInterval = 10, until: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if until() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return until()
    }

    /// One tour photograph, named as `ScreenshotTour` names its own — `<theme>-<step>-<name>` —
    /// after the same settle, so CI files it beside them.
    func tourSnap(_ app: XCUIApplication, theme: String, step: inout Int, _ name: String) {
        step += 1
        // Let animations and loads settle; a half-drawn transition is not what a person sees.
        Thread.sleep(forTimeInterval: 0.8)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = String(format: "%@-%02d-%@", theme, step, name)
        shot.lifetime = .keepAlways
        add(shot)
    }
}

extension XCUIApplication {

    /// The app launched against the stub server and signed in, with the tabs on screen.
    /// `extra` are further launch arguments; `light` draws the light theme.
    static func launchedSignedIn(_ extra: [String] = [], light: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode"] + extra + (light ? ["-UITestLight"] : [])
        app.launch()
        if app.textFields["Email"].waitForExistence(timeout: 15) {
            app.signInWithACode()
        }
        _ = app.tab("Home").waitForExistence(timeout: 15)
        return app
    }

    /// Opens a case tool from More: the More tab, the card scrolled to, then tapped — again, up
    /// to three taps in all, while no sheet has come up (a tap can be swallowed by a sheet still
    /// leaving). `tool` is the `WorkspaceTool` raw value, as in the card's identifier
    /// `case-tool-<tool>`. Every tool screen carries "Done" in its bar and More does not, so a
    /// "Done" in a bar is the sheet having opened — the card itself may still read as hittable
    /// behind an iPad's form sheet, and a tap there would dismiss it.
    func openCaseTool(_ tool: String) {
        let more = tab("More")
        guard more.waitForExistence(timeout: 10) else { return }
        more.tap()
        let card = buttons["case-tool-\(tool)"].firstMatch
        guard card.waitForExistence(timeout: 10) else { return }
        reveal(card)
        let done = navigationBars.buttons["Done"].firstMatch
        for _ in 0..<3 {
            guard card.exists, card.isHittable else { return }
            card.tap()
            if done.waitForExistence(timeout: 5) { return }
        }
    }

    /// Waits until `e` has gone — a sheet's bar after Done, say — and returns whether it did.
    @discardableResult
    func waitGone(_ e: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !e.exists { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return !e.exists
    }
}
