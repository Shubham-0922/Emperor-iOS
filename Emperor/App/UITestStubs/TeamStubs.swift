#if DEBUG
import Foundation

/// The UI tests' canned answers for teams. Answers nothing yet: `nil` lets
/// `UITestSupport` answer as it always has. Owned by package 11-T; honours
/// `UITestSupport.isEmpty` itself once it answers anything.
enum TeamStubs {
    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        nil
    }
}
#endif
