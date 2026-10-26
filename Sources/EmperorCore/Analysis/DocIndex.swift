import Foundation

/// One cell of a Doc Index row. `nil` in a row is an empty cell.
enum DocIndexCell: Equatable, Sendable {
    case text(String)
    case number(Double)
    case tags([String])

    var textValue: String? {
        if case .text(let s) = self { return s }
        return nil
    }

    var numberValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    /// The cell as the web's `String(v)` would write it.
    var plain: String {
        switch self {
        case .text(let s): return s
        case .number(let n): return AnalysisJS.string(n)
        case .tags(let t): return t.joined(separator: ",")
        }
    }

    /// Whether the web's `v == null || v === ''` holds.
    var isBlank: Bool { self == .text("") }
}

/// A Doc Index: one table of every document, whose columns the AI chose for this bundle
/// (`src/pages/analysis/samples/docIndex.js`).
///
/// `normalise` is the port of the web's `normalizeIndex`: it never trusts the answer — unknown
/// column types become text, numbers, dates and tags are coerced, long text is capped, rows get
/// their own ids — and gives `nil` only when there is nothing to draw.
struct DocIndex: Equatable, Sendable {

    enum ColumnType: String, CaseIterable, Sendable {
        case text, long, date, badge, number, amount, tags, pages, link

        /// Numbers sit at the right of their column.
        var isNumeric: Bool { self == .number || self == .pages || self == .amount }

        fileprivate var defaultWidth: Double {
            switch self {
            case .text: return 220
            case .long: return 340
            case .date: return 120
            case .badge: return 140
            case .number: return 90
            case .amount: return 130
            case .tags: return 260
            case .pages: return 90
            case .link: return 200
            }
        }
    }

    struct Column: Equatable, Sendable, Identifiable {
        var key: String
        var label: String
        var type: ColumnType
        var width: Double
        var description: String
        var pin: Bool
        var strong: Bool
        var total: Bool
        /// The colour a badge value takes, as the AI named it (`accent`, `info`, `ok`, `warn`,
        /// `danger`, `neutral`).
        var tones: [String: String]?
        /// The order a badge column sorts in; `nil` entries are values that were not text.
        var order: [String?]?
        var id: String { key }
    }

    struct Flag: Equatable, Sendable {
        var key: String
        var nonEmpty: Bool
        /// The values that flag a row, when `nonEmpty` is false.
        var values: [JSONValue]?
        var label: String?
    }

    struct Row: Equatable, Sendable, Identifiable {
        /// `r0`, `r1`… in the order the rows came.
        var id: String
        var cells: [String: DocIndexCell]

        subscript(_ key: String) -> DocIndexCell? { cells[key] }
    }

    var id: String
    var label: String
    var filterKey: String?
    var filterLabel: String
    var flag: Flag?
    var pagesKey: String?
    var rationale: String
    var columns: [Column]
    var rows: [Row]

    // MARK: - Normalising

    private static let maxText = 4000

    private static func clip(_ s: String) -> String {
        AnalysisJS.length(s) > maxText ? AnalysisJS.prefix(s, maxText) + "…" : s
    }

    /// `toText(v)`.
    static func toText(_ v: JSONValue?) -> String? {
        switch v {
        case nil, .null?: return nil
        case .string(let s)?:
            let t = AnalysisJS.trim(s)
            return t.isEmpty ? nil : clip(t)
        case .number(let n)?: return AnalysisJS.string(n)
        case .bool(let b)?: return b ? "true" : "false"
        case .array(let items)?:
            let joined = items.map { item -> String in
                switch item {
                case .null, .object, .array: return ""
                default: return AnalysisJS.string(item)
                }
            }.filter { !$0.isEmpty }.joined(separator: ", ")
            return toText(.string(joined))
        case .object?: return nil
        }
    }

    /// `toNum(v)`: a number, or a figure written with ₹, commas, "Rs." or "INR".
    static func toNumber(_ v: JSONValue?) -> Double? {
        switch v {
        case nil, .null?, .bool?: return nil
        case .string(let s)? where s.isEmpty: return nil
        case .number(let n)?: return n.isFinite ? n : nil
        default:
            let n = AnalysisJS.number(stripCurrency(AnalysisJS.string(v)))
            return n.isFinite ? n : nil
        }
    }

    /// `s.replace(/[₹,\s]|rs\.?|inr/gi, '')`.
    private static func stripCurrency(_ s: String) -> String {
        let scalars = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        func lower(_ k: Int) -> Unicode.Scalar? {
            k < scalars.count ? Unicode.Scalar(String(scalars[k]).lowercased()) : nil
        }
        while i < scalars.count {
            let c = scalars[i]
            if c == "₹" || c == "," || AnalysisJS.isSpace(c) { i += 1; continue }
            if lower(i) == "r", lower(i + 1) == "s" {
                i += 2
                if i < scalars.count, scalars[i] == "." { i += 1 }
                continue
            }
            if lower(i) == "i", lower(i + 1) == "n", lower(i + 2) == "r" { i += 3; continue }
            out.append(c)
            i += 1
        }
        return String(out)
    }

    /// `toTags(v)`: a list, or a string split at `;`, a newline or a comma not followed by a digit.
    static func toTags(_ v: JSONValue?) -> [String]? {
        var pieces: [JSONValue] = []
        switch v {
        case .array(let items)?: pieces = items
        case .string(let s)?: pieces = splitTags(s).map { .string($0) }
        default: break
        }
        let out = pieces.map { item -> String in
            switch item {
            case .string(let s): return AnalysisJS.trim(s)
            case .number(let n): return AnalysisJS.trim(AnalysisJS.string(n))
            default: return ""
            }
        }.filter { !$0.isEmpty }.map { AnalysisJS.prefix($0, 80) }
        return out.isEmpty ? nil : Array(out.prefix(40))
    }

    private static func splitTags(_ s: String) -> [String] {
        let scalars = Array(s.unicodeScalars)
        var parts: [String] = []
        var current = String.UnicodeScalarView()
        for (i, c) in scalars.enumerated() {
            let nextIsDigit = i + 1 < scalars.count && ("0"..."9").contains(scalars[i + 1])
            if c == ";" || c == "\n" || (c == "," && !nextIsDigit) {
                parts.append(String(current))
                current = String.UnicodeScalarView()
            } else {
                current.append(c)
            }
        }
        parts.append(String(current))
        return parts
    }

    private static func toCell(_ type: ColumnType, _ v: JSONValue?) -> DocIndexCell? {
        switch type {
        case .number, .amount, .pages: return toNumber(v).map(DocIndexCell.number)
        case .tags: return toTags(v).map(DocIndexCell.tags)
        default: return toText(v).map(DocIndexCell.text)
        }
    }

    private static func isFlagWord(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["issue", "flag", "risk", "concern", "watch", "defect", "gap", "problem"]
            .contains { lower.contains($0) }
    }

    /// The server's `result` (or a stored one) as an index, or `nil` when there is nothing to
    /// draw: not an object, no columns, or rows that are not a list.
    static func normalise(_ raw: JSONValue?, fallbackID: String = "results") -> DocIndex? {
        guard case .object(let r)? = raw,
              case .array(let rawColumns)? = r["columns"],
              case .array(let rawRows)? = r["rows"]
        else { return nil }

        var seen = Set<String>()
        var columns: [Column] = []
        for (i, item) in rawColumns.enumerated() {
            guard AnalysisJS.isObjectLike(item) else { continue }
            let c = AnalysisJS.fields(item)
            var key = "col\(i)"
            if case .string(let k)? = c["key"], !k.isEmpty { key = k }
            if seen.contains(key) { continue }
            seen.insert(key)
            let type = c["type"]?.stringValue.flatMap(ColumnType.init(rawValue:)) ?? .text
            let w = AnalysisJS.number(c["width"])
            var tones: [String: String]?
            if AnalysisJS.isObjectLike(c["tones"]) {
                tones = AnalysisJS.fields(c["tones"]).compactMapValues { $0.stringValue }
            }
            var order: [String?]?
            if case .array(let items)? = c["order"] { order = items.map(\.stringValue) }
            let total: Bool
            if let t = c["total"], t != .null { total = AnalysisJS.truthy(t) } else { total = type == .pages }
            columns.append(Column(
                key: key, label: toText(c["label"]) ?? key, type: type,
                width: w.isFinite ? min(600, max(70, w)) : type.defaultWidth,
                description: toText(c["description"]) ?? "",
                pin: AnalysisJS.truthy(c["pin"]), strong: AnalysisJS.truthy(c["strong"]),
                total: total, tones: tones, order: order))
        }
        guard !columns.isEmpty else { return nil }
        if !columns.contains(where: \.strong) {
            let at = columns.firstIndex { $0.type == .text } ?? 0
            columns[at].strong = true
        }
        if !columns.contains(where: \.pin), let at = columns.firstIndex(where: \.strong), at < 2 {
            columns[at].pin = true
            if at == 1, columns[0].type == .number { columns[0].pin = true }
        }

        let rows: [Row] = rawRows.compactMap { item -> [String: JSONValue]? in
            if case .object(let o) = item { return o }
            return nil
        }.enumerated().map { i, raw in
            var cells: [String: DocIndexCell] = [:]
            for c in columns { cells[c.key] = toCell(c.type, raw[c.key]) }
            return Row(id: "r\(i)", cells: cells)
        }

        func distinct(_ c: Column) -> Int {
            var values: [DocIndexCell] = []
            for row in rows { if let v = row[c.key], !values.contains(v) { values.append(v) } }
            return values.count
        }
        let rawFilterKey = r["filterKey"]?.stringValue
        let filterColumn = columns.first { $0.key == rawFilterKey }
            ?? AnalysisJS.stableSorted(
                columns.filter { $0.type == .badge && distinct($0) > 1 && distinct($0) <= 14 }
            ) { distinct($0) - distinct($1) }.first

        let rawFlag = AnalysisJS.fields(r["flag"])
        let rawFlagKey = rawFlag["key"]
        let flagColumn = columns.first { rawFlagKey != nil && $0.key == rawFlagKey?.stringValue }
            ?? columns.first { ($0.type == .long || $0.type == .text) && isFlagWord("\($0.key) \($0.label)") }
        var flag: Flag?
        if AnalysisJS.truthy(rawFlagKey) {
            var values: [JSONValue]?
            if case .array(let items)? = rawFlag["in"] { values = items }
            flag = Flag(
                key: AnalysisJS.string(rawFlagKey), nonEmpty: AnalysisJS.truthy(rawFlag["nonEmpty"]),
                values: values, label: rawFlag["label"]?.stringValue)
        } else if let flagColumn {
            flag = Flag(key: flagColumn.key, nonEmpty: true, values: nil, label: "with something to watch")
        }

        let filterLabel = AnalysisJS.truthy(r["filterLabel"])
            ? AnalysisJS.string(r["filterLabel"]) : (filterColumn?.label ?? "")
        return DocIndex(
            id: AnalysisJS.truthy(r["id"]) ? AnalysisJS.string(r["id"]) : fallbackID,
            label: AnalysisJS.truthy(r["label"]) ? AnalysisJS.string(r["label"]) : "Your documents",
            filterKey: filterColumn?.key,
            filterLabel: filterLabel,
            flag: flag,
            pagesKey: columns.first { $0.type == .pages }?.key,
            rationale: r["rationale"]?.stringValue ?? "",
            columns: columns, rows: rows)
    }

    // MARK: - Formatting

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "3 Feb 2024" for an ISO date; anything else as it was written.
    static func fmtDate(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "" }
        let s = Array(iso.unicodeScalars)
        func digits(_ range: Range<Int>) -> Int? {
            guard range.upperBound <= s.count else { return nil }
            var n = 0
            for i in range {
                guard ("0"..."9").contains(s[i]) else { return nil }
                n = n * 10 + Int(s[i].value - 48)
            }
            return n
        }
        guard s.count >= 10, let y = digits(0..<4), s[4] == "-", let m = digits(5..<7), s[7] == "-",
              let d = digits(8..<10), (1...12).contains(m)
        else { return iso }
        return "\(d) \(months[m - 1]) \(String(format: "%04d", y))"
    }

    /// "₹4,82,00,000": Indian grouping, as lawyers write it.
    static func fmtINR(_ n: Double?) -> String {
        guard let n else { return "" }
        let s = AnalysisJS.string(AnalysisJS.round(n))
        guard s.count > 3 else { return "₹\(s)" }
        let rest = Array(s.dropLast(3))
        var out = ""
        for (p, c) in rest.enumerated() {
            if p > 0, isWord(rest[p - 1]) == isWord(c), c.isASCII, c.isNumber {
                var run = 0
                var k = p
                while k < rest.count, rest[k].isASCII, rest[k].isNumber { run += 1; k += 1 }
                if run >= 2, run % 2 == 0 { out.append(",") }
            }
            out.append(c)
        }
        return "₹\(out),\(s.suffix(3))"
    }

    private static func isWord(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber || c == "_")
    }

    /// "12 pp", "1 p".
    static func fmtPages(_ n: Double?) -> String {
        guard let n else { return "" }
        return "\(AnalysisJS.string(n)) \(n == 1 ? "p" : "pp")"
    }

    /// The plain text of one cell, for searching and for the CSV file.
    static func cellText(_ column: Column, _ row: Row) -> String {
        guard let v = row[column.key], !v.isBlank else { return "" }
        switch (column.type, v) {
        case (.date, .text(let s)): return fmtDate(s)
        case (.amount, .number(let n)): return fmtINR(n)
        case (.pages, .number(let n)): return fmtPages(n)
        case (.tags, .tags(let t)): return t.joined(separator: "; ")
        default: return v.plain
        }
    }

    /// A column's sort, empty cells last whichever way.
    static func compareCells(_ column: Column, _ a: Row, _ b: Row, descending: Bool) -> Int {
        let x = a[column.key].flatMap { $0.isBlank ? nil : $0 }
        let y = b[column.key].flatMap { $0.isBlank ? nil : $0 }
        guard let x, let y else {
            if x == nil, y == nil { return 0 }
            return x == nil ? 1 : -1
        }
        var r: Int
        switch column.type {
        case .number, .pages, .amount:
            let d = (x.numberValue ?? .nan) - (y.numberValue ?? .nan)
            r = d < 0 ? -1 : d > 0 ? 1 : 0
        case .date:
            let p = x.plain, q = y.plain
            r = p.utf16.lexicographicallyPrecedes(q.utf16) ? -1 : (q.utf16.lexicographicallyPrecedes(p.utf16) ? 1 : 0)
        case .tags:
            let lx: Int, ly: Int
            if case .tags(let t) = x { lx = t.count } else { lx = AnalysisJS.length(x.plain) }
            if case .tags(let t) = y { ly = t.count } else { ly = AnalysisJS.length(y.plain) }
            r = lx - ly
        default:
            if let order = column.order {
                let ix = order.firstIndex { $0 == x.textValue && $0 != nil } ?? -1
                let iy = order.firstIndex { $0 == y.textValue && $0 != nil } ?? -1
                r = ix - iy
            } else {
                r = AnalysisJS.localeCompare(x.plain, y.plain)
            }
        }
        return descending ? -r : r
    }

    /// Whether a row carries the index's flag.
    func isFlagged(_ row: Row) -> Bool {
        guard let flag else { return false }
        let v = row[flag.key]
        if flag.nonEmpty { return v != nil && v?.isBlank == false }
        guard let values = flag.values else { return false }
        return values.contains { value in
            switch (value, v) {
            case (.null, nil): return true
            case (.string(let s), .text(let t)?): return s == t
            case (.number(let n), .number(let m)?): return n == m
            default: return false
            }
        }
    }

    var flaggedCount: Int? { flag.map { _ in rows.filter(isFlagged).count } }

    /// The pages in every document, when there is a pages column.
    var allPages: Double? {
        pagesKey.map { key in rows.reduce(0) { $0 + ($1[key]?.numberValue ?? 0) } }
    }

    /// The badge values of the filter column with how many rows carry each, first seen first.
    var filterCounts: [(value: String, count: Int)] {
        guard let filterKey else { return [] }
        var out: [(value: String, count: Int)] = []
        for row in rows {
            guard let v = row[filterKey] else { continue }
            let key = v.plain
            if let i = out.firstIndex(where: { $0.value == key }) { out[i].count += 1 }
            else { out.append((key, 1)) }
        }
        return out
    }

    /// The colour a badge value takes: the AI's own, else high/critical/urgent red, medium amber.
    static func tone(_ column: Column, _ value: String) -> String {
        if let given = column.tones?[value], !given.isEmpty { return given }
        let v = value.lowercased()
        if v.hasPrefix("high") || v.hasPrefix("critical") || v.hasPrefix("urgent") { return "danger" }
        if v.hasPrefix("medium") { return "warn" }
        return "neutral"
    }

    /// The column a row is named by.
    var strongColumn: Column {
        columns.first(where: \.strong) ?? (columns.count > 1 ? columns[1] : columns[0])
    }

    /// The rows shown for a search, a filter value and a sort, in that order.
    func rows(query: String, filter: String?, sortKey: String?, descending: Bool) -> [Row] {
        let q = AnalysisJS.trim(query).lowercased()
        var out = rows.filter { row in
            if let filter, let filterKey, row[filterKey]?.plain != filter { return false }
            if q.isEmpty { return true }
            return columns.map { Self.cellText($0, row) }.joined(separator: "\n").lowercased().contains(q)
        }
        if let sortKey, let column = columns.first(where: { $0.key == sortKey }) {
            out = AnalysisJS.stableSorted(out) { Self.compareCells(column, $0, $1, descending: descending) }
        }
        return out
    }

    /// The sums under the table for each total column still shown, over the rows shown.
    func totals(shown: [Row], hidden: Set<String> = []) -> [(column: Column, sum: Double)] {
        columns.filter { $0.total && !hidden.contains($0.key) && $0.type.isNumeric }.map { column in
            (column, shown.reduce(0) { $0 + ($1[column.key]?.numberValue ?? 0) })
        }
    }

    /// The footer's words for one total: "₹4,82,000 amount" or "124 pages".
    static func totalText(_ column: Column, _ sum: Double) -> String {
        column.type == .amount ? "\(fmtINR(sum)) \(column.label.lowercased())" : "\(AnalysisJS.string(sum)) pages"
    }

    /// One CSV of the given columns and rows: a byte-order mark so Excel keeps the rupee sign,
    /// CRLF lines, numbers bare, and any cell that Excel would run as a formula defused.
    static func toCSV(columns: [Column], rows: [Row]) -> String {
        func quote(_ t: String) -> String {
            var s = t
            if let first = s.unicodeScalars.first, ["=", "+", "-", "@", "\t", "\r"].contains(first) {
                s = "'" + s
            }
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let head = columns.map { quote($0.label) }.joined(separator: ",")
        let body = rows.map { row in
            columns.map { c -> String in
                guard let v = row[c.key] else { return "" }
                if c.type.isNumeric { return v.plain }
                return quote(cellText(c, row))
            }.joined(separator: ",")
        }
        return "\u{FEFF}" + ([head] + body).joined(separator: "\r\n") + "\r\n"
    }

    /// The table's footer note when sorted, or the hint when not.
    static func sortLine(_ column: Column?, descending: Bool) -> String {
        guard let column else { return "Tap a heading to sort. Tap a row to read more." }
        return "Sorted by \(column.label), \(descending ? "high to low" : "low to high")"
    }

    /// The empty table's title.
    func emptyTitle(query: String) -> String {
        if rows.isEmpty { return "No documents were found to index" }
        let q = AnalysisJS.trim(query)
        return q.isEmpty ? "No documents match these filters" : "No documents match “\(q)”"
    }

    static let emptyHint =
        "Try a shorter word, a party name, or a date. Search looks at every column, including hidden ones."
}
