#if DEBUG
import Foundation

/// The UI tests' canned answers for OCR job detail and the billing meter. Each answers only
/// under its own launch argument, so every other run is served as it always was.
///
/// - `-UITestOCRNotes`: one layout-engine job with a page breakdown and two warnings.
/// - `-UITestPlanDetail`: a Junior Associate plan sized in binary units, five days from ending.
enum OCRBillingStubs {
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        if UITestSupport.isEmpty { return nil }
        if arguments.contains("-UITestOCRNotes"), path == "/ocr-history" {
            return .json(ocrHistory)
        }
        if arguments.contains("-UITestPlanDetail") {
            switch path {
            case "/billing/entitlements": return .json(entitlements)
            case "/billing/me": return .json(billingMe())
            default: return nil
            }
        }
        return nil
    }

    private static let ocrHistory = #"""
    [{"id":"1790000000000","status":"completed","step":5,"progress":100,"fileName":"Bakshi_Order.pdf",
      "targetLang":"Hindi","pageSetup":{"size":"A4"},"logs":[],"userId":"1","engine":"layout",
      "pages":12,"digitalPages":9,"scannedPages":3,
      "warnings":["Page 4 could not be read as text and was kept as an image.",
                  "2 passages could not be translated and were kept in the original."],
      "markdownFile":null,"outputFile":"1790000000000_Bakshi_Order_Hindi.docx"}]
    """#

    /// 50 GiB allowance (53687091200 bytes), 2.4 GiB used.
    private static let entitlements = #"""
    {"success":true,"signedIn":true,"feeTier":"essential","planKey":"essential","planLabel":"Essential",
     "tier":"premium","expired":false,"cycle":"monthly",
     "limits":{"label":"Junior Associate","matters":-1,"storageGb":50,"documents":-1,"scannedPages":25000,
               "chatQueries":3000,"deepThinkingQueries":300,"support":"email"},
     "usage":{"period":"2026-10","resetsAt":"2026-10-31T18:30:00.000Z","chatQueries":812,"deepThinkingQueries":4,
              "scannedPages":120,"documents":44,"matters":7,"storageUsedBytes":2576980378,
              "storageAllowanceBytes":53687091200},
     "metered":true,"upgradable":true,"features":{"filingReady":true,"cloudSync":true},
     "storageBytes":53687091200,"support":"Email support",
     "overageRates":{"scannedPagePaise":50,"storageGbMonthPaise":1000},
     "coreFeatures":[{"key":"chat","label":"AI Chat with page citations"},
                     {"key":"calendar","label":"Calendar"},
                     {"key":"icloud","label":"iCloud Sync","comingSoon":true}],
     "roadmap":[{"key":"ocr-translate","label":"OCR & Translate","status":"in-development","detail":"d"},
                {"key":"list-of-dates","label":"List of Dates","status":"available","detail":"d"},
                {"key":"master-brief","label":"Master Brief","status":"in-development","detail":"d"},
                {"key":"devils-advocate","label":"Devil's Advocate","status":"available","detail":"d"}]}
    """#

    private static func billingMe() -> String {
        let ends = ISO8601DateFormatter().string(from: Date().addingTimeInterval(4.5 * 86_400))
        return #"{"success":true,"plan":{"planSource":"purchase","expiresAt":"\#(ends)","expired":false,"displayLabel":"Junior Associate","feeTier":"essential"}}"#
    }
}
#endif
