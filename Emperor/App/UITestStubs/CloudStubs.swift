#if DEBUG
import Foundation

/// The UI tests' canned answers for cloud drives. Answers nothing yet: `nil` lets
/// `UITestSupport` answer as it always has. Owned by package 15-CL; honours
/// `UITestSupport.isEmpty` itself once it answers anything.
enum CloudStubs {
    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        nil
    }
}
#endif
