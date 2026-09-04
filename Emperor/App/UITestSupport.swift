#if DEBUG
import Foundation

/// Runs the app against a canned server, for the simulator UI tests.
///
/// ## Why a stubbed transport rather than fake services
///
/// `Session` already takes a `URLSession`, so a `URLProtocol` can answer every request without
/// touching the network. That means the UI tests drive the **real** services, view models,
/// decoders and stream parser — the whole stack the app actually ships — and only the socket is
/// replaced. Swapping in fake services would have tested the fakes.
///
/// It also means the fixtures below are a second, independent check on the wire contract: a
/// response shape that `APIModels` cannot decode fails the UI test as a blank screen, exactly as
/// it would against the real server.
///
/// ## Why this ships in the binary
///
/// `#if DEBUG` and inert without `-UITestMode`, so it is compiled out of any Release build and
/// does nothing in the debug build you sideload. The alternative — a separate scheme — buys
/// nothing and risks the tests exercising a target that is not the app.
enum UITestSupport {

    static let launchArgument = "-UITestMode"

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// Start signed in. Sign-*out* is still exercised, from Settings.
    static var isSignedIn: Bool {
        !ProcessInfo.processInfo.arguments.contains("-UITestSignedOut")
    }

    /// Every list empty, so the empty states can be driven — they are a third of the branches in
    /// `ListStateView` and the easiest to get wrong.
    static var isEmpty: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestEmpty")
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// Answers the routes the screens under test call.
    ///
    /// Anything unlisted returns 200 with an empty object rather than failing: a screen this
    /// suite does not cover should not take the app down on some unrelated fetch, and a test
    /// that depends on a route it never declared is a test that is lying about its subject.
    final class StubProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}

        override func startLoading() {
            let path = request.url?.path.replacingOccurrences(of: "/api", with: "") ?? ""
            let body = Fixtures.body(for: path)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    /// The canned responses. Shapes are taken from the real routes, not invented — a fixture the
    /// decoder rejects would make the screen blank and the failure would read as a UI bug.
    enum Fixtures {
        static func body(for path: String) -> String {
            if isEmpty, let empty = emptyBody(for: path) { return empty }
            switch path {
            case "/login", "/register":
                return #"{"token":"ui-test-token","user":{"id":1,"name":"Test Advocate","email":"test@example.com"}}"#
            case "/chats":
                return #"{"chats":[{"id":"c1","title":"Bakshi v. State","updatedAt":"2026-09-01T10:00:00.000Z"}]}"#
            case "/messages":
                return #"{"messages":[]}"#
            case "/cases":
                return #"{"cases":[{"id":"case1","title":"Bakshi v. State of Maharashtra","court_name":"Bombay High Court","next_hearing_date":"2026-09-20"}]}"#
            case "/case":
                return #"{"case":{"id":"case1","title":"Bakshi v. State of Maharashtra","court_name":"Bombay High Court"},"events":[]}"#
            case "/cause-list":
                return #"{"cases":[{"id":"case1","title":"Bakshi v. State of Maharashtra","court_name":"Bombay High Court","next_hearing_date":"2026-09-20"}]}"#
            case "/compliance":
                return #"{"events":[{"id":"e1","title":"File written statement","kind":"task","due_date":"2026-09-15"}]}"#
            case "/notifications":
                return #"{"notifications":[{"id":"n1","title":"Hearing listed","message":"Bakshi v. State is listed","is_read":0,"created_at":"2026-09-01T10:00:00.000Z"}]}"#
            case "/notifications/unread-count":
                return #"{"count":1}"#
            case "/user-files":
                return #"{"files":[{"name":"petition.pdf","folderName":"Bakshi","status":"ready","size":12345}]}"#
            case "/library/categories":
                return #"{"categories":[{"id":"bare-acts","label":"Bare Acts","count":42}]}"#
            case "/library/browse":
                return #"{"items":[{"id":"l1","title":"Code of Civil Procedure, 1908"}],"total":1}"#
            case "/auction-notices":
                return #"{"notices":[{"id":"a1","corporate_debtor":"Bhushan Steel Ltd","auction_date":"2026-10-01"}],"total":1}"#
            case "/auction-notices/facets":
                return #"{"types":[],"platforms":[]}"#
            case "/documents", "/tables":
                return #"{"documents":[]}"#
            default:
                return "{}"
            }
        }

        /// `nil` means "this route has no distinct empty shape", so the normal body is used.
        private static func emptyBody(for path: String) -> String? {
            switch path {
            case "/chats": return #"{"chats":[]}"#
            case "/cases", "/cause-list": return #"{"cases":[]}"#
            case "/compliance": return #"{"events":[]}"#
            case "/notifications": return #"{"notifications":[]}"#
            case "/notifications/unread-count": return #"{"count":0}"#
            case "/user-files": return #"{"files":[]}"#
            case "/library/browse": return #"{"items":[],"total":0}"#
            case "/auction-notices": return #"{"notices":[],"total":0}"#
            default: return nil
            }
        }
    }
}
#endif
