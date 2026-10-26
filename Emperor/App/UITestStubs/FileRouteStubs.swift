#if DEBUG
import Foundation

/// The UI tests' canned answers for the file routes (save, zip, text, print). Answers nothing yet: `nil` lets
/// `UITestSupport` answer as it always has. Owned by package 14-X; honours
/// `UITestSupport.isEmpty` itself once it answers anything.
enum FileRouteStubs {
    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        nil
    }
}
#endif
