import Foundation

/// A Devil's Advocate report: where a case is weak, what the other side will ask, what is missing,
/// which authorities cut against it, and a checklist — the page's one object
/// (`src/pages/analysis/samples/devilsAdvocate.js`).
///
/// `normalise` is the port of the web's `normaliseReport`, so a sloppy model answer — a missing
/// field, an unknown label, a duplicate id — draws the same report here as there. Every number on
/// the page is derived from this value, never sent.
struct DevilsAdvocateReport: Equatable, Sendable {

    enum Severity: String, CaseIterable, Sendable {
        case serious, moderate, minor

        var label: String {
            switch self {
            case .serious: return "Serious"
            case .moderate: return "Moderate"
            case .minor: return "Minor"
            }
        }

        /// What each band means, as the donut's legend says it.
        var hint: String {
            switch self {
            case .serious: return "Could lose or stall the case"
            case .moderate: return "Could cost money or credibility"
            case .minor: return "Easy to fix, awkward if ignored"
            }
        }

        /// The weight a spot adds to its category's bar.
        var weight: Int {
            switch self {
            case .serious: return 3
            case .moderate: return 2
            case .minor: return 1
            }
        }
    }

    enum Readiness: String, CaseIterable, Sendable {
        case ready, work, gap

        var label: String {
            switch self {
            case .ready: return "Ready"
            case .work: return "Needs work"
            case .gap: return "Gap"
            }
        }
    }

    struct Matter: Equatable, Sendable {
        var title = ""
        var forum = ""
        var number = ""
        var client = ""
        var date = ""
    }

    struct WeakSpot: Equatable, Sendable, Identifiable {
        var id: Int
        var severity: Severity
        var category: String
        var likelihood: Int
        var impact: Int
        var title: String
        var why: String
        var `where`: [String]
        var say: String
        var fix: String
    }

    struct Question: Equatable, Sendable {
        var q: String
        var why: String
        var answer: String
        var readiness: Readiness
        var spot: Int?
    }

    struct DocGap: Equatable, Sendable {
        var doc: String
        var who: String
        var how: String
        var when: String
        var spot: Int?
    }

    struct Authority: Equatable, Sendable {
        var name: String
        var court: String
        var year: String
        var pinCite: String
        var holds: String
        var distinguish: String
        var against: Int?
        var verify: Bool
    }

    struct ChecklistItem: Equatable, Sendable, Identifiable {
        var id: String
        var text: String
        var done: Bool
    }

    var matter: Matter
    var exposureScore: Int
    var oneMinute: [String]
    var weakSpots: [WeakSpot]
    var questions: [Question]
    var docGaps: [DocGap]
    var authorities: [Authority]
    var checklist: [ChecklistItem]

    // MARK: - Vocabulary

    /// The seven categories the page knows by name, in the order the bars list them.
    static let categories: [(key: String, label: String)] = [
        ("limitation", "Limitation"),
        ("jurisdiction", "Jurisdiction"),
        ("pleadings", "Pleadings"),
        ("evidence", "Evidence"),
        ("contract", "Contract terms"),
        ("relief", "Relief and quantum"),
        ("procedure", "Procedure"),
    ]

    private static let severityWords: [String: Severity] = [
        "serious": .serious, "high": .serious, "critical": .serious, "severe": .serious,
        "major": .serious, "grave": .serious,
        "moderate": .moderate, "medium": .moderate, "med": .moderate, "mid": .moderate,
        "minor": .minor, "low": .minor, "trivial": .minor, "slight": .minor,
    ]

    private static let readinessWords: [String: Readiness] = [
        "ready": .ready, "done": .ready, "good": .ready, "strong": .ready,
        "work": .work, "needs work": .work, "partial": .work, "moderate": .work, "medium": .work,
        "gap": .gap, "missing": .gap, "weak": .gap, "none": .gap,
    ]

    private static let scaleWords: [String: Int] = [
        "very low": 1, "low": 1, "medium-low": 2, "low-medium": 2, "medium": 3, "moderate": 3,
        "medium-high": 4, "high-medium": 4, "high": 4, "very high": 5, "certain": 5,
        "critical": 5, "severe": 5,
    ]

    // MARK: - Reading a value the way the page does

    /// `str(v)`: a string trimmed, a finite number as text, anything else empty.
    static func str(_ v: JSONValue?) -> String {
        switch v {
        case .string(let s)?: return AnalysisJS.trim(s)
        case .number(let n)? where n.isFinite: return AnalysisJS.string(n)
        default: return ""
        }
    }

    private static func list(_ v: JSONValue?) -> [JSONValue] {
        if case .array(let items)? = v { return items }
        return []
    }

    private static func strList(_ v: JSONValue?) -> [String] {
        let items: [JSONValue]
        switch v {
        case .array(let a)?: items = a
        case .string?: items = [v!]
        default: items = []
        }
        return items.map { str($0) }.filter { !$0.isEmpty }
    }

    /// `posInt(v)`: a positive whole number, from a number or a "#3"-style string; `nil` else.
    static func posInt(_ v: JSONValue?) -> Int? {
        let n: Double
        switch v {
        case .string(let s)?:
            n = AnalysisJS.number(s.hasPrefix("#") ? String(s.dropFirst()) : s)
        case .number(let d)?:
            n = d
        default:
            return nil
        }
        guard n.isFinite, n >= 1 else { return nil }
        return Int(AnalysisJS.round(n))
    }

    private static func objects(_ v: JSONValue?) -> [[String: JSONValue]] {
        list(v).compactMap { item in
            if case .object(let o) = item { return o }
            return nil
        }
    }

    static func normaliseSeverity(_ v: JSONValue?) -> Severity {
        severityWords[str(v).lowercased()] ?? .moderate
    }

    static func normaliseReadiness(_ v: JSONValue?) -> Readiness {
        readinessWords[str(v).lowercased()] ?? .work
    }

    static func normaliseScale(_ v: JSONValue?) -> Int {
        var n: Double?
        switch v {
        case .number(let d)?:
            n = d
        case .string(let s)?:
            let value = AnalysisJS.number(s)
            if !AnalysisJS.trim(s).isEmpty, !value.isNaN { n = value }
        default:
            break
        }
        if let n, n.isFinite { return Int(min(5, max(1, AnalysisJS.round(n)))) }
        return scaleWords[str(v).lowercased()] ?? 3
    }

    static func normaliseCategory(_ v: JSONValue?) -> String {
        var out = String.UnicodeScalarView()
        var inRun = false
        for scalar in str(v).lowercased().unicodeScalars {
            if AnalysisJS.isSpace(scalar) || scalar == "_" {
                if !inRun { out.append("-") }
                inRun = true
            } else {
                out.append(scalar)
                inRun = false
            }
        }
        let key = String(out)
        return key.isEmpty ? "other" : key
    }

    /// The name a category goes by: one of the seven, or the key in title case.
    static func categoryLabel(_ key: String) -> String {
        if let hit = categories.first(where: { $0.key == key }) { return hit.label }
        let label = titleCase(key)
        return label.isEmpty ? "Other" : label
    }

    /// `k.replace(/[_-]+/g, ' ').replace(/\s+/g, ' ').trim().replace(/\b\w/g, upper)`.
    private static func titleCase(_ key: String) -> String {
        let spaced = String(String.UnicodeScalarView(key.unicodeScalars.map { $0 == "_" || $0 == "-" ? " " : $0 }))
        let collapsed = AnalysisJS.trim(AnalysisJS.collapseSpaces(spaced))
        var out = String.UnicodeScalarView()
        var previousIsWord = false
        for scalar in collapsed.unicodeScalars {
            let isWord = scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || scalar == "_")
            if isWord, !previousIsWord, ("a"..."z").contains(scalar) {
                out.append(Unicode.Scalar(scalar.value - 32)!)
            } else {
                out.append(scalar)
            }
            previousIsWord = isWord
        }
        return String(out)
    }

    // MARK: - Normalising

    /// The server's `result` (or a stored one) as a clean report, or `nil` when it is not an
    /// object at all.
    static func normalise(_ raw: JSONValue?) -> DevilsAdvocateReport? {
        guard case .object(let r)? = raw else { return nil }

        var used = Set<Int>()
        var remap: [Int: Int] = [:]
        let rawSpots = objects(r["weakSpots"])
        let firstPass: [(spot: [String: JSONValue], id: Int?)] = rawSpots.map { s in
            var id = posInt(s["id"])
            if let given = id, used.contains(given) { id = nil }
            if let id { used.insert(id) }
            return (s, id)
        }
        var spots: [WeakSpot] = []
        for (i, entry) in firstPass.enumerated() {
            var nid: Int
            if let id = entry.id {
                nid = id
            } else {
                nid = i + 1
                while used.contains(nid) { nid += 1 }
                used.insert(nid)
            }
            if let id = entry.id, remap[id] == nil { remap[id] = nid }
            let s = entry.spot
            let title = str(s["title"])
            spots.append(WeakSpot(
                id: nid, severity: normaliseSeverity(s["severity"]),
                category: normaliseCategory(s["category"]),
                likelihood: normaliseScale(s["likelihood"]), impact: normaliseScale(s["impact"]),
                title: title.isEmpty ? "Weak spot \(nid)" : title,
                why: str(s["why"]), where: strList(s["where"]), say: str(s["say"]), fix: str(s["fix"])))
        }
        let order = Severity.allCases
        spots = AnalysisJS.stableSorted(spots) {
            order.firstIndex(of: $0.severity)! - order.firstIndex(of: $1.severity)!
        }
        func ref(_ v: JSONValue?) -> Int? { posInt(v).flatMap { remap[$0] } }

        let m = AnalysisJS.fields(r["matter"])
        var score: Int?
        if case .number(let n)? = r["exposureScore"], n.isFinite {
            score = Int(min(100, max(0, AnalysisJS.round(n))))
        }
        var seenIDs = Set<String>()
        let checklist: [ChecklistItem] = objects(r["checklist"]).enumerated().map { i, c in
            var id = str(c["id"])
            if id.isEmpty { id = "c\(i + 1)" }
            while seenIDs.contains(id) { id += "_" }
            seenIDs.insert(id)
            return ChecklistItem(id: id, text: str(c["text"]), done: c["done"] == .bool(true))
        }.filter { !$0.text.isEmpty }

        return DevilsAdvocateReport(
            matter: Matter(
                title: str(m["title"]), forum: str(m["forum"]), number: str(m["number"]),
                client: str(m["client"]), date: str(m["date"])),
            exposureScore: score ?? deriveExposure(spots),
            oneMinute: strList(r["oneMinute"]),
            weakSpots: spots,
            questions: objects(r["questions"]).map { q in
                Question(
                    q: str(q["q"]), why: str(q["why"]), answer: str(q["answer"]),
                    readiness: normaliseReadiness(q["readiness"]), spot: ref(q["spot"]))
            }.filter { !$0.q.isEmpty },
            docGaps: objects(r["docGaps"]).map { d in
                DocGap(
                    doc: str(d["doc"]), who: str(d["who"]), how: str(d["how"]),
                    when: str(d["when"]), spot: ref(d["spot"]))
            }.filter { !$0.doc.isEmpty },
            authorities: objects(r["authorities"]).map { a in
                Authority(
                    name: str(a["name"]), court: str(a["court"]), year: str(a["year"]),
                    pinCite: str(a["pinCite"]), holds: str(a["holds"]),
                    distinguish: str(a["distinguish"]), against: ref(a["against"]),
                    verify: a["verify"] == .bool(true) || a["verify"] == .string("true"))
            }.filter { !$0.name.isEmpty },
            checklist: checklist)
    }

    /// With no score from the server: the worst spot counts most, the average the rest.
    private static func deriveExposure(_ spots: [WeakSpot]) -> Int {
        guard !spots.isEmpty else { return 0 }
        let r = spots.map { Double($0.likelihood * $0.impact) / 25 }
        let worst = r.max()!
        let mean = r.reduce(0, +) / Double(r.count)
        return Int(AnalysisJS.round(100 * (0.6 * worst + 0.4 * mean)))
    }

    // MARK: - Derived

    struct SeverityCounts: Equatable, Sendable {
        var serious = 0
        var moderate = 0
        var minor = 0

        subscript(_ s: Severity) -> Int {
            switch s {
            case .serious: return serious
            case .moderate: return moderate
            case .minor: return minor
            }
        }
    }

    var countBySeverity: SeverityCounts {
        var out = SeverityCounts()
        for s in weakSpots {
            switch s.severity {
            case .serious: out.serious += 1
            case .moderate: out.moderate += 1
            case .minor: out.minor += 1
            }
        }
        return out
    }

    /// "Low", "Moderate" or "High".
    static func exposureBand(_ score: Int) -> String {
        score < 34 ? "Low" : score < 67 ? "Moderate" : "High"
    }

    var exposureBand: String { Self.exposureBand(exposureScore) }

    /// "3 serious, 2 moderate, 1 minor", or that nothing was found.
    var countsLine: String {
        guard !weakSpots.isEmpty else { return "No weak spots found in the papers" }
        let c = countBySeverity
        return "\(c.serious) serious, \(c.moderate) moderate, \(c.minor) minor"
    }

    struct CategoryRow: Equatable, Sendable, Identifiable {
        var key: String
        var label: String
        var by: SeverityCounts
        var count: Int
        var weight: Int
        var id: String { key }
    }

    /// Per category that has a spot: how many of each severity and a weight to size the bar,
    /// heaviest first.
    var categoryRows: [CategoryRow] {
        var keys = Self.categories.map(\.key)
        for s in weakSpots where !keys.contains(s.category) { keys.append(s.category) }
        let rows: [CategoryRow] = keys.map { key in
            let mine = weakSpots.filter { $0.category == key }
            var by = SeverityCounts()
            for s in mine {
                switch s.severity {
                case .serious: by.serious += 1
                case .moderate: by.moderate += 1
                case .minor: by.minor += 1
                }
            }
            return CategoryRow(
                key: key, label: Self.categoryLabel(key), by: by, count: mine.count,
                weight: mine.reduce(0) { $0 + $1.severity.weight })
        }.filter { $0.count > 0 }
        return AnalysisJS.stableSorted(rows) { $1.weight - $0.weight }
    }

    struct MatrixCell: Equatable, Sendable, Identifiable {
        var likelihood: Int
        var impact: Int
        var score: Int { likelihood * impact }
        var spots: [WeakSpot]
        var id: String { "\(likelihood)-\(impact)" }
    }

    /// The 5×5 grid, top row (impact 5) first, likelihood rising left to right.
    var matrixCells: [MatrixCell] {
        var cells: [MatrixCell] = []
        for impact in stride(from: 5, through: 1, by: -1) {
            for likelihood in 1...5 {
                cells.append(MatrixCell(
                    likelihood: likelihood, impact: impact,
                    spots: weakSpots.filter { $0.likelihood == likelihood && $0.impact == impact }))
            }
        }
        return cells
    }

    struct ReadinessCounts: Equatable, Sendable {
        var all = 0
        var ready = 0
        var work = 0
        var gap = 0

        subscript(_ r: Readiness?) -> Int {
            switch r {
            case nil: return all
            case .ready?: return ready
            case .work?: return work
            case .gap?: return gap
            }
        }
    }

    var readinessCounts: ReadinessCounts {
        var out = ReadinessCounts(all: questions.count)
        for q in questions {
            switch q.readiness {
            case .ready: out.ready += 1
            case .work: out.work += 1
            case .gap: out.gap += 1
            }
        }
        return out
    }

    /// The questions under one readiness chip; `nil` is "All questions".
    func questions(_ readiness: Readiness?) -> [Question] {
        guard let readiness else { return questions }
        return questions.filter { $0.readiness == readiness }
    }

    /// The header's facts, each only when known; the date falls back to the day of the run.
    func meta(madeOn: String) -> [(label: String, value: String)] {
        let date = matter.date.isEmpty ? (madeOn.isEmpty ? "Today" : madeOn) : matter.date
        return [
            ("Forum", matter.forum), ("Matter", matter.number),
            ("Prepared for", matter.client), ("Date", date),
        ].filter { !$0.1.isEmpty }
    }

    /// The charts' subtitle.
    var chartsLine: String {
        let n = weakSpots.count
        guard n > 0 else { return "Charts appear here when the report finds weak spots." }
        return "Three views of the same \(n == 1 ? "weak spot" : "\(n) weak spots"): how serious, where they sit, and how hard the other side is likely to push on \(n == 1 ? "it" : "each")."
    }

    /// The spot a cross-reference points at.
    func spot(_ id: Int) -> WeakSpot? { weakSpots.first { $0.id == id } }

    // MARK: - Words the page uses

    static let disclaimerLead = "A first draft to check, not advice."
    static let disclaimer =
        "This report was written by an AI from your documents. It can misread a clause, slip on a figure or assume a fact that is not in your papers. Check every point against the documents and your own judgment before you rely on it."
    static let verifyLead = "Verify before citing."
    static let verifyNote =
        "These are general descriptions written by an AI, not citations. Anything marked Verify was not found in your papers. Read the judgment, check it is still good law, and confirm the exact holding and paragraph before relying on it in court."
    static let verifyBadge = "Verify before citing: not found in your papers"
    static let noSpotsChart =
        "No weak spots were found in the papers you gave, so there is nothing to chart. That is a good sign, not a promise: check that you attached everything."
    static let noSpots = "Nothing in these papers stood out as a weak spot."
    static let noQuestions = "No likely questions were listed."
    static let noGaps = "No missing papers were identified."
    static let noAuthorities = "No adverse authorities were listed."
    static let noChecklist = "No checklist items were suggested."
}
