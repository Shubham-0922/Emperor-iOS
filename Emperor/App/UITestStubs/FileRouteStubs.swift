#if DEBUG
import Foundation

/// The UI tests' canned answers for the small file routes: saving an edited draft, a folder as
/// one archive, a document's extracted text, the server's PDF, the account's starting model and
/// the maintenance notice. Owned by package 14-X.
///
/// Stateful for the life of the launch: a saved draft reads back as saved. Under
/// `-UITestDraftEdit` the drafts list holds one HTML draft; under `-UITestOfficeFails` the Word
/// converter refuses, so the viewer falls back to the extracted text; under `-UITestMaintenance`
/// the platform is down. `-UITestEmpty` leaves the drafts list and the extracted text empty.
enum FileRouteStubs {

    static let draftHTML = "<h1>Plaint</h1><p>Draft text</p>"

    private static func flag(_ name: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(name)
    }

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var saved: String?
        private(set) var lastSave: [String: Any] = [:]
        private(set) var model: String?

        func save(_ body: [String: Any]) {
            lock.withLock {
                lastSave = body
                saved = body["content"] as? String
            }
        }

        var content: String { lock.withLock { saved ?? FileRouteStubs.draftHTML } }

        func setModel(_ value: String?) { lock.withLock { model = value } }
    }

    private static let store = Store()

    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        switch (request.httpMethod ?? "GET", path) {
        case ("POST", "/save-document"):
            let body = UITestSupport.Fixtures.jsonBody(of: request) ?? [:]
            guard let content = body["content"] as? String, !content.isEmpty else {
                return .json(#"{"error":"Missing userId or content"}"#, status: 500)
            }
            store.save(body)
            let id = body["id"] as? String ?? "d1"
            return .json(#"{"success":true,"id":"\#(id)","type":"doc","deduped":false,"reclassified":false}"#)
        case ("GET", "/documents") where flag("-UITestDraftEdit"):
            if UITestSupport.isEmpty { return .json(#"{"success":true,"documents":[],"tables":[]}"#) }
            let row = #"{"id":"d1","chat_id":"c1","title":"Plaint","type":"doc","created_at":"2026-10-01 09:00:00","chat_title":"Bakshi"}"#
            return .json(#"{"success":true,"documents":[\#(row)],"tables":[\#(row)]}"#)
        case ("GET", "/documents/content") where flag("-UITestDraftEdit"):
            return .json(contentJSON(store.content))
        case ("POST", "/download-files"):
            return .bytes(zipBytes, type: "application/zip")
        case ("GET", "/office-preview") where flag("-UITestOfficeFails"):
            return .json(#"{"success":false,"reason":"busy"}"#)
        case ("GET", "/file-text"):
            if UITestSupport.isEmpty {
                return .json(#"{"success":true,"fileExists":true,"totalPages":0,"matchedBy":null,"truncated":false,"pages":[]}"#)
            }
            return .json(fileText)
        case ("POST", "/print-pdf"):
            return .bytes(minimalPDF, type: "application/pdf")
        case ("POST", "/set-preferred-model"):
            let body = UITestSupport.Fixtures.jsonBody(of: request) ?? [:]
            store.setModel(body["model"] as? String)
            return .json(#"{"success":true}"#)
        case ("GET", "/maintenance"):
            return .json(flag("-UITestMaintenance")
                ? #"{"enabled":true,"message":"Back at 6","since":null,"bypass":false,"active":true}"#
                : #"{"enabled":false,"message":null,"since":null,"bypass":false,"active":false}"#)
        default:
            return nil
        }
    }

    /// `{"success":true,"content":…}`, the content escaped as JSON.
    private static func contentJSON(_ content: String) -> String {
        let object: [String: Any] = ["success": true, "content": content]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            return #"{"success":true,"content":""}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Two pages of a board resolution, as the extractor read them.
    private static let fileText = ###"{"success":true,"fileName":"Board_Resolution.docx","fileExists":true,"totalPages":2,"matchedBy":"path","truncated":false,"pages":[{"page":1,"content":"# Board Resolution\n\nRESOLVED that the company shall file the reply before the Tribunal."},{"page":2,"content":"## Authority\n\nThe Managing Director is authorised to sign the affidavit."}]}"###

    /// The local-file-header signature and nothing more: enough for the client's check, and the
    /// share sheet only needs a file.
    private static let zipBytes = Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00])

    private static let minimalPDF = Data("""
        %PDF-1.4
        1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
        2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
        3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >> endobj
        trailer << /Root 1 0 R >>
        %%EOF
        """.utf8)
}
#endif
