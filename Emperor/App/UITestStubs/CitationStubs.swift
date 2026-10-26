#if DEBUG
import Foundation

/// The UI tests' canned answers for citations and their sources. Answers nothing yet: `nil` lets
/// `UITestSupport` answer as it always has. Owned by package 07-P7; honours
/// `UITestSupport.isEmpty` itself once it answers anything.
enum CitationStubs {
    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        nil
    }
}
#endif
