import XCTest

extension AccessibilityAuditTests {

    /// Opens the Library from More, signed in, with the shelves on screen.
    private func openLibraryForAudit() -> XCUIApplication? {
        let app = launch()
        guard signIn(app) else { return nil }
        guard app.openLibrary() else {
            XCTFail("the Library did not open")
            return nil
        }
        guard reached(app.library("library-doc-2478"), "the Bare Acts shelf", timeout: 15) else { return nil }
        return app
    }

    /// The home shelves.
    func testTheLibraryHomePassesTheAudit() {
        guard let app = openLibraryForAudit() else { return }
        audit("library-home", in: app, sheet: app.navigationBars["Library"])
    }

    /// Case Law, with its court chips, count and numbered pages.
    func testTheLibraryCollectionPassesTheAudit() {
        guard let app = openLibraryForAudit() else { return }
        let chip = app.library("library-category-case-law")
        guard reached(chip, "the Case law chip") else { return }
        chip.tap()
        guard reached(app.library("library-page-label"), "Case law's pages", timeout: 15) else { return }
        audit("library-collection", in: app, sheet: app.navigationBars["Case law"])
    }

    /// Case Law's filter sheet.
    func testTheLibraryFilterSheetPassesTheAudit() {
        guard let app = openLibraryForAudit() else { return }
        let chip = app.library("library-category-case-law")
        guard reached(chip, "the Case law chip") else { return }
        chip.tap()
        let filters = app.library("library-filters")
        guard reached(filters, "the filter button", timeout: 15) else { return }
        filters.tap()
        guard reached(app.library("library-filter-courts-delhi"), "the court filters") else { return }
        audit("library-filter-sheet", in: app, sheet: app.staticTexts["Filters and sort"].firstMatch)
    }

    /// The judgment reader.
    func testTheLibraryJudgmentPassesTheAudit() {
        guard let app = openLibraryForAudit() else { return }
        guard app.openShelfDocument(257708, shelf: "case-law") else {
            XCTFail("the judgment did not open")
            return
        }
        guard reached(app.library("judgment-block-h-1"), "the judgment", timeout: 15) else { return }
        audit("library-judgment", in: app, sheet: app.navigationBars.firstMatch)
    }

    /// An Act page with its tabs and instruments.
    func testTheLibraryActPagePassesTheAudit() {
        guard let app = openLibraryForAudit() else { return }
        guard app.openShelfDocument(2478, shelf: "bare-acts") else {
            XCTFail("the Act page did not open")
            return
        }
        guard reached(app.library("library-instrument-2478"), "the Act's instruments", timeout: 15) else { return }
        audit("library-act", in: app, sheet: app.navigationBars.firstMatch)
    }
}
