#if DEBUG
import Foundation

/// The UI tests' canned answers for filing assembly (`/filing/*`). Owned by package 13-F1, then
/// 13-F2.
///
/// Stateful for the life of the launch, as the server is: an annexure added, renamed, reordered
/// or removed shows on the next read, and an assembled bundle joins the list. Two drafts —
/// `canvas_1` (chat `c1`) with a Board resolution as P-1 and a typed copy awaiting its check as
/// P-2, and `table_2` with none. Assembly succeeds for any forum the assembler reads, except that
/// a case type of "Fail" answers as the server does when a source file is missing: a 200 with
/// `success: false`. `-UITestEmpty` leaves no drafts.
///
/// The conversation `c1` has annexures of its own (13-F2): P-1 an original PDF, P-2 a typed copy
/// awaiting its check, and P-9 a photograph whose kind cannot be previewed. Adding one of its
/// files twice answers with the annexure it already is; assembling it needs the draft's HTML.
/// Under `-UITestFilingChat`, `/messages` answers with an exchange whose answer carries a drafted
/// writ petition and whose question carried two files, one of them already P-1.
enum FilingStubs {

    static var isChatOn: Bool { ProcessInfo.processInfo.arguments.contains("-UITestFilingChat") }

    private struct Row {
        var id: Int
        var draftID: String
        var mark: String
        var title: String
        var source: String
        var treatment: String
        var verify: String
        var pageFrom: Int?
        var pageTo: Int?

        /// A conversation's own rows are held under `chat:<id>`, as its bundles are listed.
        var json: [String: Any] {
            let chat: String? = draftID.hasPrefix("chat:") ? String(draftID.dropFirst(5)) : nil
            let draft: Any
            let chatValue: Any
            if let chat {
                draft = NSNull()
                chatValue = chat
            } else {
                draft = draftID
                chatValue = NSNull()
            }
            return [
                "id": id, "user_id": "1", "draft_id": draft, "chat_id": chatValue,
                "mark": mark, "title": title, "source_file_path": source,
                "treatment": treatment, "sort_order": 0, "verify_status": verify,
                "page_from": pageFrom.map { $0 as Any } ?? NSNull(),
                "page_to": pageTo.map { $0 as Any } ?? NSNull(),
                "created_at": 1_790_000_000_000, "updated_at": 1_790_000_000_000,
                "pasted_at": NSNull(),
            ]
        }
    }

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var rows: [Row] = []
        private var nextID = 3
        private var bundles: [[String: Any]] = []

        init() {
            guard !UITestSupport.isEmpty else { return }
            rows = [
                Row(id: 1, draftID: "canvas_1", mark: "P-1", title: "Board resolution",
                    source: "/storage/1/Bakshi/Plaint.pdf", treatment: "append", verify: "n/a"),
                Row(id: 2, draftID: "canvas_1", mark: "P-2", title: "Notice under Section 8",
                    source: "/storage/1/Bakshi/Orders/Interim_Order.pdf", treatment: "typed",
                    verify: "pending"),
                Row(id: 101, draftID: "chat:c1", mark: "P-1", title: "Board resolution",
                    source: "/storage/1/Bakshi/Plaint.pdf", treatment: "append", verify: "n/a"),
                Row(id: 102, draftID: "chat:c1", mark: "P-2", title: "Notice under Section 8",
                    source: "/storage/1/Bakshi/Notice.pdf", treatment: "typed", verify: "pending"),
                Row(id: 103, draftID: "chat:c1", mark: "P-9", title: "Site photograph",
                    source: "/storage/1/Bakshi/Site_Photo.heic", treatment: "append", verify: "n/a"),
            ]
        }

        /// One of a conversation's rows by its mark.
        func row(chat: String, mark: String) -> Row? {
            lock.withLock { rows.first { $0.draftID == "chat:\(chat)" && $0.mark == mark } }
        }

        func typedRows(chat: String) -> [Row] {
            lock.withLock { rows.filter { $0.draftID == "chat:\(chat)" && $0.treatment == "typed" } }
        }

        func list(draftID: String) -> [[String: Any]] {
            lock.withLock { rows.filter { $0.draftID == draftID }.map(\.json) }
        }

        func add(draftID: String, folder: String, fileName: String) -> [String: Any] {
            lock.withLock {
                let path = folder == "." ? fileName : "\(folder)/\(fileName)"
                // In a conversation the same file again answers with the annexure it already is.
                let source = "/storage/1/\(path)"
                if draftID.hasPrefix("chat:"),
                   let existing = rows.first(where: { $0.draftID == draftID && $0.source == source }) {
                    return existing.json
                }
                let taken = rows.filter { $0.draftID == draftID }
                    .compactMap { Int($0.mark.split(separator: "-").last ?? "") }
                let mark = "P-\((taken.max() ?? 0) + 1)"
                let title = (fileName as NSString).deletingPathExtension
                    .replacingOccurrences(of: "_", with: " ")
                let row = Row(
                    id: nextID, draftID: draftID, mark: mark, title: title,
                    source: "/storage/1/\(path)", treatment: "append", verify: "n/a")
                nextID += 1
                rows.append(row)
                return row.json
            }
        }

        func update(_ body: [String: Any]) -> [String: Any]? {
            lock.withLock {
                guard let id = body["id"] as? Int,
                      let i = rows.firstIndex(where: { $0.id == id }) else { return nil }
                if let title = body["title"] as? String { rows[i].title = title }
                if let treatment = body["treatment"] as? String {
                    rows[i].treatment = treatment
                    if body["verify_status"] == nil {
                        rows[i].verify = treatment == "typed"
                            ? (rows[i].verify == "verified" ? "verified" : "pending") : "n/a"
                    }
                }
                if let verify = body["verify_status"] as? String { rows[i].verify = verify }
                return rows[i].json
            }
        }

        func delete(id: Int) -> Bool {
            lock.withLock {
                let before = rows.count
                rows.removeAll { $0.id == id }
                return rows.count < before
            }
        }

        func reorder(draftID: String, ids: [Int]) -> [[String: Any]]? {
            lock.withLock {
                let mine = rows.filter { $0.draftID == draftID }
                guard Set(mine.map(\.id)) == Set(ids), mine.count == ids.count else { return nil }
                let ordered = ids.compactMap { id in mine.first { $0.id == id } }
                rows = rows.filter { $0.draftID != draftID } + ordered
                return ordered.map(\.json)
            }
        }

        /// Places the draft's annexures in the bundle, as assembly back-fills them.
        func placePages(draftID: String) -> [[String: Any]] {
            lock.withLock {
                var folio = 18
                var ranges: [[String: Any]] = []
                for i in rows.indices where rows[i].draftID == draftID {
                    rows[i].pageFrom = folio
                    rows[i].pageTo = folio + 2
                    ranges.append(["mark": rows[i].mark, "from": folio, "to": folio + 2])
                    folio += 3
                }
                return ranges
            }
        }

        func addBundle(draftID: String, status: String, pages: Int?) -> Int {
            lock.withLock {
                let id = 7 + bundles.count
                bundles.insert([
                    "id": id, "draft_id": draftID,
                    "page_count": pages.map { $0 as Any } ?? NSNull(), "status": status,
                    "created_at": Int(Date().timeIntervalSince1970 * 1000),
                ], at: 0)
                return id
            }
        }

        func bundleList(draftID: String?) -> [[String: Any]] {
            lock.withLock {
                guard let draftID, !draftID.isEmpty else { return bundles }
                return bundles.filter { ($0["draft_id"] as? String) == draftID }
            }
        }

        func bundleIsReady(_ id: Int) -> Bool {
            lock.withLock {
                bundles.contains { ($0["id"] as? Int) == id && ($0["status"] as? String) == "ok" }
            }
        }
    }

    private static let store = Store()

    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        if let conversation = messages(path) { return conversation }
        guard path.hasPrefix("/filing/") else { return nil }
        let q = { (name: String) in UITestSupport.Fixtures.query(request, name) }
        switch (request.httpMethod ?? "GET", path) {
        case ("GET", "/filing/drafts"):
            return ok(["drafts": UITestSupport.isEmpty ? [] : drafts])
        case ("GET", "/filing/annexures"):
            guard let draftID = q("draftId") ?? q("chatId").map({ "chat:\($0)" }) else {
                return failure("draftId or chatId required")
            }
            return ok(["annexures": store.list(draftID: draftID)])
        case ("POST", "/filing/annexures"):
            let body = UITestSupport.Fixtures.jsonBody(of: request) ?? [:]
            let chatKey: String? = (body["chatId"] as? String).map { "chat:\($0)" }
            guard let draftID = (body["draftId"] as? String) ?? chatKey,
                  let folder = body["folderName"] as? String, !folder.isEmpty,
                  let fileName = body["fileName"] as? String
            else { return failure("missing folderName") }
            return ok(["annexure": store.add(draftID: draftID, folder: folder, fileName: fileName)])
        case ("POST", "/filing/annexures/update"):
            let body = UITestSupport.Fixtures.jsonBody(of: request) ?? [:]
            guard let row = store.update(body) else { return failure("annexure not found") }
            return ok(["annexure": row])
        case ("POST", "/filing/annexures/delete"):
            let body = UITestSupport.Fixtures.jsonBody(of: request) ?? [:]
            guard let id = body["id"] as? Int, store.delete(id: id) else {
                return failure("annexure not found")
            }
            return ok([:])
        case ("POST", "/filing/annexures/reorder"):
            let body = UITestSupport.Fixtures.jsonBody(of: request) ?? [:]
            guard let draftID = body["draftId"] as? String,
                  let ids = body["orderedIds"] as? [Int],
                  let rows = store.reorder(draftID: draftID, ids: ids)
            else { return failure("orderedIds must be a permutation of the draft's annexures") }
            let marks = rows.compactMap { $0["mark"] as? String }
            return ok(["orderMatchesMarks": marks == marks.sorted(), "annexures": rows])
        case ("POST", "/filing/assemble"):
            return assemble(UITestSupport.Fixtures.jsonBody(of: request) ?? [:])
        case ("GET", "/filing/bundles"):
            return ok(["bundles": store.bundleList(draftID: q("draftId"))])
        case ("GET", "/filing/bundle-download"):
            guard let id = q("bundleId").flatMap(Int.init), store.bundleIsReady(id) else {
                return .json(#"{"success":false,"error":"bundle not found"}"#, status: 404)
            }
            return .bytes(Data(pdf.utf8), type: "application/pdf")
        case ("GET", "/filing/annexures/typed-copy"):
            return typedCopy(chat: q("chatId") ?? "", mark: q("mark") ?? "")
        case ("GET", "/filing/annexures/original"), ("HEAD", "/filing/annexures/original"):
            return original(chat: q("chatId") ?? "", mark: q("mark") ?? "")
        case ("GET", "/filing/annexures/original-pages"):
            return originalPages(chat: q("chatId") ?? "", mark: q("mark") ?? "")
        case ("GET", "/filing/annexures/typed-copies"):
            let typed = store.typedRows(chat: q("chatId") ?? "")
            let html = typed.map { typedCopyHTML(mark: $0.mark, title: $0.title) }.joined()
            return ok(["html": html, "marks": typed.map(\.mark)])
        case ("GET", "/filing/checklist"):
            guard let forum = q("forum"), let name = forumName(forum) else {
                return failure("unknown forum")
            }
            return ok(["checklist": checklist(forum: name, assembled: false)])
        default:
            return .json(#"{"success":false,"error":"not found"}"#, status: 404)
        }
    }

    // MARK: - Assembly

    private static func assemble(_ body: [String: Any]) -> StubReply {
        let chatKey: String? = (body["chatId"] as? String).map { "chat:\($0)" }
        let draftID = (body["draftId"] as? String) ?? chatKey ?? ""
        let cover = body["cover"] as? [String: Any] ?? [:]
        let forum = cover["forum"] as? String ?? ""
        guard !forum.isEmpty else { return failure("cover.forum is required") }
        if body["draftId"] == nil {
            let html = (body["draftHtml"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !html.isEmpty else {
                return ok(["success": false, "errors": ["a draftId or non-empty draftHtml is required"], "warnings": [String]()])
            }
        }
        if (cover["caseType"] as? String) == "Fail" {
            let id = store.addBundle(draftID: draftID, status: "failed", pages: nil)
            return ok([
                "success": false, "bundleId": id, "warnings": [String](),
                "errors": ["P-1 (Board resolution): source file is missing — re-upload it or remove the annexure"],
            ])
        }
        guard let name = forumName(forum) else {
            return ok(["success": false, "errors": ["unknown forum '\(forum)' (use NCLT, NCLAT, High Court or Supreme Court)"], "warnings": [String]()])
        }
        let ranges = store.placePages(draftID: draftID)
        let id = store.addBundle(draftID: draftID, status: "ok", pages: 42)
        return ok([
            "bundleId": id, "pageCount": 42,
            "index": [
                ["label": "Synopsis and List of Dates", "folio": 1],
                ["label": "Writ Petition with affidavit", "folio": 5],
                ["label": "Annexures", "folio": 18],
            ],
            "annexures": ranges,
            "checklist": checklist(forum: name, assembled: true),
            "warnings": ["P-2 is a typed copy that has not been verified against the original"],
            "verify": ["ok": true, "entriesChecked": 3, "mismatches": [String]()],
        ])
    }

    private static func forumName(_ forum: String) -> String? {
        let s = forum.trimmingCharacters(in: .whitespaces).lowercased()
        if s == "nclt" || s.contains("company law tribunal ") { return "NCLT" }
        if s == "nclat" || s.contains("appellate tribunal") { return "NCLAT" }
        if s == "hc" || s.contains("high court") { return "High Court" }
        if s == "sc" || s.contains("supreme") { return "Supreme Court" }
        if s.contains("company law tribunal") { return "NCLT" }
        return nil
    }

    private static func checklist(forum: String, assembled: Bool) -> [String: Any] {
        [
            "forum": forum,
            "items": [
                ["id": "pleading-body", "label": "Main pleading / petition body", "kind": "ai", "status": "ok"],
                ["id": "prayer", "label": "Prayer / reliefs sought", "kind": "ai", "status": "ok"],
                ["id": "affidavit", "label": "Supporting affidavit / verification", "kind": "ai", "status": "missing"],
                ["id": "index", "label": "Index (generated last from the paginated bundle)", "kind": "assembled",
                 "status": assembled ? "ok" : "auto",
                 "note": "Derived folios, verified against stamped pages before the bundle is emitted."],
                ["id": "typed-verified", "label": "Typed true copies verified against originals (human gate)",
                 "kind": "human", "status": "attention"],
                ["id": "court-fee", "label": "Court fee paid", "kind": "human", "status": "manual"],
            ],
            "blockers": ["affidavit"],
            "attention": ["typed-verified"],
        ]
    }

    // MARK: - A conversation's annexures, one by one

    private static func typedCopyHTML(mark: String, title: String) -> String {
        "<div style=\"page-break-before:always\"></div><p style=\"text-align:center\"><strong><u>ANNEXURE \(mark)</u></strong></p>"
            + "<p style=\"text-align:center\"><strong>TRUE TYPED COPY</strong></p><p>\(title). Take notice that the respondent is called upon to appear on the date fixed.</p>"
    }

    private static func typedCopy(chat: String, mark: String) -> StubReply {
        guard let row = store.row(chat: chat, mark: mark) else { return failure("annexure not found") }
        guard row.treatment == "typed" else {
            return ok(["skipped": true, "reason": "Annexure \(mark) is attached as its original, not as a typed copy."])
        }
        return ok(["html": typedCopyHTML(mark: mark, title: row.title), "mark": mark])
    }

    private static func original(chat: String, mark: String) -> StubReply {
        guard let row = store.row(chat: chat, mark: mark) else {
            return .json(#"{"success":false,"error":"annexure not found"}"#, status: 404)
        }
        guard row.source.lowercased().hasSuffix(".pdf") else {
            return .json(#"{"success":false,"error":"preview not available for .heic"}"#, status: 415)
        }
        return .bytes(Data(pdf.utf8), type: "application/pdf")
    }

    private static func originalPages(chat: String, mark: String) -> StubReply {
        guard let row = store.row(chat: chat, mark: mark) else {
            return .json(#"{"success":false,"error":"annexure not found"}"#, status: 404)
        }
        guard row.source.lowercased().hasSuffix(".pdf") else {
            return .json(#"{"success":false,"error":"original-page rendering not available for .heic"}"#, status: 415)
        }
        return ok(["pages": [["base64": jpeg, "mime": "image/jpeg"]]])
    }

    /// A 1×1 grey JPEG.
    private static let jpeg =
        "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA="

    // MARK: - The conversation with a draft (`-UITestFilingChat`)

    /// `/messages` for the conversation whose answer carries a writ petition, or `nil`.
    static func messages(_ path: String) -> StubReply? {
        guard isChatOn, path == "/messages", !UITestSupport.isEmpty else { return nil }
        let paragraphs: [String] = [
            "<p style=\"text-align:center\"><strong>IN THE HIGH COURT OF DELHI AT NEW DELHI</strong></p>",
            "<p style=\"text-align:center\">W.P.(C) No. 1234 of 2026</p>",
            "<p style=\"text-align:center\">Anil Kumar Goel …Petitioner</p>",
            "<p style=\"text-align:center\">versus</p>",
            "<p style=\"text-align:center\">Union of India …Respondent</p>",
            "<p>1. The petitioner is aggrieved by the Look Out Circular issued against him. A copy of the board resolution is annexed as Annexure P-1.</p>",
            "<p>2. The notice under Section 8 is annexed as Annexure P-2.</p>",
        ]
        let draft: String = paragraphs.joined()
        let lead = "Here is the writ petition.\n\n[CANVAS_TRIGGER: Writ Petition — Look Out Circular]\n"
        let answer: String = lead + "<canvas_content>" + draft + "</canvas_content>"
        let files: [[String: Any]] = [
            ["name": "Plaint.pdf", "folderName": "Bakshi"],
            ["name": "Reply_Affidavit.pdf", "folderName": "Bakshi"],
        ]
        let body: [String: Any] = [
            "success": true,
            "messages": [
                ["id": "m1", "role": "user", "content": "Draft a writ petition against the Look Out Circular.",
                 "attachments": files],
                ["id": "m2", "role": "assistant", "content": answer],
            ],
        ]
        return ok(body)
    }

    // MARK: - Fixtures

    /// Computed: a stored `[String: Any]` is not concurrency-safe as a static.
    private static var drafts: [[String: Any]] {
        [
            ["id": "canvas_1", "title": "Writ Petition — Look Out Circular", "type": "doc",
             "created_at": "2026-10-01 09:00:00", "chat_id": "c1"],
            ["id": "table_2", "title": "List of dates — Bakshi", "type": "table",
             "created_at": "2026-10-02T09:00:00.000Z", "chat_id": "c2"],
        ]
    }

    private static let pdf = """
        %PDF-1.4
        1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
        2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
        3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >> endobj
        trailer << /Root 1 0 R >>
        %%EOF
        """

    private static func ok(_ payload: [String: Any]) -> StubReply {
        var body = payload
        if body["success"] == nil { body["success"] = true }
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        return StubReply(status: 200, data: data, contentType: "application/json")
    }

    private static func failure(_ message: String) -> StubReply {
        .json(#"{"success":false,"error":"\#(message)","errors":["\#(message)"]}"#, status: 400)
    }
}
#endif
