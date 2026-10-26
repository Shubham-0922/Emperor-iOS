#if DEBUG
import Foundation

/// The UI tests' canned answers for matters (hand-made projects). Answers nothing yet: `nil` lets
/// `UITestSupport` answer as it always has. Owned by package 03-MA, then 04-MB and 05-MC; honours
/// `UITestSupport.isEmpty` itself once it answers anything.
enum MattersStubs {
    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        nil
    }
}
#endif
