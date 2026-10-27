#if DEBUG
import Foundation

/// The UI tests' canned answers for the court lookup (package 06-C): Fetch Orders'
/// `POST /court/lookup`, and the Delhi High Court's own portal — `/court/hc/config?courtId=hc-delhi`
/// and `/court/hc/dedicated/search`. Everything else is answered by `UITestSupport` as before; the
/// matter writes Add to Matters makes are `MattersStubs`'.
///
/// `-UITestLookupNotFound`: the court has nothing under the number (404 `NOT_FOUND`).
/// `-UITestEmpty` answers nothing here, so a lookup there reads as the server's plain failure.
enum CasesStubs {

    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        if UITestSupport.isEmpty { return nil }
        let method = request.httpMethod ?? "GET"
        switch (method, path) {
        case ("POST", "/court/lookup"):
            if ProcessInfo.processInfo.arguments.contains("-UITestLookupNotFound") {
                return .json(notFound, status: 404)
            }
            return .json(lookupRecord())
        case ("GET", "/court/hc/config"):
            let courtID = UITestSupport.Fixtures.query(request, "courtId") ?? ""
            return courtID == "hc-delhi" ? .json(delhiConfig) : nil
        case ("POST", "/court/hc/dedicated/search"):
            return .json(delhiResult)
        default:
            return nil
        }
    }

    /// A day relative to today, in India, as the lookup writes one.
    private static func day(_ offset: Int) -> String {
        WireDate.dayKey(Date().addingTimeInterval(TimeInterval(offset) * 86_400))
    }

    private static let notFound = #"""
        {"success":false,"code":"NOT_FOUND","error":"The court returned no details for this case. Check the case number and year, or try again later."}
        """#

    /// Two orders (one with the court's PDF, one with a consumer forum's marker that has no copy
    /// online), three hearings (one to come), two parties a side.
    private static func lookupRecord() -> String {
        let next = day(9), last = day(-20), first = day(-200), order = day(-20), older = day(-400)
        return """
            {"success":true,"cached":false,"record":{\
            "case":{"title":"Ramesh Kumar Sharma, Sunita Sharma vs. Union of India, State of Delhi",\
            "courtType":"sc","courtName":"Supreme Court of India","caseType":"SLP(C)","caseNumber":"1234",\
            "caseYear":"2025","cnr":"SCIN010012342025","diaryNumber":null,"status":"Pending",\
            "stage":"ADMISSION HEARING","bench":"HON'BLE THE CHIEF JUSTICE","filingDate":"\(first)",\
            "category":null,"nextHearing":"\(next)"},\
            "parties":{"petitioners":["RAMESH KUMAR SHARMA","SUNITA SHARMA"],\
            "respondents":["UNION OF INDIA","STATE OF DELHI"],\
            "petitionerAdvocates":["A. K. MEHTA"],"respondentAdvocates":["SOLICITOR GENERAL"]},\
            "hearings":[\
            {"date":"\(next)","purpose":"FOR ADMISSION","bench":null,"stage":null,"remarks":null,"courtNo":"4","itemNo":"12","time":null,"ia":null,"listType":null},\
            {"date":"\(last)","purpose":"MENTIONING","bench":null,"stage":null,"remarks":null,"courtNo":"4","itemNo":"30","time":null,"ia":null,"listType":null},\
            {"date":"\(first)","purpose":"FRESH MATTER","bench":null,"stage":null,"remarks":null,"courtNo":"2","itemNo":null,"time":null,"ia":null,"listType":null}],\
            "orders":[\
            {"date":"\(order)","title":"O","url":"https://example.org/orders/1234-2025.pdf"},\
            {"date":"\(older)","title":"Record of proceedings","url":"ejagriti-order:1234"}],\
            "applications":[{"number":"IA 1/2025","particular":"EXEMPTION FROM FILING","filedOn":"\(first)","status":"Pending","remark":null}],\
            "connected":[],"courtFees":[{"head":"Court fee","amount":1250}],\
            "fetchedAt":"2026-10-21T10:00:00.000Z"}}
            """
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
