#if DEBUG
import Foundation

/// The UI tests' canned answers for the court lookup and case routes. Answers nothing yet: `nil` lets
/// `UITestSupport` answer as it always has. Owned by package 06-C; honours
/// `UITestSupport.isEmpty` itself once it answers anything.
enum CasesStubs {
    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        nil
    }
}
#endif
