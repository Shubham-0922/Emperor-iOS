#if DEBUG
import Foundation

/// The UI tests' canned answers for matters (the web's projects): the reads — `GET /projects`,
/// `GET /project`, `GET /project-banner` — and, through `Store`, every write on a matter's record,
/// kept for the life of the launch so a test can create, edit and delete and then read the result.
/// Owned by package 03-MA, then 04-MB and 05-MC. `-UITestEmpty` answers with no matters at all.
/// A matter's files, its drafts, attach and the chronology read are answered here too (05-MC).
///
/// Four matters: `prj-writ` (active, high priority, linked to a case that is **not** on the
/// docket, with a full workspace), `prj-arb` (an uploaded banner, nothing dated), `prj-old`
/// (archived) and `prj-gone` (listed, but its workspace answers 404). No matter links a case the
/// docket stub lists, so every docket test sees the docket it always saw; no forum name begins
/// with a docket heading. Writes: a new matter is `prj-new-N`; `DELETE /project` wants the exact
/// name; linking `case-sc` is refused as another team's case; a matter made from
/// `case-matter-only` is `prj-writ`, which already exists; the court refresh answers once, then
/// says to wait four minutes.
enum MattersStubs {

    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        let method = request.httpMethod ?? "GET"
        if method == "GET", path == "/project-banner" {
            guard let png = Data(base64Encoded: onePixelPNG) else { return nil }
            return .bytes(png, type: "image/png")
        }
        // `-UITestFreshChats`: every conversation opens empty, as a new one does on the server —
        // for the tests that start a matter's conversation. Without it `/messages` answers as it
        // always has.
        if method == "GET", path == "/messages", ProcessInfo.processInfo.arguments.contains("-UITestFreshChats") {
            return .json(#"{"success":true,"messages":[]}"#)
        }
        return store.reply(method: method, path: path, request: request)
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

// MARK: - The matters, as the writes leave them

extension MattersStubs {

    fileprivate static let store = Store()

    /// One launch's matters: seeded from the canned rows above, changed by every write, read back
    /// by the next `GET`. Locked, because `URLProtocol` answers on queues of its own.
    final class Store: @unchecked Sendable {
        private typealias Row = [String: Any]

        private let lock = NSLock()
        private var order: [String] = []
        private var rows: [String: Row] = [:]
        /// Each matter's lists — `updates`, `tasks`, `ledger`, `people`, `chats`, `courtHistory` —
        /// and its `linkedCase`. A listed matter without one answers 404 (`prj-gone`).
        private var children: [String: Row] = [:]
        private var made = 0
        private var refreshes: [String: Int] = [:]
        /// Folders made with New folder, by matter, relative to the matter.
        private var madeFolders: [String: [String]] = [:]

        init() {
            guard !UITestSupport.isEmpty else { return }
            let list = Self.object(MattersStubs.listJSON())?["projects"] as? [Row] ?? []
            for row in list {
                guard let id = row["id"] as? String else { continue }
                order.append(id)
                rows[id] = row
                if let json = MattersStubs.detailJSON(id), var detail = Self.object(json) {
                    detail.removeValue(forKey: "success")
                    detail.removeValue(forKey: "totals")
                    detail.removeValue(forKey: "project")
                    children[id] = detail
                }
            }
        }

        // MARK: Dispatch

        func reply(method: String, path: String, request: URLRequest) -> StubReply? {
            lock.lock()
            defer { lock.unlock() }
            let body = method == "POST" ? (UITestSupport.Fixtures.jsonBody(of: request) ?? [:]) : [:]
            func q(_ name: String) -> String { UITestSupport.Fixtures.query(request, name) ?? "" }
            switch (method, path) {
            case ("GET", "/projects"): return list()
            case ("GET", "/project"): return detail(q("id"))
            case ("POST", "/project"): return save(body)
            case ("POST", "/project-patch"): return patch(body)
            case ("DELETE", "/project"): return deleteProject(q("id"), confirm: q("confirm"))
            case ("POST", "/project-banner"): return banner(body["projectId"] as? String ?? "", on: true)
            case ("DELETE", "/project-banner"): return banner(q("id"), on: false)
            case ("POST", "/project-update"): return saveChild("updates", body, prefix: "pup", key: "update")
            case ("DELETE", "/project-update"): return deleteChild("updates", q("id"), missing: "Chronology entry not found")
            case ("POST", "/project-task"): return saveChild("tasks", body, prefix: "pt", key: "task")
            case ("DELETE", "/project-task"): return deleteChild("tasks", q("id"), missing: "Task not found")
            case ("POST", "/project-ledger"): return saveChild("ledger", body, prefix: "pl", key: "entry")
            case ("DELETE", "/project-ledger"): return deleteChild("ledger", q("id"), missing: "Ledger entry not found")
            case ("POST", "/project-person"): return saveChild("people", body, prefix: "pp", key: "person")
            case ("DELETE", "/project-person"): return deleteChild("people", q("id"), missing: "Person not found")
            case ("POST", "/project-link-case"): return link(body)
            case ("POST", "/project-from-case"): return fromCase(body)
            case ("POST", "/project-case-refresh"): return refresh(body["projectId"] as? String ?? "")
            case ("GET", "/project-files"): return files(q("projectId"))
            case ("POST", "/project-folder"): return folder(body)
            case ("POST", "/project-attach"): return attach(body)
            case ("POST", "/project-chronology-extract"): return extract(body["projectId"] as? String ?? "")
            // A matter's drafts only; the Library's own list is answered as it always was.
            case ("GET", "/documents"), ("GET", "/tables"):
                return q("projectId").isEmpty ? nil : drafts(q("projectId"), tables: path == "/tables")
            case ("POST", "/save-case"): return Self.reply(["success": true, "id": "case-new"])
            default: return nil
            }
        }

        // MARK: Reads

        private func list() -> StubReply {
            let out = order.compactMap { id -> Row? in
                guard var row = rows[id] else { return nil }
                if let kids = children[id] {
                    let tasks = kids["tasks"] as? [Row] ?? []
                    row["open_tasks"] = tasks.filter { ($0["status"] as? String) != "done" }.count
                    row["update_count"] = (kids["updates"] as? [Row] ?? []).count
                    let t = totals(kids["ledger"] as? [Row] ?? [])
                    row["billed"] = t["billed"]
                    row["received"] = t["received"]
                }
                return row
            }
            return Self.reply(["success": true, "projects": out])
        }

        private func detail(_ id: String) -> StubReply {
            guard let row = rows[id], var kids = children[id] else { return Self.missing("Project not found") }
            kids["success"] = true
            kids["project"] = row
            kids["totals"] = totals(kids["ledger"] as? [Row] ?? [])
            return Self.reply(kids)
        }

        private func totals(_ ledger: [Row]) -> Row {
            var sums = ["fee": 0, "payment": 0, "expense": 0]
            for entry in ledger {
                let kind = entry["kind"] as? String ?? ""
                sums[kind, default: 0] += (entry["amount_paise"] as? Int) ?? 0
            }
            let fee = sums["fee"] ?? 0, paid = sums["payment"] ?? 0
            return ["billed": Double(fee) / 100, "received": Double(paid) / 100,
                    "outstanding": Double(fee - paid) / 100, "expenses": Double(sums["expense"] ?? 0) / 100]
        }

        // MARK: The matter

        /// Body keys to columns, as the server's `PROJECT_FIELDS` maps them.
        private static let columns: [String: String] = [
            "name": "name", "client": "client", "description": "description", "forumType": "forum_type",
            "forumName": "forum_name", "caseNumber": "case_number", "caseYear": "case_year", "caseType": "case_type",
            "cnr": "cnr", "stage": "stage", "status": "status", "priority": "priority",
            "nextHearingDate": "next_hearing_date", "filingDate": "filing_date", "color": "color", "banner": "banner",
            "practiceArea": "practice_area", "ourSide": "our_side", "oppositeParty": "opposite_party",
            "courtStatus": "court_status",
        ]

        private static let defaults: [String: String] = ["status": "active", "priority": "normal", "forum_type": "other"]

        private func apply(_ fields: [String: Any], to row: inout Row) {
            for (key, value) in fields {
                guard let column = Self.columns[key] else { continue }
                let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.isEmpty {
                    row[column] = Self.defaults[column] ?? NSNull()
                } else {
                    row[column] = text
                }
            }
            if let status = row["status"] as? String {
                row["archived_at"] = status == "archived" ? Self.nowISO() : NSNull()
            }
            row["updated_at"] = Self.nowISO()
        }

        private func save(_ body: [String: Any]) -> StubReply {
            if let id = body["id"] as? String {
                guard var row = rows[id] else { return Self.missing("Project not found") }
                apply(body, to: &row)
                rows[id] = row
                return Self.reply(["success": true, "project": row])
            }
            let name = (body["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return Self.refused("Project name is required") }
            made += 1
            let id = "prj-new-\(made)"
            var row: Row = ["id": id, "user_id": "1", "created_at": Self.nowISO(), "linked_case_id": NSNull(),
                            "file_count": 0, "chat_count": 0, "status": "active", "priority": "normal",
                            "forum_type": "other"]
            apply(body, to: &row)
            rows[id] = row
            order.insert(id, at: 0)
            children[id] = ["updates": [Row](), "chats": [Row](), "courtHistory": [Row](), "linkedCase": NSNull(),
                            "tasks": [Row](), "ledger": [Row](), "people": [Row]()]
            return Self.reply(["success": true, "project": row])
        }

        private func patch(_ body: [String: Any]) -> StubReply {
            let id = body["projectId"] as? String ?? ""
            guard var row = rows[id] else { return Self.missing("Project not found") }
            let fields = body["fields"] as? [String: Any] ?? [:]
            if let unknown = fields.keys.sorted().first(where: { Self.columns[$0] == nil }) {
                return Self.refused("Unknown project field: \(unknown)")
            }
            apply(fields, to: &row)
            rows[id] = row
            return Self.reply(["success": true, "project": row])
        }

        private func deleteProject(_ id: String, confirm: String) -> StubReply {
            guard let row = rows[id] else { return Self.missing("Project not found") }
            guard !confirm.isEmpty, confirm == (row["name"] as? String ?? "") else {
                return Self.refused("To delete this project, send confirm= with its exact name")
            }
            let kids = children[id] ?? [:]
            rows[id] = nil
            children[id] = nil
            order.removeAll { $0 == id }
            func count(_ key: String) -> Int { (kids[key] as? [Row] ?? []).count }
            return Self.reply(["success": true, "deleted": [
                "chats": count("chats"), "drafts": 0, "tasks": count("tasks"), "ledger": count("ledger"),
                "people": count("people"), "updates": count("updates"), "fileLinks": 0, "chatLinks": 0,
                "storage": true, "index": NSNull()]])
        }

        private func banner(_ id: String, on: Bool) -> StubReply {
            guard var row = rows[id] else { return Self.missing("Project not found") }
            if on {
                row["banner"] = "image"
            } else if (row["banner"] as? String) == "image" {
                row["banner"] = NSNull()
            }
            row["updated_at"] = Self.nowISO()
            rows[id] = row
            return Self.reply(on ? ["success": true, "banner": "image"] : ["success": true])
        }

        // MARK: Chronology, tasks, ledger, people

        private func saveChild(_ list: String, _ body: [String: Any], prefix: String, key: String) -> StubReply {
            let projectID = body["projectId"] as? String ?? ""
            guard var kids = children[projectID] else { return Self.missing("Project not found") }
            var items = kids[list] as? [Row] ?? []
            let existing = (body["id"] as? String).flatMap { id in items.firstIndex { ($0["id"] as? String) == id } }
            if body["id"] != nil, existing == nil {
                return Self.missing(list == "updates" ? "Chronology entry not found" : "Not found")
            }
            var row: Row = existing.map { items[$0] } ?? [
                "id": "\(prefix)-\(made + items.count + 1)-\(Int(Date().timeIntervalSince1970 * 1000) % 100_000)",
                "project_id": projectID, "user_id": "1", "created_at": Self.nowSQL(),
            ]
            if list == "updates", key == "update", body["title"] as? String ?? "" == "", body["body"] as? String ?? "" == "" {
                return Self.refused("A chronology entry needs a title or a note")
            }
            for (field, value) in body where field != "projectId" && field != "userId" && field != "id" {
                let column = Self.childColumns[field] ?? field
                if field == "amount", let rupees = value as? Double {
                    row["amount_paise"] = Int((rupees * 100).rounded())
                    row["amount"] = rupees
                    continue
                }
                if let text = value as? String {
                    row[column] = text.isEmpty ? NSNull() : text
                } else {
                    row[column] = value
                }
            }
            if list == "tasks" {
                let done = (row["status"] as? String) == "done"
                row["completed_at"] = done ? Self.nowISO() : NSNull()
                row["updated_at"] = Self.nowSQL()
            }
            if list == "updates", row["event_date"] is NSNull || row["event_date"] == nil {
                row["event_date"] = MattersStubs.day(0)
            }
            if let existing {
                items[existing] = row
            } else {
                items.insert(row, at: 0)
            }
            kids[list] = items
            children[projectID] = kids
            touch(projectID)
            var answer: Row = ["success": true, key: row]
            if list == "updates" {
                answer["id"] = row["id"]
                answer["nextHearingDate"] = nextHearing(projectID, after: row)
            }
            return Self.reply(answer)
        }

        private static let childColumns: [String: String] = [
            "eventDate": "event_date", "sourceRef": "source_ref", "dueDate": "due_date", "entryDate": "entry_date",
            "receiptFile": "receipt_file",
        ]

        /// A hearing dated today or later becomes the next date when it is the soonest.
        private func nextHearing(_ projectID: String, after update: Row) -> Any {
            guard var row = rows[projectID] else { return NSNull() }
            let current = row["next_hearing_date"] as? String
            if (update["kind"] as? String) == "hearing", let day = update["event_date"] as? String, day.count == 10,
               day >= MattersStubs.day(0), current == nil || day < current! {
                row["next_hearing_date"] = day
                rows[projectID] = row
            }
            return row["next_hearing_date"] ?? NSNull()
        }

        private func deleteChild(_ list: String, _ id: String, missing: String) -> StubReply {
            for (projectID, var kids) in children {
                var items = kids[list] as? [Row] ?? []
                guard let index = items.firstIndex(where: { ($0["id"] as? String) == id }) else { continue }
                items.remove(at: index)
                kids[list] = items
                children[projectID] = kids
                touch(projectID)
                return Self.reply(["success": true])
            }
            return Self.missing(missing)
        }

        private func touch(_ projectID: String) {
            rows[projectID]?["updated_at"] = Self.nowISO()
        }

        // MARK: The court case

        private func link(_ body: [String: Any]) -> StubReply {
            let id = body["projectId"] as? String ?? ""
            guard var row = rows[id], var kids = children[id] else { return Self.missing("Project not found") }
            guard body.keys.contains("caseId") else { return Self.refused("caseId is required (null unlinks the case)") }
            if let caseID = body["caseId"] as? String, !caseID.isEmpty {
                if caseID == "case-sc" {
                    return .json(#"{"success":false,"error":"You are not a member of the team that tracks that case"}"#,
                                 status: 403)
                }
                row["linked_case_id"] = caseID
                kids["linkedCase"] = ["id": caseID, "title": "Linked case", "court_name": "Delhi High Court",
                                      "court_type": "hc", "status": "Pending", "last_synced_at": Self.nowISO()]
            } else {
                row["linked_case_id"] = NSNull()
                kids["linkedCase"] = NSNull()
                kids["courtHistory"] = [Row]()
            }
            rows[id] = row
            children[id] = kids
            return Self.reply(["success": true, "project": row])
        }

        private func fromCase(_ body: [String: Any]) -> StubReply {
            let caseID = body["caseId"] as? String ?? ""
            guard !caseID.isEmpty else { return Self.refused("caseId is required") }
            if let existing = order.first(where: { (rows[$0]?["linked_case_id"] as? String) == caseID }),
               let row = rows[existing] {
                return Self.reply(["success": true, "project": row, "existed": true])
            }
            var fields = body
            if (fields["name"] as? String ?? "").isEmpty { fields["name"] = "Matter from the court" }
            _ = save(fields)
            let id = "prj-new-\(made)"
            rows[id]?["linked_case_id"] = caseID
            return Self.reply(["success": true, "project": rows[id] ?? [:], "existed": false])
        }

        private func refresh(_ projectID: String) -> StubReply {
            guard rows[projectID] != nil else { return Self.missing("Project not found") }
            refreshes[projectID, default: 0] += 1
            if refreshes[projectID] == 1 {
                return Self.reply(["success": true, "lastSyncedAt": Self.nowISO(),
                                   "counts": ["hearings": 1, "orders": 1]])
            }
            return .json(
                #"{"success":false,"error":"This case was refreshed a moment ago — try again in 4 min","retryAfter":240}"#,
                status: 429)
        }

        // MARK: Files, attach, drafts, chronology (05-MC)

        /// `prj-writ` holds a ready petition and an affidavit still being read in Pleadings, and a
        /// court-fee receipt in Receipts; every other matter is empty until a folder is made.
        private func files(_ projectID: String) -> StubReply {
            guard rows[projectID] != nil else { return Self.missing("Project not found") }
            let root = "_projects/\(projectID)"
            func file(_ sub: String, _ name: String, _ status: String, _ modified: String) -> Row {
                ["type": "file", "name": name, "path": "\(root)/\(sub)/\(name)", "size": 4096,
                 "modified": modified, "status": status, "favorite": false]
            }
            func folder(_ sub: String, _ files: [Row]) -> Row {
                ["type": "folder", "name": sub, "path": "\(root)/\(sub)", "created": "2026-08-01T10:00:00.000Z", "files": files]
            }
            var folders: [Row] = []
            if projectID == "prj-writ" {
                folders = [
                    folder("Pleadings", [
                        file("Pleadings", "Writ_Petition.pdf", "ready", "2026-08-11T10:00:00.000Z"),
                        file("Pleadings", "Counter_Affidavit.pdf", "Reading page 3 of 18", "2026-10-20T10:00:00.000Z"),
                    ]),
                    folder("Receipts", [file("Receipts", "Court_Fee_Receipt.pdf", "ready", "2026-08-11T11:00:00.000Z")]),
                ]
            }
            for sub in madeFolders[projectID] ?? [] { folders.append(folder(sub, [])) }
            return Self.reply(["success": true, "root": root, "folders": folders, "files": [Row]()])
        }

        private func folder(_ body: [String: Any]) -> StubReply {
            let projectID = body["projectId"] as? String ?? ""
            guard rows[projectID] != nil else { return Self.missing("Project not found") }
            let name = (body["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return Self.refused("Folder name is required") }
            let existed = madeFolders[projectID, default: []].contains(name)
            if !existed { madeFolders[projectID, default: []].append(name) }
            return Self.reply(["success": true, "folder": "_projects/\(projectID)/\(name)", "existed": existed])
        }

        /// The first document is copied; every other one is still being read in My Files.
        private func attach(_ body: [String: Any]) -> StubReply {
            let projectID = body["projectId"] as? String ?? ""
            guard rows[projectID] != nil else { return Self.missing("Project not found") }
            let sub = (body["subfolder"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Pleadings"
            let folder = "_projects/\(projectID)/\(sub)"
            let wanted = body["files"] as? [[String: Any]] ?? []
            var out: [Row] = []
            for (index, entry) in wanted.enumerated() {
                let name = entry["fileName"] as? String ?? ""
                let source: Row = ["folderName": entry["folderName"] as? String ?? "", "fileName": name]
                var row: Row = ["name": name, "folder": folder, "status": "indexing", "source": source]
                if index > 0 {
                    row["status"] = "skipped"
                    row["processing"] = true
                    row["reason"] = "Still being read in My Files. Attach it once it shows as ready there."
                }
                out.append(row)
            }
            touch(projectID)
            return Self.reply(["success": true, "folder": folder, "files": out])
        }

        /// One draft made in the matter's conversation, as `/documents?projectId=` lists it.
        private func drafts(_ projectID: String, tables: Bool) -> StubReply {
            guard rows[projectID] != nil else { return Self.missing("Project not found") }
            var list: [Row] = []
            if projectID == "prj-writ", !tables {
                list = [["id": "doc-writ-1", "chat_id": "chat-writ", "user_id": "1", "title": "Rejoinder to the counter affidavit",
                         "type": "doc", "created_at": "2026-10-01T08:30:00.000Z", "chat_title": "Draft the rejoinder",
                         "project_id": projectID]]
            }
            return Self.reply(["success": true, "documents": list, "tables": list])
        }

        /// Three dated events; the first is the petition already on the record, so it starts unticked.
        private func extract(_ projectID: String) -> StubReply {
            guard rows[projectID] != nil else { return Self.missing("Project not found") }
            let events: [Row] = [
                ["date": MattersStubs.day(-30), "title": "Writ petition filed", "details": "Filed with 12 annexures.",
                 "kind": "filing", "sourceRef": "Writ_Petition.pdf, p. 1"],
                ["date": MattersStubs.day(-60), "title": "Tender cancelled by the Department", "details": "Order No. 118 of the Executive Engineer.",
                 "kind": "event", "sourceRef": "Writ_Petition.pdf, p. 4"],
                ["date": MattersStubs.day(-90), "title": "Tender awarded to the petitioner", "details": "",
                 "kind": "award", "sourceRef": "Writ_Petition.pdf, p. 3"],
            ]
            return Self.reply(["success": true, "events": events, "files": 2, "skipped": ["Counter_Affidavit.pdf"],
                               "chunks": ["total": 2, "failed": 0, "notRun": 0], "partial": false])
        }

        // MARK: Helpers

        private static func object(_ json: String) -> Row? {
            (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? Row
        }

        private static func reply(_ object: Row) -> StubReply {
            let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
            return StubReply(status: 200, data: data, contentType: "application/json")
        }

        private static func refused(_ message: String) -> StubReply {
            .json(#"{"success":false,"error":"\#(message)"}"#, status: 400)
        }

        private static func missing(_ message: String) -> StubReply {
            .json(#"{"success":false,"error":"\#(message)"}"#, status: 404)
        }

        private static func nowISO() -> String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.string(from: Date())
        }

        private static func nowSQL() -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f.string(from: Date())
        }
    }
}
#endif
