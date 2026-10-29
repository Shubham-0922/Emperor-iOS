#if DEBUG
import Foundation

/// The UI tests' canned answers for the small file routes: a document's extracted text and the
/// maintenance notice.
///
/// Under `-UITestOfficeFails` the Word converter refuses, so the viewer falls back to the
/// extracted text; under `-UITestMaintenance` the platform is down. `-UITestEmpty` leaves the
/// extracted text empty.
enum FileRouteStubs {

    private static func flag(_ name: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(name)
    }

    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        switch (request.httpMethod ?? "GET", path) {
        case ("GET", "/office-preview") where flag("-UITestOfficeFails"):
            return .json(#"{"success":false,"reason":"busy"}"#)
        case ("GET", "/file-text"):
            if UITestSupport.isEmpty {
                return .json(#"{"success":true,"fileExists":true,"totalPages":0,"matchedBy":null,"truncated":false,"pages":[]}"#)
            }
            return .json(fileText)
        case ("GET", "/maintenance"):
            return .json(flag("-UITestMaintenance")
                ? #"{"enabled":true,"message":"Back at 6","since":null,"bypass":false,"active":true}"#
                : #"{"enabled":false,"message":null,"since":null,"bypass":false,"active":false}"#)
        default:
            return nil
        }
    }

    /// Two pages of a board resolution, as the extractor read them.
    private static let fileText = ###"{"success":true,"fileName":"Board_Resolution.docx","fileExists":true,"totalPages":2,"matchedBy":"path","truncated":false,"pages":[{"page":1,"content":"# Board Resolution\n\nRESOLVED that the company shall file the reply before the Tribunal."},{"page":2,"content":"## Authority\n\nThe Managing Director is authorised to sign the affidavit."}]}"###
}
#endif
