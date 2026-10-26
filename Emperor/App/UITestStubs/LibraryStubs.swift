#if DEBUG
import Foundation

/// The UI tests' canned library catalogue, `/library/catalogue/*`. Owned by package 09-L.
///
/// Shapes are the catalogue's own (see `LibraryCatalogueModels`): three collections; Case Law in
/// 45 judgments (three pages of 20, fifteen of them Delhi's), a structured judgment (257708), one
/// whose formatting fails so the reader falls back to its text (19655), and a PDF whose file is
/// not on the server (999); the Indian Penal Code (2478) with its rules, one repealed, and an
/// amendment; covers for even ids, none for odd ones, and one (4) still rendering the first time
/// it is asked for. A search for "busy" is refused as busy once, then answered. `-UITestEmpty`
/// leaves the catalogue with no collections.
enum LibraryStubs {

    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        guard path.hasPrefix("/library/catalogue/") else { return nil }
        let route = String(path.dropFirst("/library/catalogue".count))
        let q = { (name: String) in UITestSupport.Fixtures.query(request, name) }
        let isHead = request.httpMethod == "HEAD"

        switch route {
        case "/categories":
            if UITestSupport.isEmpty { return .json(#"{"success":true,"categories":[]}"#) }
            return .json(#"{"success":true,"categories":[{"key":"bare-acts","label":"Bare acts","count":2},{"key":"case-law","label":"Case law","count":45},{"key":"books-and-law-reports","label":"Books and law reports","count":3}]}"#)
        case "/shelf":
            return shelf(q("category") ?? "", by: q("by"))
        case "/facets":
            return facets(q("category") ?? "")
        case "/browse":
            if q("groupBy") == "category" { return grouped(q("q") ?? "") }
            return browse(category: q("category") ?? "", court: q("court"), page: Int(q("page") ?? "") ?? 1,
                          pageSize: Int(q("pageSize") ?? "") ?? 20, series: q("series"))
        case "/search":
            if q("q") == "busy", busy.firstTime() {
                return .json(#"{"error":"search_busy"}"#, status: 503)
            }
            return .json(#"{"success":true,"items":[\#(judgmentRow(257708, snippet: true)),\#(judgmentRow(19655, snippet: true))],"total":2,"totalIsCapped":false,"page":1,"pageSize":20,"sort":null,"search":"\#(escape(q("q") ?? ""))","mode":"body","index":{"available":true,"ready":true,"complete":true,"indexed":45,"pending":0,"noText":0,"total":45}}"#)
        case "/search-status":
            return .json(#"{"success":true,"index":{"available":true,"ready":true,"complete":true,"indexed":45,"pending":0,"noText":0,"total":45}}"#)
        case "/folders":
            return folders(kind: q("kind"))
        case "/act":
            return act(Int(q("id") ?? "") ?? 0)
        case "/judgment":
            return judgment(Int(q("id") ?? "") ?? 0)
        case "/doc":
            let id = Int(q("id") ?? "") ?? 0
            return .json(#"{"success":true,"doc":\#(docRow(id))}"#)
        case "/file":
            let id = Int(q("id") ?? "") ?? 0
            if id == 999 { return .json(#"{"error":"not_found"}"#, status: 404) }
            if isHead { return .bytes(Data(), type: "application/pdf") }
            if q("prefer") == "text" {
                return .bytes(Data(plainJudgment.utf8), type: "text/plain; charset=utf-8")
            }
            return .bytes(Data(pdf.utf8), type: "application/pdf")
        case "/cover":
            let id = Int(q("id") ?? "") ?? 0
            if id == 4, pending.firstTime() {
                return .json(#"{"error":"cover_pending"}"#, status: 404)
            }
            if id % 2 == 0, let jpeg = Data(base64Encoded: jpegBase64) {
                return .bytes(jpeg, type: "image/jpeg")
            }
            return .json(#"{"error":"no_cover","reason":"none"}"#, status: 404)
        default:
            return .json(#"{"error":"unknown_library_route","path":"\#(path)"}"#, status: 404)
        }
    }

    // MARK: - State

    /// Answers `true` the first time only, behind a lock: `URLProtocol` answers on its own queue.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false
        func firstTime() -> Bool {
            lock.lock(); defer { lock.unlock() }
            defer { used = true }
            return !used
        }
    }

    private static let busy = Once()
    private static let pending = Once()

    // MARK: - Rows

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func judgmentRow(_ id: Int, snippet: Bool = false) -> String {
        let title = id == 257708 ? "Seethamma vs State Of Karnataka on 31 October, 2012" : "Ramesh Kumar vs Union Of India"
        let parties = id == 257708 ? #""petitioner":"Seethamma","respondent":"State Of Karnataka","# : ""
        let passage = snippet
            ? #","snippet":{"text":"the court held that bail could not be refused","before":true,"after":true,"term":"court"}"#
            : ""
        return #"{"id":\#(id),"title":"\#(title)",\#(parties)"category":"case-law","docType":"judgment","court":"supremecourt","courtLabel":"Supreme Court of India","year":2012,"decidedOn":"2012-10-31","neutralCitation":"2012 INSC \#(id % 1000)","isAmendment":false,"titleFromScan":false,"ext":".txt","fileSize":48211,"render":"\#(id == 257708 ? "html" : "text")"\#(passage)}"#
    }

    private static func caseRow(_ n: Int, court: String) -> String {
        let label = court == "delhi" ? "Delhi High Court" : "Supreme Court of India"
        let day = String(format: "2025-%02d-%02d", 12 - (n % 12), 1 + (n % 27))
        return #"{"id":\#(100_000 + n),"title":"Petitioner \#(n) vs State","category":"case-law","docType":"judgment","court":"\#(court)","courtLabel":"\#(label)","year":2025,"decidedOn":"\#(day)","isAmendment":false,"titleFromScan":false,"ext":".txt","fileSize":2048,"render":"text"}"#
    }

    private static func bookRow(_ id: Int, title: String, series: String? = nil, volume: String? = nil, year: Int = 1950) -> String {
        let seriesPart = series.map { #""series":"\#($0)","# } ?? ""
        let volumePart = volume.map { #""volume":"\#($0)","# } ?? ""
        return #"{"id":\#(id),"title":"\#(title)",\#(seriesPart)\#(volumePart)"category":"books-and-law-reports","year":\#(year),"isAmendment":false,"titleFromScan":false,"ext":".pdf","fileSize":204800,"render":"pdf","coverUrl":"/api/library/catalogue/cover?id=\#(id)&w=320"}"#
    }

    private static func actRow(_ id: Int, title: String, year: Int, docType: String = "act", rules: Int = 0, repealed: Bool = false) -> String {
        let counts = rules > 0 ? #","tabCounts":{"act":1,"rules":\#(rules),"amendments":1},"instruments":\#(rules + 1),"hasChildren":\#(rules + 1)"# : ""
        return #"{"id":\#(id),"title":"\#(title)","category":"bare-acts","docType":"\#(docType)","jurisdiction":"Central","year":\#(year),"isAmendment":false,"titleFromScan":false,"ext":".pdf","fileSize":1468006,"render":"pdf","kind":"act","firstLetter":"I","jurisdictionInferred":false\#(repealed ? #","repealed":true"# : "")\#(counts)}"#
    }

    private static let ipc = actRow(2478, title: "THE INDIAN PENAL CODE, 1860", year: 1860, rules: 2)
    private static let crpc = actRow(2500, title: "The Code of Criminal Procedure, 1973", year: 1973)

    private static func docRow(_ id: Int) -> String {
        switch id {
        case 257708, 19655:
            return judgmentRow(id).replacingOccurrences(of: #""render":"#, with: #""hasFile":true,"hasText":true,"render":"#)
        case 999:
            return #"{"id":999,"title":"Calcutta Law Journal, Vol-09","series":"Calcutta Law Journal","volume":"9","category":"books-and-law-reports","year":1909,"isAmendment":false,"titleFromScan":false,"ext":".pdf","fileSize":204800,"render":"pdf","hasFile":false,"childGroups":[],"childCount":0,"editions":[],"parent":null}"#
        case 2478, 2479, 2480, 2481, 2500:
            return actRow(id, title: "THE INDIAN PENAL CODE, 1860", year: 1860)
        default:
            return bookRow(id, title: "Document \(id)").replacingOccurrences(of: #""render":"pdf""#, with: #""render":"pdf","hasFile":true"#)
        }
    }

    // MARK: - Routes

    private static func shelf(_ category: String, by: String?) -> StubReply {
        if by == "series" {
            return .json(#"{"success":true,"category":"books-and-law-reports","label":"Books and law reports","day":20261027,"seriesTotal":1,"shelves":[{"series":"Calcutta Law Journal","count":3,"yearMin":1904,"yearMax":1909,"items":[\#(bookRow(30, title: "Calcutta Law Journal, Vol-01", series: "Calcutta Law Journal", volume: "1", year: 1904)),\#(bookRow(4, title: "Calcutta Law Journal, Vol-02", series: "Calcutta Law Journal", volume: "2", year: 1905))]}],"standalone":{"count":1,"items":[\#(bookRow(31, title: "A Treatise on Easements", year: 1931))]}}"#)
        }
        let items: [String]
        switch category {
        case "bare-acts": items = [ipc, crpc]
        case "case-law": items = [judgmentRow(257708), judgmentRow(19655), caseRow(1, court: "supremecourt")]
        case "books-and-law-reports":
            items = [bookRow(30, title: "Calcutta Law Journal, Vol-01", series: "Calcutta Law Journal", volume: "1", year: 1904),
                     bookRow(4, title: "Calcutta Law Journal, Vol-02", series: "Calcutta Law Journal", volume: "2", year: 1905),
                     docRow(999)]
        default: items = []
        }
        return .json(#"{"success":true,"category":"\#(category)","label":"x","day":20261027,"items":[\#(items.joined(separator: ","))]}"#)
    }

    private static func facets(_ category: String) -> StubReply {
        let sorts = category == "case-law"
            ? #"[{"value":"date_desc","label":"Newest"},{"value":"date_asc","label":"Oldest"},{"value":"court","label":"Court"}]"#
            : #"[{"value":"title_asc","label":"Title A–Z"},{"value":"year_desc","label":"Year (newest)"}]"#
        let courts = category == "case-law"
            ? #"[{"value":"supremecourt","label":"Supreme Court of India","count":30},{"value":"delhi","label":"Delhi High Court","count":15}]"#
            : "[]"
        let letters = category == "case-law" ? "[]"
            : "[" + (["#"] + (65...90).map { String(UnicodeScalar($0)!) }).map { #"{"letter":"\#($0)","count":\#($0 == "C" || $0 == "A" ? 2 : 0)}"# }.joined(separator: ",") + "]"
        return .json(#"{"success":true,"facets":{"category":"\#(category)","label":"x","courts":\#(courts),"years":[{"year":2025,"count":20},{"year":2024,"count":15},{"year":2023,"count":10}],"yearRange":{"min":2023,"max":2025},"docTypes":[],"jurisdictions":[],"series":[{"value":"Calcutta Law Journal","count":3,"yearMin":1904,"yearMax":1909},{"value":"All India Reporter","count":2}],"publishers":[],"kinds":[],"letters":\#(letters),"sorts":\#(sorts)}}"#)
    }

    private static func grouped(_ q: String) -> StubReply {
        .json(#"{"success":true,"groups":[{"category":"bare-acts","label":"Bare acts","total":2,"items":[\#(ipc)]},{"category":"case-law","label":"Case law","total":45,"items":[\#(judgmentRow(257708)),\#(judgmentRow(19655))]}],"search":"\#(escape(q))","pageSize":6}"#)
    }

    private static func browse(category: String, court: String?, page: Int, pageSize: Int, series: String?) -> StubReply {
        switch category {
        case "case-law":
            let total = court == "delhi" ? 15 : 45
            let size = max(1, pageSize)
            let first = (max(page, 1) - 1) * size
            let rows = (first..<min(total, first + size)).map { caseRow($0 + 1, court: court ?? ($0 % 3 == 0 ? "delhi" : "supremecourt")) }
            return .json(#"{"success":true,"items":[\#(rows.joined(separator: ","))],"total":\#(total),"page":\#(page),"pageSize":\#(size),"sort":"date_desc"}"#)
        case "books-and-law-reports":
            let rows = series != nil
                ? [bookRow(30, title: "Calcutta Law Journal, Vol-01", series: series, volume: "1", year: 1904),
                   bookRow(4, title: "Calcutta Law Journal, Vol-02", series: series, volume: "2", year: 1905),
                   docRow(999)]
                : [bookRow(30, title: "Calcutta Law Journal, Vol-01", series: "Calcutta Law Journal", volume: "1", year: 1904),
                   bookRow(31, title: "A Treatise on Easements", year: 1931), docRow(999)]
            return .json(#"{"success":true,"items":[\#(rows.joined(separator: ","))],"total":3,"page":1,"pageSize":\#(pageSize),"sort":"title_asc"}"#)
        default:
            return .json(#"{"success":true,"items":[],"total":0,"page":1,"pageSize":\#(pageSize),"sort":"title_asc"}"#)
        }
    }

    private static func folders(kind: String?) -> StubReply {
        if kind == "featured" {
            return .json(#"{"success":true,"items":[\#(ipc),\#(crpc)],"total":2,"page":1,"pageSize":40,"letters":[],"jurisdictions":[]}"#)
        }
        let letters = "[" + (["#"] + (65...90).map { String(UnicodeScalar($0)!) }).map { l in
            #"{"letter":"\#(l)","count":\#(l == "I" || l == "C" ? 1 : 0)}"#
        }.joined(separator: ",") + "]"
        return .json(#"{"success":true,"items":[\#(crpc),\#(ipc)],"total":2,"page":1,"pageSize":60,"letters":\#(letters),"jurisdictions":[{"value":"Central","label":"Central","count":2}]}"#)
    }

    private static func act(_ id: Int) -> StubReply {
        guard [2478, 2479, 2480, 2481].contains(id) else {
            if id == 2500 {
                return .json(#"{"success":true,"act":\#(crpc),"bundleId":2500,"kind":"act","requestedId":2500,"selectedId":2500,"selectedTab":"act","orphan":false,"tabs":[{"key":"act","label":"The Act","count":1,"docs":[\#(crpc)]}]}"#)
            }
            return .json(#"{"error":"not_found"}"#, status: 404)
        }
        let rule = actRow(2479, title: "Indian Penal Code Rules, 1950", year: 1950, docType: "rules")
        let repealed = actRow(2480, title: "Penal Code (Old) Rules, 1901 (Rep., Act 5 of 1960)", year: 1901, docType: "rules", repealed: true)
        let amendment = actRow(2481, title: "The Indian Penal Code (Amendment) Act, 2013", year: 2013)
        let selectedTab = id == 2479 || id == 2480 ? "rules" : (id == 2481 ? "amendments" : "act")
        return .json(#"{"success":true,"act":\#(ipc),"bundleId":2478,"kind":"act","requestedId":\#(id),"selectedId":\#(id),"selectedTab":"\#(selectedTab)","orphan":false,"tabs":[{"key":"act","label":"The Act","count":1,"docs":[\#(ipc)]},{"key":"rules","label":"Rules","count":2,"docs":[\#(rule),\#(repealed)]},{"key":"amendments","label":"Amendments","count":1,"docs":[\#(amendment)]}]}"#)
    }

    private static func judgment(_ id: Int) -> StubReply {
        if id == 19655 { return .json(#"{"error":"library_failed"}"#, status: 500) }
        guard id == 257708 else { return .json(#"{"error":"file_missing"}"#, status: 404) }
        var blocks = [
            #"{"id":"b-0","type":"cause","text":"SEETHAMMA ... Appellant\nVersus\nSTATE OF KARNATAKA ... Respondent","lines":["SEETHAMMA ... Appellant","Versus","STATE OF KARNATAKA ... Respondent"]}"#,
            #"{"id":"h-1","type":"heading","text":"JUDGMENT","level":1}"#,
        ]
        for n in 1...16 {
            blocks.append(#"{"id":"para-\#(n)","type":"para","n":"\#(n)","text":"Paragraph \#(n). The court considered the submissions made before the court on this point."}"#)
            if n == 8 {
                blocks.append(#"{"id":"b-q","type":"quote","text":"Bail is the rule and jail the exception."}"#)
            }
        }
        blocks.append(#"{"id":"b-sig","type":"meta","role":"signature","text":"New Delhi\nOctober 31, 2012","lines":["New Delhi","October 31, 2012"]}"#)
        let toc = #"[{"id":"h-1","label":"JUDGMENT","level":1},{"id":"para-1","label":"Para 1","level":3},{"id":"para-10","label":"Para 10","level":3}]"#
        return .json(#"{"success":true,"doc":\#(judgmentRow(257708)),"header":{"court":"supremecourt","courtLabel":"Supreme Court of India","title":"Seethamma vs State Of Karnataka","petitioner":"Seethamma","respondent":"State Of Karnataka","caseNumber":"7710 of 2012","caseType":"Civil Appeal","decidedOn":"2012-10-31","year":2012,"bench":["A.K. Patnaik","Swatanter Kumar"],"author":"A.K. Patnaik","citations":["(2012) 10 SCC 409"],"neutralCitation":"2012 INSC 708","source":null,"citesCount":4,"citedByCount":2},"blocks":[\#(blocks.joined(separator: ","))],"toc":\#(toc),"stats":{"paragraphs":16,"words":1200,"blocks":\#(blocks.count),"layout":"sc","debrisLines":0,"formatMs":3},"formatterVersion":7,"cached":true}"#)
    }

    // MARK: - Bytes

    private static let plainJudgment = """
        Title: Ramesh Kumar vs Union Of India
        ==========
        IN THE HIGH COURT OF DELHI

        1. This petition is placed before the court for orders.

        2. The court has heard the parties at length.

        3. The petition is allowed.
        """

    private static let pdf = """
        %PDF-1.4
        1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
        2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
        3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >> endobj
        trailer << /Root 1 0 R >>
        %%EOF
        """

    /// A small JPEG in a book's green, for the covers that have one.
    private static let jpegBase64 = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkzODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2P/2wBDARESEhgVGC8aGi9jQjhCY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2P/wAARCAAGAAQDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDnKKKKDmP/2Q=="
}
#endif
