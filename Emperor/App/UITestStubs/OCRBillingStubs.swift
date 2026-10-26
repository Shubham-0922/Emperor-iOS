#if DEBUG
import Foundation

/// The UI tests' canned answers for OCR job detail and the billing meter. Answers nothing yet: `nil` lets
/// `UITestSupport` answer as it always has. Owned by package 08-O; honours
/// `UITestSupport.isEmpty` itself once it answers anything.
enum OCRBillingStubs {
    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        nil
    }
}
#endif
