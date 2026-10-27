import XCTest

extension XCUIApplication {

    func cloudElement(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Home → the profile button → Account & Profile, scrolled to Connected services. Answers
    /// whether Google Drive's row is on screen.
    @discardableResult
    func openConnectedServices() -> Bool {
        let home = tab("Home")
        guard home.waitForExistence(timeout: 10) else { return false }
        home.tap()
        let profile = buttons["home-profile"]
        guard profile.waitForExistence(timeout: 10) else { return false }
        let bar = navigationBars["Account & Profile"]
        for _ in 0..<3 {
            guard profile.exists, profile.isHittable else { break }
            profile.tap()
            if bar.waitForExistence(timeout: 5) { break }
        }
        guard bar.waitForExistence(timeout: 10) else { return false }
        return waitAndReveal(cloudElement("cloud-row-google"))
    }

    /// Files → Bakshi, the folder the import and export tests work in.
    @discardableResult
    func openBakshiForCloud() -> Bool {
        guard openMyFiles() else { return false }
        let folder = buttons["folder-Bakshi"]
        guard folder.waitForExistence(timeout: 10) else { return false }
        reveal(folder)
        folder.tap()
        return staticTexts["Plaint.pdf"].waitForExistence(timeout: 10)
    }

    /// The folder's Add menu → "From Google Drive", waiting for the import sheet's run button.
    @discardableResult
    func openCloudImport() -> Bool {
        let add = navigationBars.buttons["Add"].firstMatch
        guard add.waitForExistence(timeout: 10) else { return false }
        let item = buttons["From Google Drive"].firstMatch
        for _ in 0..<3 {
            add.tap()
            if item.waitForExistence(timeout: 5) { break }
            // The menu opened before the drives were read; close it and look again.
            add.tap()
        }
        guard item.exists else { return false }
        item.tap()
        return cloudElement("cloud-file-cf1").waitForExistence(timeout: 10)
    }
}

/// Cloud drives: connecting in the (stand-in) browser, disconnecting, importing, saving a file
/// to the drive, and a server with no drive set up.
final class CloudUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testConnectAutoClosesWhenConnected() {
        let app = XCUIApplication.launchedSignedIn()
        XCTAssertTrue(app.openConnectedServices(), "Connected services is not on Account")
        let connect = app.buttons["cloud-connect-google"]
        XCTAssertTrue(app.waitAndReveal(connect), "Google Drive offers no Connect")
        connect.tap()

        let page = app.cloudElement("cloud-browser-stub")
        XCTAssertTrue(page.waitForExistence(timeout: 10), "the sign-in page did not open")
        XCTAssertTrue(app.waitGone(page, timeout: 20), "the sign-in page did not close by itself")

        let disconnect = app.buttons["cloud-disconnect-google"]
        XCTAssertTrue(app.waitAndReveal(disconnect), "the row does not offer Disconnect")
        XCTAssertTrue(
            app.staticTexts["Connected as advocate@example.com"].waitForExistence(timeout: 10),
            "the row does not say who is connected")
    }

    func testDisconnectConfirms() {
        let app = XCUIApplication.launchedSignedIn(["-UITestCloudConnected"])
        XCTAssertTrue(app.openConnectedServices(), "Connected services is not on Account")
        let disconnect = app.buttons["cloud-disconnect-google"]
        XCTAssertTrue(app.waitAndReveal(disconnect), "the connected drive offers no Disconnect")
        disconnect.tap()

        let question = app.staticTexts["Disconnect Google Drive?"]
        XCTAssertTrue(question.waitForExistence(timeout: 10), "Disconnect was not asked first")
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "Disconnect")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        XCTAssertTrue(
            app.waitAndReveal(app.buttons["cloud-connect-google"]),
            "the drive did not go back to Connect")
    }

    /// The toast is kept on screen (`-UITestLongToasts`): it comes up as the sheet closes and the
    /// folder is read again, and a toast of four seconds can be gone before the simulator settles.
    func testImportTwoFilesIntoFolder() {
        let app = XCUIApplication.launchedSignedIn(["-UITestCloudConnected", "-UITestLongToasts"])
        XCTAssertTrue(app.openBakshiForCloud(), "the Bakshi folder did not open")
        XCTAssertTrue(app.openCloudImport(), "the import sheet did not list the drive")

        app.cloudElement("cloud-file-cf1").tap()
        let second = app.cloudElement("cloud-file-cf2")
        XCTAssertTrue(app.waitAndReveal(second))
        second.tap()
        let run = app.buttons["cloud-import-run"]
        XCTAssertTrue(poll { run.label.contains("Import 2") }, "the button reads: \(run.label)")
        run.tap()

        let toast = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Imported 2 files")).firstMatch
        if !toast.waitForExistence(timeout: 15) {
            // Say what was on screen instead: the sheet still up, or an alert over the folder.
            let alert = app.alerts.firstMatch
            let lines: [String] = alert.staticTexts.allElementsBoundByIndex.map { $0.label }
            let alertWords: String = alert.exists ? lines.joined(separator: " / ") : "no alert"
            XCTFail("no word that the files arrived (sheet open: \(run.exists), \(alertWords))")
            return
        }
        XCTAssertTrue(app.waitGone(run), "the import sheet stayed open")
    }

    func testExportFile() {
        let app = XCUIApplication.launchedSignedIn(["-UITestCloudConnected"])
        XCTAssertTrue(app.openBakshiForCloud(), "the Bakshi folder did not open")
        let document = app.staticTexts["Plaint.pdf"]
        let save = app.buttons["Save to Google Drive"].firstMatch
        for _ in 0..<3 {
            document.press(forDuration: 1.2)
            if save.waitForExistence(timeout: 5) { break }
        }
        XCTAssertTrue(save.exists, "the document's menu has no Save to Google Drive")
        save.tap()

        let saved = app.staticTexts["Plaint.pdf saved to Google Drive"]
        XCTAssertTrue(saved.waitForExistence(timeout: 15), "no word that the file was saved")
        let ok = app.alerts.buttons["OK"].firstMatch
        XCTAssertTrue(ok.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.buttons["Open"].exists, "the drive's link is not offered")
        ok.tap()
        XCTAssertTrue(app.waitGone(saved), "the confirmation did not close")
    }

    func testNotConfiguredShowsSoon() {
        let app = XCUIApplication.launchedSignedIn(["-UITestCloudOff"])
        XCTAssertTrue(app.openConnectedServices(), "Connected services is not on Account")
        let pill = app.cloudElement("status-pill-Not available yet")
        XCTAssertTrue(app.waitAndReveal(pill), "the drive is not said to be unavailable")
        XCTAssertTrue(app.staticTexts["Not configured on this server."].exists)
        XCTAssertFalse(app.buttons["cloud-connect-google"].exists, "an unavailable drive offers Connect")
    }
}
