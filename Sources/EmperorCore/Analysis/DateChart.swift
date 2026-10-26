import Foundation

/// A List of Dates: every dated entry in the papers, as an event chart (rules on the left, the
/// year in the middle, events on the right) and a timeline
/// (`src/pages/analysis/samples/listOfDates.js`).
///
/// `normalise` is the port of the web's `normalizeResult`. It never fails: junk entries are
/// dropped, odd ones repaired, and the entries sorted by day with undated ones last.
struct DateChart: Equatable, Sendable {

    enum Category: String, CaseIterable, Sendable {
        case rules, ours, others, adverse
    }

    struct Entry: Equatable, Sendable, Identifiable {
        var id: String
        /// "YYYY-MM-DD", "YYYY-MM", "YYYY", or "" when the day could not be read.
        var day: String
        var cat: Category
        /// The full line, with `**bold**` around key terms.
        var text: String
        /// The timeline's headline.
        var short: String
        var label: String
        var upcoming: Bool
        /// Everything a search looks in, lower-cased.
        var hay: String
        var order: Int

        var isEvent: Bool { cat != .rules }
        /// The date as the chart writes it: the entry's own label, else "12.03.2023".
        var dateLabel: String { label.isEmpty ? DateChart.dmy(day) : label }
    }

    struct Matter: Equatable, Sendable {
        var title = ""
        var number = ""
        var forum = ""
    }

    struct Limitation: Equatable, Sendable {
        var headline: String
        var note: String
    }

    /// The words for one category: in the key, on its filter chip, and as its column caption.
    struct CategoryWords: Equatable, Sendable {
        var label: String
        var chip: String
        var who: String
    }

    struct Summary: Equatable, Sendable {
        var total: Int
        var rules: Int
        var ours: Int
        var others: Int
        var adverse: Int
        var from: String
        var to: String
        var all: Int

        subscript(_ c: Category) -> Int {
            switch c {
            case .rules: return rules
            case .ours: return ours
            case .others: return others
            case .adverse: return adverse
            }
        }
    }

    var entries: [Entry]
    var matter: Matter
    /// The short names of the two sides, as given ("Helios", "Northgrid"), trimmed.
    var ours: String
    var other: String
    var inSum: String
    var limitation: Limitation?
    var chartTitleOverride: String
    var cats: [Category: CategoryWords]
    var sum: Summary
    var title: String

    // MARK: - Normalising

    private static func clean(_ v: JSONValue?, _ max: Int = 600) -> String {
        guard case .string(let s)? = v else { return "" }
        return AnalysisJS.prefix(AnalysisJS.trim(s), max)
    }

    /// The server's `result` (or a stored one), or anything else, as a chart.
    static func normalise(_ raw: JSONValue?) -> DateChart {
        let r = AnalysisJS.fields(raw)
        var source: [JSONValue] = []
        if case .array(let items)? = r["entries"] { source = items }
        var seen = Set<String>()
        var entries: [Entry] = []
        for (i, item) in source.enumerated() {
            guard AnalysisJS.isObjectLike(item) else { continue }
            let x = AnalysisJS.fields(item)
            let text = clean(x["text"], 6000)
            let short0 = clean(x["short"], 300)
            if text.isEmpty, short0.isEmpty { continue }
            let rawDay: JSONValue? = (x["day"] == nil || x["day"] == .null) ? x["date"] : x["day"]
            let day = normDay(rawDay)
            let cat = x["cat"]?.stringValue.flatMap(Category.init(rawValue:)) ?? .others
            var id: String
            switch x["id"] {
            case nil, .null?, .string("")?: id = "e\(i)"
            default: id = AnalysisJS.string(x["id"])
            }
            if seen.contains(id) { id = "\(id)#\(i)" }
            seen.insert(id)
            let body = text.isEmpty ? short0 : text
            let plainBody = plain(body)
            let short = short0.isEmpty
                ? (AnalysisJS.length(plainBody) > 90 ? AnalysisJS.trimEnd(AnalysisJS.prefix(plainBody, 87)) + "…" : plainBody)
                : short0
            let label = clean(x["label"], 40)
            let upcoming = x["upcoming"] == .bool(true) && !day.isEmpty
            let dateLabel = label.isEmpty ? dmy(day) : label
            let hay = [plainBody, short, dateLabel, fullDate(day)].joined(separator: " ").lowercased()
            entries.append(Entry(
                id: id, day: day, cat: cat, text: body, short: short, label: label,
                upcoming: upcoming, hay: hay, order: i))
        }
        entries = AnalysisJS.stableSorted(entries) { a, b in
            if a.day.isEmpty != b.day.isEmpty { return a.day.isEmpty ? 1 : -1 }
            if a.day != b.day { return a.day < b.day ? -1 : 1 }
            return a.order - b.order
        }

        var matter = Matter()
        if AnalysisJS.isObjectLike(r["matter"]) {
            let m = AnalysisJS.fields(r["matter"])
            matter = Matter(title: clean(m["title"], 300), number: clean(m["number"], 120), forum: clean(m["forum"], 200))
        }
        var limitation: Limitation?
        if AnalysisJS.isObjectLike(r["limitation"]) {
            let l = AnalysisJS.fields(r["limitation"])
            let headline = clean(l["headline"], 300)
            if !headline.isEmpty { limitation = Limitation(headline: headline, note: clean(l["note"], 800)) }
        }
        let parties = AnalysisJS.fields(r["parties"])
        let ours = clean(parties["ours"], 60)
        let other = clean(parties["other"], 60)
        let sum = summarise(entries)
        let chartTitleOverride = clean(r["chartTitle"], 300)
        return DateChart(
            entries: entries, matter: matter, ours: ours, other: other,
            inSum: clean(r["inSum"], 6000), limitation: limitation,
            chartTitleOverride: chartTitleOverride,
            cats: catsFor(ours: ours, other: other, labels: r["labels"]),
            sum: sum,
            title: chartTitle(override: chartTitleOverride, sum: sum, ours: ours, other: other))
    }

    /// The four categories' words, named from the parties and the result's own overrides.
    static func catsFor(ours o: String, other t: String, labels: JSONValue?) -> [Category: CategoryWords] {
        var base: [Category: CategoryWords] = [
            .rules: CategoryWords(label: "Rules / orders", chip: "Rules & orders", who: "Rules, contract terms & orders"),
            .ours: CategoryWords(
                label: o.isEmpty ? "Our side’s acts" : "\(o)’s own acts",
                chip: o.isEmpty ? "Our side" : "\(o) (ours)",
                who: o.isEmpty ? "Our side" : o),
            .others: CategoryWords(label: "Third parties", chip: "Third parties", who: "Bank, grid, court, others"),
            .adverse: CategoryWords(
                label: "Adverse action",
                chip: t.isEmpty ? "Other side (adverse)" : "\(t) (adverse)",
                who: t.isEmpty ? "Other side / adverse" : "\(t) / adverse"),
        ]
        let overrides = AnalysisJS.fields(labels)
        for c in Category.allCases {
            guard AnalysisJS.isObjectLike(overrides[c.rawValue]) else { continue }
            let ov = AnalysisJS.fields(overrides[c.rawValue])
            let label = clean(ov["label"], 80), chip = clean(ov["chip"], 80), who = clean(ov["who"], 80)
            if !label.isEmpty { base[c]?.label = label }
            if !chip.isEmpty { base[c]?.chip = chip }
            if !who.isEmpty { base[c]?.who = who }
        }
        return base
    }

    static func summarise(_ entries: [Entry]) -> Summary {
        func count(_ c: Category) -> Int { entries.filter { $0.cat == c }.count }
        let events = entries.filter { $0.isEvent && !$0.day.isEmpty }
        return Summary(
            total: entries.filter(\.isEvent).count, rules: count(.rules), ours: count(.ours),
            others: count(.others), adverse: count(.adverse),
            from: events.first.map { yearOf($0.day) } ?? "",
            to: events.last.map { yearOf($0.day) } ?? "",
            all: entries.count)
    }

    static func chartTitle(override: String, sum: Summary, ours o: String, other t: String) -> String {
        if !override.isEmpty { return override }
        let who = !o.isEmpty && !t.isEmpty ? "WHAT \(o.uppercased()) AND \(t.uppercased()) DID" : "WHAT EACH SIDE DID"
        let span = sum.from.isEmpty ? "" : " (\(sum.from == sum.to ? sum.from : "\(sum.from) TO \(sum.to)"))"
        return "EVENT CHART: HOW THE RULES AND CONTRACT TERMS CAME, AND \(who)\(span)"
    }

    // MARK: - Reading dates

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private static func monthIndex(_ name: String) -> Int? {
        let key = String(name.prefix(3)).lowercased()
        return months.firstIndex { $0.lowercased() == key }.map { $0 + 1 }
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are fixed text below; a failure to compile is a programming error.
        try! NSRegularExpression(pattern: pattern)
    }

    // `\d` is written [0-9] throughout: JavaScript's `\d` is ASCII, ICU's is every digit.
    nonisolated(unsafe) private static let isoForm = regex(#"^([0-9]{4})(?:-([0-9]{1,2})(?:-([0-9]{1,2}))?)?(?:[T\s].*)?$"#)
    nonisolated(unsafe) private static let dmyForm = regex(#"^([0-9]{1,2})[./-]([0-9]{1,2})[./-]([0-9]{4})$"#)
    nonisolated(unsafe) private static let dayMonthForm = regex(#"^([0-9]{1,2})(?:st|nd|rd|th)?[\s,-]+([A-Za-z]{3,9})\.?[\s,-]+([0-9]{4})$"#)
    nonisolated(unsafe) private static let monthDayForm = regex(#"^([A-Za-z]{3,9})\.?[\s,-]+([0-9]{1,2})(?:st|nd|rd|th)?,?[\s,-]+([0-9]{4})$"#)
    nonisolated(unsafe) private static let monthYearForm = regex(#"^([A-Za-z]{3,9})\.?[\s,-]+([0-9]{4})$"#)

    private static func groups(_ re: NSRegularExpression, _ s: String) -> [String?]? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }

    /// Any date a model might write, as "YYYY-MM-DD", "YYYY-MM", "YYYY", or "" when unreadable.
    static func normDay(_ v: JSONValue?) -> String {
        let raw: String
        switch v {
        case nil, .null?: raw = ""
        default: raw = AnalysisJS.string(v)
        }
        let s = AnalysisJS.trim(raw)
        guard !s.isEmpty else { return "" }
        var y: Int?, m: Int?, d: Int?
        if let g = groups(isoForm, s) {
            y = g[0].flatMap { Int($0) }; m = g[1].flatMap { Int($0) }; d = g[2].flatMap { Int($0) }
        } else if let g = groups(dmyForm, s) {
            d = g[0].flatMap { Int($0) }; m = g[1].flatMap { Int($0) }; y = g[2].flatMap { Int($0) }
        } else if let g = groups(dayMonthForm, s) {
            d = g[0].flatMap { Int($0) }; m = g[1].flatMap(monthIndex); y = g[2].flatMap { Int($0) }
        } else if let g = groups(monthDayForm, s) {
            m = g[0].flatMap(monthIndex); d = g[1].flatMap { Int($0) }; y = g[2].flatMap { Int($0) }
        } else if let g = groups(monthYearForm, s) {
            m = g[0].flatMap(monthIndex); y = g[1].flatMap { Int($0) }
        } else {
            return ""
        }
        guard let year = y, (1000...2999).contains(year) else { return "" }
        if let month = m, !(1...12).contains(month) { m = nil; d = nil }
        if let day = d {
            if let month = m, day >= 1, day <= daysIn(month: month, year: year) {} else { d = nil }
        }
        guard let month = m else { return String(year) }
        guard let day = d else { return "\(year)-\(pad(month))" }
        return "\(year)-\(pad(month))-\(pad(day))"
    }

    private static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : String(n) }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    private static func parts(_ day: String) -> (y: Int, m: Int, d: Int) {
        let p = day.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        return (p.count > 0 ? p[0] : 0, p.count > 1 ? p[1] : 0, p.count > 2 ? p[2] : 0)
    }

    static func yearOf(_ day: String) -> String { String(day.prefix(4)) }

    private static func monthName(_ day: String) -> String {
        let m = parts(day).m
        return (1...12).contains(m) ? months[m - 1] : ""
    }

    private static func dayNumber(_ day: String) -> String {
        let d = parts(day).d
        return d != 0 ? String(d) : ""
    }

    /// "12 Mar", "Mar", "2023", or "—".
    static func shortDate(_ day: String) -> String {
        guard !day.isEmpty else { return "—" }
        let text = [dayNumber(day), monthName(day)].filter { !$0.isEmpty }.joined(separator: " ")
        return text.isEmpty ? yearOf(day) : text
    }

    /// "12 Mar 2023", or "Undated".
    static func fullDate(_ day: String) -> String {
        guard !day.isEmpty else { return "Undated" }
        return [dayNumber(day), monthName(day), yearOf(day)].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// "12.03.2023", "Mar 2023", "2023", or "Undated".
    static func dmy(_ day: String) -> String {
        let p = parts(day)
        if p.y == 0 { return "Undated" }
        if p.m == 0 { return String(p.y) }
        if p.d == 0 { return "\(months[p.m - 1]) \(p.y)" }
        return "\(pad(p.d)).\(pad(p.m)).\(p.y)"
    }

    // MARK: - Reading text

    /// "text with **bold** terms" as runs, bold or not. A stray unmatched `**` is dropped.
    static func parseRich(_ v: JSONValue?) -> [(text: String, bold: Bool)] {
        let s: String
        switch v {
        case nil, .null?: s = ""
        default: s = AnalysisJS.string(v)
        }
        return parseRich(s)
    }

    static func parseRich(_ s: String) -> [(text: String, bold: Bool)] {
        let c = Array(s.unicodeScalars)
        func isMarker(_ at: Int) -> Bool { at + 1 < c.count && c[at] == "*" && c[at + 1] == "*" }
        var pieces: [String] = []
        var start = 0
        var q = 0
        while q < c.count {
            if isMarker(q) {
                var k = q + 3
                var found: Int?
                while k + 1 < c.count {
                    if isMarker(k) { found = k; break }
                    k += 1
                }
                if let end = found {
                    pieces.append(String(String.UnicodeScalarView(c[start..<q])))
                    pieces.append(String(String.UnicodeScalarView(c[(q + 2)..<end])))
                    q = end + 2
                    start = q
                    continue
                }
            }
            q += 1
        }
        pieces.append(String(String.UnicodeScalarView(c[start..<c.count])))
        return pieces.enumerated().map { i, t in
            i % 2 == 1 ? (t, true) : (t.replacingOccurrences(of: "**", with: ""), false)
        }.filter { !$0.text.isEmpty }
    }

    /// The text without its bold marks.
    static func plain(_ s: String) -> String { parseRich(s).map(\.text).joined() }

    // MARK: - Showing

    /// Whether an entry matches a search.
    static func matches(_ e: Entry, _ query: String) -> Bool {
        let t = AnalysisJS.trim(query).lowercased()
        return t.isEmpty || e.hay.contains(t)
    }

    /// The entries under a category chip (`nil` is All) and a search.
    func shown(category: Category?, query: String) -> [Entry] {
        entries.filter { (category == nil || $0.cat == category) && Self.matches($0, query) }
    }

    struct YearRow: Equatable, Sendable, Identifiable {
        var year: String
        var rules: [Entry]
        var events: [Entry]
        var id: String { year }
    }

    /// One row per year, oldest first; undated entries in a last row.
    static func byYear(_ entries: [Entry]) -> [YearRow] {
        var rows: [YearRow] = []
        for e in entries {
            let y = yearOf(e.day).isEmpty ? "Undated" : yearOf(e.day)
            if rows.last?.year != y { rows.append(YearRow(year: y, rules: [], events: [])) }
            if e.cat == .rules { rows[rows.count - 1].rules.append(e) } else { rows[rows.count - 1].events.append(e) }
        }
        return rows
    }

    /// "Title | Number, Forum", each part only when known.
    var matterLine: String {
        let tail = [matter.number, matter.forum].filter { !$0.isEmpty }.joined(separator: ", ")
        return [matter.title, tail].filter { !$0.isEmpty }.joined(separator: " | ")
    }

    /// The events column's caption.
    var eventsHead: String {
        !ours.isEmpty && !other.isEmpty ? "\(ours), \(other), what followed" : "who did what, and what followed"
    }

    /// The matter number as a file name, or "List_of_Dates".
    var fileStem: String {
        let source = matter.number.isEmpty ? "List_of_Dates" : matter.number
        var out = ""
        var inRun = false
        for scalar in source.unicodeScalars {
            if scalar.isASCII, scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) {
                out.unicodeScalars.append(scalar)
                inRun = false
            } else if !inRun {
                out.append("-")
                inRun = true
            }
        }
        while out.hasPrefix("-") { out.removeFirst() }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "List_of_Dates" : out
    }

    /// The four categories' words, in the key's order.
    func words(_ c: Category) -> CategoryWords { cats[c]! }

    /// The chart as tab-separated text, for pasting.
    func asPlainText(_ shown: [Entry]? = nil) -> String {
        let entries = shown ?? self.entries
        func cellText(_ list: [Entry]) -> String {
            list.map { AnalysisJS.collapseSpaces("\($0.dateLabel): \(Self.plain($0.text))") }.joined(separator: " / ")
        }
        let head = "\(title)\n\(matterLine.isEmpty ? "" : "\(matterLine)\n")"
        let cols = "RULES, CONTRACT TERMS & ORDERS (as they came)\tYEAR\tEVENTS: \(eventsHead)"
        let rows = Self.byYear(entries).map { "\(cellText($0.rules))\t\($0.year)\t\(cellText($0.events))" }
        let key = Category.allCases.map { words($0).label }.joined(separator: " | ")
        let sumLine = inSum.isEmpty ? "" : "In sum: \(Self.plain(inSum))\n"
        return "\(head)\n\(cols)\n\(rows.joined(separator: "\n"))\n\nKey: \(key)\n\(sumLine)"
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func richHTML(_ s: String) -> String {
        parseRich(s).map { $0.bold ? "<b>\(esc($0.text))</b>" : esc($0.text) }.joined()
    }

    private static let wordTint: [Category: String] = [
        .rules: "#dce8f7", .ours: "#fdf0cf", .others: "#dcefe0", .adverse: "#f8dcdc",
    ]

    /// The chart as a page Word opens: the web's own export, byte for byte.
    func asWordHTML(_ shown: [Entry]? = nil) -> String {
        let entries = shown ?? self.entries
        func cell(_ list: [Entry]) -> String {
            list.map { "<p style=\"margin:0 0 3pt 0;background:\(Self.wordTint[$0.cat]!)\"><b>\(Self.esc($0.dateLabel)):</b> \(Self.richHTML($0.text))</p>" }.joined()
        }
        let rows = Self.byYear(entries).map {
            "<tr><td valign=\"top\">\(cell($0.rules))</td><td align=\"center\" valign=\"middle\" bgcolor=\"#2f3a6b\"><b><font color=\"#ffffff\">\(Self.esc($0.year))</font></b></td><td valign=\"top\">\(cell($0.events))</td></tr>"
        }.joined()
        let key = Category.allCases.map { "<span style=\"background:\(Self.wordTint[$0]!)\">&nbsp;\(Self.esc(words($0).label))&nbsp;</span>" }
            .joined(separator: " &nbsp;|&nbsp; ")
        return "<html xmlns:o=\"urn:schemas-microsoft-com:office:office\" xmlns:w=\"urn:schemas-microsoft-com:office:word\"><head><meta charset=\"utf-8\"><title>Event Chart</title>"
            + "<style>body{font-family:Cambria,serif;font-size:9pt}table{border-collapse:collapse;width:100%}td,th{border:1px solid #8a93b3;padding:3pt}</style></head><body>"
            + (matterLine.isEmpty ? "" : "<p>\(Self.esc(matterLine))</p>")
            + "<table><tr><th colspan=\"3\" bgcolor=\"#2f3a6b\"><font color=\"#ffffff\">\(Self.esc(title))</font></th></tr>"
            + "<tr bgcolor=\"#e6e9f4\"><th width=\"46%\">RULES, CONTRACT TERMS &amp; ORDERS (as they came)</th><th width=\"6%\">YEAR</th><th width=\"48%\">EVENTS: \(Self.esc(eventsHead))</th></tr>\(rows)</table>"
            + "<p><b>Key:</b> \(key)</p>\(inSum.isEmpty ? "" : "<p><b>In sum:</b> \(Self.richHTML(inSum))</p>")</body></html>"
    }

    /// What lies between `<body>` and `</body>` of `asWordHTML` — the part a document builder
    /// that takes a fragment needs.
    func wordBody(_ shown: [Entry]? = nil) -> String {
        let html = asWordHTML(shown)
        guard let open = html.range(of: "<body>"), let close = html.range(of: "</body>", options: .backwards)
        else { return html }
        return String(html[open.upperBound..<close.lowerBound])
    }

    struct TimelineItem: Equatable, Sendable, Identifiable {
        /// A year heading when `entry` is `nil`.
        var year: String?
        var entry: Entry?
        var next: Bool
        var id: String { entry.map { "e-\($0.id)" } ?? "y-\(year ?? "")" }
    }

    /// The timeline: upcoming entries first, then the rest newest first with a heading at each
    /// change of year, undated last.
    var timelineItems: [TimelineItem] {
        var out: [TimelineItem] = entries.filter(\.upcoming).map { TimelineItem(year: nil, entry: $0, next: true) }
        let rest = entries.filter { !$0.upcoming }
        let order = Array(rest.filter { !$0.day.isEmpty }.reversed()) + rest.filter { $0.day.isEmpty }
        var year: String?
        for e in order {
            let y = Self.yearOf(e.day).isEmpty ? "Undated" : Self.yearOf(e.day)
            if y != year { out.append(TimelineItem(year: y, entry: nil, next: false)); year = y }
            out.append(TimelineItem(year: nil, entry: e, next: false))
        }
        return out
    }

    /// The timeline row's date: the day and month, or for an upcoming entry its full day less
    /// the year (which is written under it).
    static func timelineDate(_ e: Entry, next: Bool) -> String {
        guard next else { return shortDate(e.day) }
        let full = fullDate(e.day)
        if let r = full.range(of: #" [0-9]{4}$"#, options: .regularExpression) { return String(full[..<r.lowerBound]) }
        return full
    }

    // MARK: - Words the page uses

    static let noDates =
        "No dates were found in these documents. If they are scanned, check that the pages are readable, or add the papers that carry the dates and start over."

    /// "Arora", "our side": who the summary strip says acted for us.
    var oursLine: String { ours.isEmpty ? "by our side" : "by \(ours)" }

    /// "2021 → 2025", or one year.
    var spanLine: String? {
        guard !sum.from.isEmpty else { return nil }
        return sum.from == sum.to ? sum.from : "\(sum.from) → \(sum.to)"
    }
}
