#if DEBUG
import Foundation

/// The UI tests' canned answers for the Limitation Radar. Answers nothing yet: `nil` lets
/// `UITestSupport` answer as it always has. Owned by package 10-R; honours
/// `UITestSupport.isEmpty` itself once it answers anything.
enum RadarStubs {
    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        nil
    }
}
#endif
