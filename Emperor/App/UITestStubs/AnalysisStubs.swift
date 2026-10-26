#if DEBUG
import Foundation

/// The UI tests' canned answers for the analysis tools (`/analysis/*`). Owned by package 12-AN.
///
/// Stateful, per launch: a start resets the tool's job, whose first poll is still thinking and
/// whose second is done — and the finished run then joins the tool's History, after the seeded
/// one. `-UITestAnalysisLimit` refuses every start as a spent monthly allowance; `-UITestEmpty`
/// starts every History empty.
enum AnalysisStubs {
    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        guard path.hasPrefix("/analysis/") else { return nil }
        let method = request.httpMethod ?? "GET"
        switch (method, path) {
        case ("POST", "/analysis/start"):
            if ProcessInfo.processInfo.arguments.contains("-UITestAnalysisLimit") {
                return .json(limitBody, status: 402)
            }
            let tool = (UITestSupport.Fixtures.jsonBody(of: request)?["tool"] as? String) ?? ""
            guard Tool(rawValue: tool) != nil else {
                return .json(#"{"success":false,"error":"tool must be one of: doc-index, list-of-dates, devils-advocate"}"#, status: 400)
            }
            Store.shared.start(tool)
            return .json(#"{"success":true,"jobId":"job-\#(tool)"}"#, status: 202)
        case ("GET", "/analysis/job"):
            let id = UITestSupport.Fixtures.query(request, "id") ?? ""
            guard id.hasPrefix("job-"), let tool = Tool(rawValue: String(id.dropFirst(4))) else {
                return .json(goneBody, status: 404)
            }
            if Store.shared.poll(tool.rawValue) == 1 {
                return .json(#"{"success":true,"status":"thinking","stage":"Spotting every date","progress":0.4}"#)
            }
            Store.shared.finish(tool.rawValue)
            return .json(#"{"success":true,"status":"done","stage":"Done","progress":1,"result":\#(tool.result),"runId":"anr_ui_\#(tool.rawValue)","usage":{"model":"stub","inputTokens":1200,"outputTokens":800,"costUsd":0.01}}"#)
        case ("GET", "/analysis/history"):
            let tool = UITestSupport.Fixtures.query(request, "tool") ?? ""
            let runs = Store.shared.runs(tool).map { summaryJSON($0, tool: tool) }
            return .json(#"{"success":true,"runs":[\#(runs.joined(separator: ","))]}"#)
        case ("GET", "/analysis/run"):
            let id = UITestSupport.Fixtures.query(request, "id") ?? ""
            guard let found = Store.shared.find(id), let kind = Tool(rawValue: found.tool) else {
                return .json(#"{"success":false,"error":"No such saved analysis."}"#, status: 404)
            }
            let summary = summaryJSON(found.run, tool: found.tool)
            return .json(#"{"success":true,"run":\#(summary.dropLast()),"result":\#(kind.result)}}"#)
        case ("DELETE", "/analysis/run"):
            let id = UITestSupport.Fixtures.query(request, "id") ?? ""
            guard Store.shared.remove(id) else {
                return .json(#"{"success":false,"error":"No such saved analysis."}"#, status: 404)
            }
            return .json(#"{"success":true}"#)
        default:
            return .json(#"{"success":false,"error":"Not found"}"#, status: 404)
        }
    }

    private static let limitBody = #"{"success":false,"error":"This month’s queries are used up. Upgrade your plan to keep going.","code":"LIMIT"}"#
    private static let goneBody = #"{"success":false,"error":"This analysis is no longer running (it finished over an hour ago, or the server restarted). Run it again."}"#

    private struct Run {
        var id: String
        var title: String
        var createdAt: String
        var fileNames: [String]
        var reference: String
    }

    private static func summaryJSON(_ run: Run, tool: String) -> String {
        let files = run.fileNames.map { #""\#($0)""# }.joined(separator: ",")
        return #"{"id":"\#(run.id)","tool":"\#(tool)","title":"\#(run.title)","createdAt":"\#(run.createdAt)","fileNames":[\#(files)],"reference":"\#(run.reference)","usage":null}"#
    }

    private final class Store: @unchecked Sendable {
        static let shared = Store()
        private let lock = NSLock()
        private var polls: [String: Int] = [:]
        private var added: [String: [Run]] = [:]
        private var removed: Set<String> = []

        func start(_ tool: String) {
            lock.withLock { polls[tool] = 0 }
        }

        /// Which poll this is, from 1.
        func poll(_ tool: String) -> Int {
            lock.withLock {
                polls[tool, default: 0] += 1
                return polls[tool]!
            }
        }

        func finish(_ tool: String) {
            lock.withLock {
                let id = "anr_ui_\(tool)"
                removed.remove(id)
                guard !(added[tool] ?? []).contains(where: { $0.id == id }) else { return }
                added[tool, default: []].insert(
                    Run(id: id, title: "Bakshi v. State of Maharashtra", createdAt: "2026-10-27T09:34:00.000Z",
                        fileNames: ["Plaint.pdf", "Interim_Order.pdf"], reference: ""),
                    at: 0)
            }
        }

        func runs(_ tool: String) -> [Run] {
            lock.withLock {
                let seed: [Run] = UITestSupport.isEmpty ? [] : [Run(
                    id: "anr_seed_\(tool)", title: "Helios v. Northgrid (seed)",
                    createdAt: "2026-10-20T09:30:00.000Z",
                    fileNames: ["Plaint.pdf", "Power_Purchase_Agreement.pdf", "Legal_notice_and_reply.pdf"],
                    reference: "We act for Helios.")]
                let extra: [Run] = added[tool] ?? []
                return (extra + seed).filter { !removed.contains($0.id) }
            }
        }

        func find(_ id: String) -> (tool: String, run: Run)? {
            for tool in Tool.allCases.map(\.rawValue) {
                if let run = runs(tool).first(where: { $0.id == id }) { return (tool: tool, run: run) }
            }
            return nil
        }

        func remove(_ id: String) -> Bool {
            guard find(id) != nil else { return false }
            lock.withLock { _ = removed.insert(id) }
            return true
        }
    }

    private enum Tool: String, CaseIterable {
        case devilsAdvocate = "devils-advocate"
        case docIndex = "doc-index"
        case listOfDates = "list-of-dates"

        var result: String {
            switch self {
            case .devilsAdvocate: return AnalysisStubs.devilsAdvocate
            case .docIndex: return AnalysisStubs.docIndex
            case .listOfDates: return AnalysisStubs.listOfDates
            }
        }
    }

    // MARK: - Results

    private static let devilsAdvocate = #"""
    {"matter":{"title":"Bakshi v. State of Maharashtra","forum":"Bombay High Court","number":"WP 1234/2025","client":"Rohan Bakshi"},
     "exposureScore":64,
     "oneMinute":["The writ was filed after the notice period, so delay is the first thing the State will raise.","The interim order helps, but the record does not yet prove service on the Collector."],
     "weakSpots":[
      {"id":1,"severity":"serious","category":"limitation","likelihood":4,"impact":5,"title":"The petition was filed after the notice period","why":"The State will say the petitioner sat on his rights.","where":["Petition para 3","Notice of 2 Jan 2025"],"say":"The petitioner waited eleven months and offers no explanation.","fix":"Add an affidavit explaining the delay with the dates of each representation."},
      {"id":2,"severity":"minor","category":"procedure","likelihood":2,"impact":2,"title":"No proof of service on the Collector","why":"An unserved respondent can delay the hearing.","where":["Affidavit of service"],"say":"Respondent 3 was never served.","fix":"File the postal receipt and tracking report."}],
     "questions":[
      {"q":"Why was the petition filed eleven months late?","why":"Delay defeats writ relief.","answer":"Representations dated 5 Feb and 9 Jun 2025 were pending.","readiness":"work","spot":1},
      {"q":"Was the Collector served?","why":"To adjourn the hearing.","answer":"Postal receipt of 3 Oct 2025.","readiness":"ready","spot":2}],
     "docGaps":[{"doc":"Postal tracking report","who":"Registry clerk","how":"Download from the India Post site","when":"Before the next listing","spot":2}],
     "authorities":[{"name":"Tukaram Kana Joshi v. MIDC","court":"Supreme Court","year":"2013","holds":"Delay is not fatal where the State's own conduct caused it.","distinguish":"Show the representations were pending with the State.","against":1,"verify":true}],
     "checklist":[{"id":"c1","text":"Draft the delay affidavit","done":true},{"id":"c2","text":"File proof of service","done":false},{"id":"c3","text":"Read the interim order again","done":false}]}
    """#

    private static let docIndex = #"""
    {"label":"Bakshi writ bundle","rationale":"A writ file, so the index shows the document type and what to watch in each paper.","filterKey":"type","filterLabel":"Type",
     "flag":{"key":"issues","nonEmpty":true,"label":"with an issue to watch"},
     "columns":[
      {"key":"sr","label":"Sr.","type":"number","width":70,"pin":true,"description":"Serial number."},
      {"key":"doc","label":"Document","type":"text","width":240,"pin":true,"strong":true,"description":"The paper, as the case calls it."},
      {"key":"type","label":"Type","type":"badge","width":140,"description":"What kind of paper it is.","tones":{"Pleading":"accent","Order":"info","Notice":"warn"}},
      {"key":"issues","label":"Issues to watch","type":"long","width":320,"description":"What the other side may use."}],
     "rows":[
      {"sr":1,"doc":"Writ petition","type":"Pleading","issues":"Para 3 does not explain the delay."},
      {"sr":2,"doc":"Interim order of 3 Oct 2025","type":"Order","issues":null},
      {"sr":3,"doc":"Legal notice to the Collector","type":"Notice","issues":"No proof of service on file."}]}
    """#

    private static let listOfDates = #"""
    {"matter":{"title":"Bakshi v. State of Maharashtra","number":"WP 1234/2025","forum":"Bombay High Court"},
     "parties":{"ours":"Bakshi","other":"State"},
     "entries":[
      {"id":"r1","day":"1963","label":"1963","cat":"rules","short":"Limitation Act, 1963","text":"**Limitation Act, 1963:** three years for a money claim (**Art. 113**)."},
      {"id":"1","day":"2025-01-02","cat":"adverse","short":"Notice of demolition","text":"The State issues a **notice of demolition** (**Annexure P-1**)."},
      {"id":"2","day":"2025-02-05","cat":"ours","short":"First representation","text":"Bakshi files his **first representation** (**Annexure P-2**)."},
      {"id":"3","day":"2025-10-03","cat":"others","short":"Interim order","text":"The High Court grants an **interim stay** (**Order of 03.10.2025**)."},
      {"id":"4","day":"2026-11-20","cat":"others","upcoming":true,"short":"Next hearing","text":"**Next hearing** before the Division Bench."}],
     "inSum":"The State issued the notice in January 2025; Bakshi represented in February, and the Court stayed the demolition in October.",
     "limitation":{"headline":"Notice 2 Jan 2025 → challenge filed in time","note":"A writ has no fixed period, but delay must be explained."}}
    """#
}
#endif
