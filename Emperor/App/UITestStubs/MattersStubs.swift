#if DEBUG
import Foundation

/// The UI tests' canned answers for matters (the web's projects): `GET /projects`, `GET /project`
/// and `GET /project-banner`. Owned by package 03-MA, then 04-MB and 05-MC. `-UITestEmpty`
/// answers with no matters at all.
///
/// Four matters: `prj-writ` (active, high priority, linked to a case that is **not** on the
/// docket, with a full workspace), `prj-arb` (an uploaded banner, nothing dated), `prj-old`
/// (archived) and `prj-gone` (listed, but its workspace answers 404). No matter links a case the
/// docket stub lists, so every docket test sees the docket it always saw; no forum name begins
/// with a docket heading.
enum MattersStubs {

    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        guard (request.httpMethod ?? "GET") == "GET" else { return nil }
        switch path {
        case "/projects":
            return .json(UITestSupport.isEmpty ? #"{"success":true,"projects":[]}"# : listJSON())
        case "/project":
            let id = UITestSupport.Fixtures.query(request, "id") ?? ""
            guard !UITestSupport.isEmpty, let body = detailJSON(id) else {
                return .json(#"{"success":false,"error":"Project not found"}"#, status: 404)
            }
            return .json(body)
        case "/project-banner":
            guard let png = Data(base64Encoded: onePixelPNG) else { return nil }
            return .bytes(png, type: "image/png")
        default:
            return nil
        }
    }

    /// A day relative to today, in India, as the server writes a hearing date.
    private static func day(_ offset: Int) -> String {
        WireDate.dayKey(Date().addingTimeInterval(TimeInterval(offset) * 86_400))
    }

    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

    private static var writRow: String {
        """
        {"id":"prj-writ","user_id":"1","name":"Bhalla v. State of Haryana","client":"Ankit Bhalla",\
        "description":"Challenge to the cancellation of the road tender.","forum_type":"high_court",\
        "forum_name":"Punjab and Haryana High Court","case_number":"4412","case_year":"2025",\
        "cnr":"PHHC010044122025","stage":"Admission","status":"active","priority":"high",\
        "next_hearing_date":"\(day(2))","filing_date":"2025-03-01","linked_case_id":"case-matter-only",\
        "created_at":"2025-03-01T10:00:00.000Z","updated_at":"2026-10-20T10:00:00.000Z","archived_at":null,\
        "case_type":"CWP","color":"teal","banner":"teal","practice_area":"writ","our_side":"petitioner",\
        "court_status":null,"opposite_party":"State of Haryana"
        """
    }

    private static func listJSON() -> String {
        let writ = writRow + #","update_count":2,"last_activity":"\#(day(-10))","file_count":3,"chat_count":1,"open_tasks":2,"next_task_due":"\#(day(-1))","billed":50000,"received":20000}"#
        let arb = """
            {"id":"prj-arb","user_id":"1","name":"Suvarnapatnam Infra v. Ashwatth Builders","client":"Suvarnapatnam Infra",\
            "description":null,"forum_type":"arbitration","forum_name":"Delhi International Arbitration Centre",\
            "case_number":null,"case_year":null,"cnr":null,"stage":null,"status":"active","priority":"normal",\
            "next_hearing_date":null,"filing_date":null,"linked_case_id":null,\
            "created_at":"2026-01-10T10:00:00.000Z","updated_at":"2026-09-01T10:00:00.000Z","archived_at":null,\
            "case_type":null,"color":"amber","banner":"image","practice_area":"arbitration","our_side":"claimant",\
            "court_status":"not_filed","opposite_party":"Ashwatth Builders","update_count":0,"last_activity":null,\
            "file_count":0,"chat_count":0,"open_tasks":0,"next_task_due":null,"billed":0,"received":0}
            """
        let old = """
            {"id":"prj-old","user_id":"1","name":"Mehra v. Mehra","client":"Sunita Mehra","description":null,\
            "forum_type":"district","forum_name":"Family Court, Saket","case_number":"112","case_year":"2019",\
            "cnr":null,"stage":"Decree","status":"archived","priority":"low","next_hearing_date":null,\
            "filing_date":null,"linked_case_id":null,"created_at":"2019-05-01T10:00:00.000Z",\
            "updated_at":"2024-01-01T10:00:00.000Z","archived_at":"2024-01-01T10:00:00.000Z","case_type":"HMA",\
            "color":null,"banner":"wine","practice_area":"family","our_side":"petitioner","court_status":null,\
            "opposite_party":"Rajiv Mehra","update_count":0,"last_activity":null,"file_count":1,"chat_count":0,\
            "open_tasks":0,"next_task_due":null,"billed":0,"received":0}
            """
        let gone = """
            {"id":"prj-gone","user_id":"1","name":"Rathore Exports v. Union of India","client":"Rathore Exports",\
            "description":null,"forum_type":"other","forum_name":null,"case_number":null,"case_year":null,\
            "cnr":null,"stage":null,"status":"active","priority":"normal","next_hearing_date":null,\
            "filing_date":null,"linked_case_id":null,"created_at":"2026-02-01T10:00:00.000Z",\
            "updated_at":"2026-02-01T10:00:00.000Z","archived_at":null,"case_type":null,"color":null,\
            "banner":"slate","practice_area":"tax","our_side":null,"court_status":null,"opposite_party":null,\
            "update_count":0,"last_activity":null,"file_count":0,"chat_count":0,"open_tasks":0,\
            "next_task_due":null,"billed":0,"received":0}
            """
        return #"{"success":true,"projects":[\#(writ),\#(arb),\#(old),\#(gone)]}"#
    }

    private static func detailJSON(_ id: String) -> String? {
        switch id {
        case "prj-writ": return writDetail()
        case "prj-arb":
            return """
                {"success":true,"project":{"id":"prj-arb","name":"Suvarnapatnam Infra v. Ashwatth Builders",\
                "client":"Suvarnapatnam Infra","forum_type":"arbitration",\
                "forum_name":"Delhi International Arbitration Centre","status":"active","priority":"normal",\
                "banner":"image","color":"amber","practice_area":"arbitration","court_status":"not_filed",\
                "opposite_party":"Ashwatth Builders","updated_at":"2026-09-01T10:00:00.000Z"},\
                "updates":[],"chats":[],"courtHistory":[],"linkedCase":null,"tasks":[],"ledger":[],"people":[],\
                "totals":{"billed":0,"received":0,"outstanding":0,"expenses":0}}
                """
        case "prj-old":
            return """
                {"success":true,"project":{"id":"prj-old","name":"Mehra v. Mehra","client":"Sunita Mehra",\
                "forum_type":"district","forum_name":"Family Court, Saket","case_number":"112","case_year":"2019",\
                "case_type":"HMA","status":"archived","priority":"low","banner":"wine","practice_area":"family",\
                "our_side":"petitioner","opposite_party":"Rajiv Mehra","updated_at":"2024-01-01T10:00:00.000Z"},\
                "updates":[],"chats":[],"courtHistory":[],"linkedCase":null,"tasks":[],"ledger":[],"people":[]}
                """
        default:
            return nil
        }
    }

    private static func writDetail() -> String {
        """
        {"success":true,"project":\(writRow)},\
        "updates":[\
        {"id":"upd-1","project_id":"prj-writ","user_id":"1","kind":"note","title":"Brief received from the client",\
        "body":"Tender file, two letters and the cancellation order.","event_date":"\(day(-40))","status":null,\
        "payload":null,"created_at":"2026-08-01 10:00:00","source":"manual","source_ref":null},\
        {"id":"upd-2","project_id":"prj-writ","user_id":"1","kind":"filing","title":"Writ petition filed",\
        "body":null,"event_date":"\(day(-30))","status":null,"payload":{"pages":42},\
        "created_at":"2026-08-11 10:00:00","source":"ai","source_ref":"Petition.pdf"}],\
        "chats":[{"id":"chat-writ","title":"Draft the rejoinder","updated_at":"2026-10-01 08:00:00","linked_at":null}],\
        "courtHistory":[\
        {"id":"ch-hearing","section":"hearings","title":"Arguments","subtitle":null,"item_date":"\(day(2))",\
        "status":null,"source":"ecourts","data":{"courtNo":"12","itemNo":7,"coram":"Hon'ble Mr. Justice A. Sharma",\
        "listType":"Daily","nested":{"seen":[1,2]}}},\
        {"id":"ch-order","section":"orders","title":"Order","subtitle":null,"item_date":"\(day(-20))",\
        "status":null,"source":"ecourts","data":{"type":"Order","summary":"Notice issued; reply in four weeks."}}],\
        "linkedCase":{"id":"case-matter-only","title":"ANKIT BHALLA VS STATE OF HARYANA",\
        "court_name":"Punjab and Haryana High Court","court_type":"hc","case_type":"CWP","case_number":"4412",\
        "case_year":"2025","cnr":"PHHC010044122025","next_hearing_date":"\(day(2))","stage":"Admission",\
        "status":"Pending","last_synced_at":"2026-10-01T04:00:00.000Z"},\
        "tasks":[\
        {"id":"tsk-overdue","title":"File the rejoinder","notes":null,"due_date":"\(day(-1))","kind":"filing",\
        "priority":"high","status":"open","completed_at":null,"created_at":"2026-09-01 10:00:00","updated_at":"2026-09-01 10:00:00"},\
        {"id":"tsk-limitation","title":"Appeal against the single judge's order","notes":"Certified copy applied for.",\
        "due_date":"\(day(3))","kind":"limitation","priority":"normal","status":"open","completed_at":null,\
        "created_at":"2026-09-02 10:00:00","updated_at":"2026-09-02 10:00:00"},\
        {"id":"tsk-later","title":"Inspect the tender file","notes":null,"due_date":"\(day(30))","kind":"task",\
        "priority":"low","status":"open","completed_at":null,"created_at":"2026-09-03 10:00:00","updated_at":"2026-09-03 10:00:00"},\
        {"id":"tsk-done","title":"Vakalatnama signed","notes":null,"due_date":"\(day(-35))","kind":"task",\
        "priority":"normal","status":"done","completed_at":"2026-08-20T05:00:00.000Z","created_at":"2026-08-01 10:00:00",\
        "updated_at":"2026-08-20 05:00:00"}],\
        "ledger":[\
        {"id":"led-fee","kind":"fee","title":"Drafting and filing","amount_paise":5000000,"amount":50000,\
        "entry_date":"\(day(-30))","mode":null,"reference":null,"category":null,"receipt_file":null,"notes":null,\
        "created_at":"2026-08-11 10:00:00"},\
        {"id":"led-payment","kind":"payment","title":null,"amount_paise":2000000,"amount":20000,\
        "entry_date":"\(day(-25))","mode":"upi","reference":"UTR 4021 7781 1123","category":null,"receipt_file":null,\
        "notes":"First instalment","created_at":"2026-08-16 10:00:00"},\
        {"id":"led-court-fee","kind":"expense","title":null,"amount_paise":50000,"amount":500,\
        "entry_date":"\(day(-30))","mode":null,"reference":"GRN 88123","category":"court_fee","receipt_file":null,\
        "notes":null,"created_at":"2026-08-11 10:00:00"},\
        {"id":"led-travel","kind":"expense","title":"Chandigarh visit","amount_paise":120000,"amount":1200,\
        "entry_date":"\(day(-28))","mode":null,"reference":null,"category":"travel","receipt_file":null,\
        "notes":null,"created_at":"2026-08-13 10:00:00"}],\
        "people":[\
        {"id":"ppl-client","role":"client","name":"Ankit Bhalla","phone":"9876543210","email":"ankit@example.com",\
        "address":"12, Sector 8, Chandigarh","notes":null,"created_at":"2026-08-01 10:00:00"},\
        {"id":"ppl-other","role":"opposite_party","name":"State of Haryana","phone":null,"email":null,\
        "address":null,"notes":null,"created_at":"2026-08-01 10:00:00"},\
        {"id":"ppl-counsel","role":"opposing_counsel","name":"Adv. R. Mehta","phone":null,"email":"mehta@example.com",\
        "address":null,"notes":"Additional Advocate General","created_at":"2026-08-02 10:00:00"}],\
        "totals":{"billed":50000,"received":20000,"outstanding":30000,"expenses":1700}}
        """
    }
}
#endif
