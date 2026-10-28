#if DEBUG
import Foundation

/// The UI tests' canned answers for a High Court on its own portal: the Delhi High Court's
/// `/court/hc/config?courtId=hc-delhi` and `/court/hc/dedicated/search`. Every other court is
/// answered by `UITestSupport` as before.
enum CasesStubs {

    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        if UITestSupport.isEmpty { return nil }
        let method = request.httpMethod ?? "GET"
        switch (method, path) {
        case ("GET", "/court/hc/config"):
            let courtID = UITestSupport.Fixtures.query(request, "courtId") ?? ""
            return courtID == "hc-delhi" ? .json(delhiConfig) : nil
        case ("POST", "/court/hc/dedicated/search"):
            return .json(delhiResult)
        default:
            return nil
        }
    }

    /// The Delhi High Court on its own portal: two case types, no bench.
    private static let delhiConfig = #"""
        {"success":true,"kind":"dedicated","contract":{"needsBench":false,"needsCaptcha":false,"caseTypeSource":"live"},"caseTypes":[{"value":"W.P.(C)","label":"W.P.(C)"},{"value":"LPA","label":"LPA"}],"benches":[]}
        """#

    private static let delhiResult = #"""
        {"success":true,"results":[{"courtType":"hc","courtCode":"hc-delhi","courtName":"High Court — Delhi","caseType":"W.P.(C)","caseNumber":"4410","caseYear":"2025","cnr":"DLHC010044102025","registrationNo":"W.P.(C) 4410/2025","title":"Mehta Traders vs. Union of India","parties":"Mehta Traders vs. Union of India","status":"Pending","preview":false,"source":"delhihighcourt"}]}
        """#
}
#endif
