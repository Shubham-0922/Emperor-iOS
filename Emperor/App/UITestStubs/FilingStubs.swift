#if DEBUG
import Foundation

/// The UI tests' canned answers for filing assembly. Answers nothing yet: `nil` lets
/// `UITestSupport` answer as it always has. Owned by package 13-F1, then 13-F2; honours
/// `UITestSupport.isEmpty` itself once it answers anything.
enum FilingStubs {
    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        nil
    }
}
#endif
