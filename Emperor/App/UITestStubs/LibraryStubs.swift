#if DEBUG
import Foundation

/// The UI tests' canned answers for the library catalogue. Answers nothing yet: `nil` lets
/// `UITestSupport` answer as it always has. Owned by package 09-L; honours
/// `UITestSupport.isEmpty` itself once it answers anything.
enum LibraryStubs {
    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        nil
    }
}
#endif
