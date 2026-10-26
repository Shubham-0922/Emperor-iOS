#if DEBUG
import Foundation

/// The UI tests' canned answers for the analysis tools. Answers nothing yet: `nil` lets
/// `UITestSupport` answer as it always has. Owned by package 12-AN; honours
/// `UITestSupport.isEmpty` itself once it answers anything.
enum AnalysisStubs {
    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        nil
    }
}
#endif
