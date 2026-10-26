import XCTest

/// Photographs the Library on the catalogue — the home shelves, a search, Case Law, its filter
/// sheet, a judgment and an Act page — in the dark theme and the light one.
final class LibraryTour: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testTheDarkLibraryTour() { tour(light: false) }
    func testTheLightLibraryTour() { tour(light: true) }

    private func tour(light: Bool) {
        let app = XCUIApplication.launchedSignedIn(light: light)
        let theme = light ? "light" : "dark"
        var step = 0
        guard app.openLibrary() else {
            tourSnap(app, theme: theme, step: &step, "library-launch-failed")
            return
        }
        _ = app.library("library-doc-2478").waitForExistence(timeout: 15)
        tourSnap(app, theme: theme, step: &step, "library-home")

        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.focusForTyping()
            search.typeText("penal\n")
            _ = app.library("library-passages").waitForExistence(timeout: 15)
            tourSnap(app, theme: theme, step: &step, "library-search")
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.exists { cancel.tap() }
        }

        let chip = app.library("library-category-case-law")
        if chip.waitForExistence(timeout: 10) {
            app.reveal(chip)
            chip.tap()
            _ = app.library("library-page-label").waitForExistence(timeout: 15)
            tourSnap(app, theme: theme, step: &step, "library-case-law")
            let filters = app.library("library-filters")
            if filters.waitForExistence(timeout: 5) {
                filters.tap()
                _ = app.library("library-filter-courts-delhi").waitForExistence(timeout: 10)
                tourSnap(app, theme: theme, step: &step, "library-filter-sheet")
                let close = app.buttons["Close"].firstMatch
                if close.exists { close.tap() }
                app.waitGone(app.library("library-filter-courts-delhi"))
            }
            let back = app.navigationBars["Case law"].buttons.element(boundBy: 0)
            if back.exists { back.tap() }
        }

        if app.openShelfDocument(257708, shelf: "case-law") {
            _ = app.library("judgment-block-h-1").waitForExistence(timeout: 15)
            tourSnap(app, theme: theme, step: &step, "library-judgment")
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap() }
        }

        if app.openShelfDocument(2478, shelf: "bare-acts") {
            _ = app.library("library-instrument-2478").waitForExistence(timeout: 15)
            tourSnap(app, theme: theme, step: &step, "library-act")
        }
    }
}
