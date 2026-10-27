#if DEBUG
import Foundation

/// The UI tests' canned answers for cloud drives: `/cloud/connections`, `/cloud/connect`,
/// `/cloud/disconnect`, `/cloud/list`, `/cloud/import`, `/cloud/export`. Owned by package 15-CL.
///
/// Stateful for the life of the launch. Google Drive is set up and not connected; OneDrive is not
/// set up. Asking for the sign-in page arms the next read of the connections to say Google Drive
/// is connected, as a real sign-in finished in Safari would. `-UITestCloudConnected` starts
/// connected; `-UITestCloudOff` (and `-UITestEmpty`) has neither drive set up.
enum CloudStubs {

    static var isOff: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-UITestCloudOff") || UITestSupport.isEmpty
    }

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var connected: Bool
        private var connectsOnNextRead = false

        init() {
            connected = ProcessInfo.processInfo.arguments.contains("-UITestCloudConnected")
        }

        func connectionsJSON() -> String {
            lock.lock(); defer { lock.unlock() }
            if connectsOnNextRead {
                connectsOnNextRead = false
                connected = true
            }
            let configured = CloudStubs.isOff ? "false" : "true"
            let isConnected = (connected && !CloudStubs.isOff) ? "true" : "false"
            let email = (connected && !CloudStubs.isOff) ? #""advocate@example.com""# : "null"
            let google = #"{"label":"Google Drive","configured":\#(configured),"connected":\#(isConnected),"email":\#(email)}"#
            let microsoft = #"{"label":"OneDrive","configured":false,"connected":false,"email":null}"#
            return #"{"success":true,"providers":{"google":\#(google),"microsoft":\#(microsoft)}}"#
        }

        func armConnect() {
            lock.lock(); defer { lock.unlock() }
            connectsOnNextRead = true
        }

        func disconnect() {
            lock.lock(); defer { lock.unlock() }
            connected = false
            connectsOnNextRead = false
        }
    }

    private static let store = Store()

    private static let listJSON = """
        {"success":true,"files":[{"id":"cf1","name":"a.pdf","mime":"application/pdf","size":2048,\
        "modified":"2026-10-01T09:00:00.000Z"},{"id":"cf2","name":"b.docx","mime":null,"size":4096,\
        "modified":"2026-09-20T09:00:00.000Z"}]}
        """

    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        switch (request.httpMethod ?? "GET", path) {
        case ("GET", "/cloud/connections"):
            return .json(store.connectionsJSON())
        case ("GET", "/cloud/connect"):
            if isOff {
                return .json(
                    #"{"success":false,"error":"Google Drive is not configured on this server"}"#, status: 400)
            }
            store.armConnect()
            return .json(#"{"success":true,"url":"https://accounts.google.com/o/oauth2/v2/auth?stub=1"}"#)
        case ("POST", "/cloud/disconnect"):
            store.disconnect()
            return .json(#"{"success":true}"#)
        case ("GET", "/cloud/list"):
            return .json(listJSON)
        case ("POST", "/cloud/import"):
            let body = UITestSupport.Fixtures.jsonBody(of: request) ?? [:]
            let name = body["fileName"] as? String ?? "file"
            let folder = body["folderName"] as? String ?? "."
            return .json(#"{"success":true,"fileName":"\#(name)","folderName":"\#(folder)","size":2048}"#)
        case ("POST", "/cloud/export"):
            let body = UITestSupport.Fixtures.jsonBody(of: request) ?? [:]
            let name = body["fileName"] as? String ?? "file"
            return .json(#"{"success":true,"id":"x","name":"\#(name)","url":"https://drive.google.com/file/d/x/view"}"#)
        default:
            return nil
        }
    }
}
#endif
