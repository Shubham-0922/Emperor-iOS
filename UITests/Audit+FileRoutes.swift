import XCTest

extension AccessibilityAuditTests {

    /// A Word document the server could not convert, shown as its extracted text.
    func testTheExtractedTextPassesTheAudit() {
        let app = launch("-UITestOfficeFails")
        guard signIn(app) else { return }
        guard app.openBoardResolution() else {
            XCTFail("the Word document did not open")
            return
        }
        let banner = app.descendants(matching: .any).matching(identifier: "file-text-banner").firstMatch
        guard reached(banner, "the extracted text", timeout: 15) else { return }
        audit("extracted-text", in: app)
    }
}
