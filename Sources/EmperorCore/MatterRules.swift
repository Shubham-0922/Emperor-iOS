import Foundation

/// A refusal worded exactly as the platform's matter rules word it (`lib/projects/rules.js`), so a
/// form can stop a write the server would answer with a 400 and say the same sentence.
struct MatterRuleError: LocalizedError, Equatable, Sendable {
    let message: String
    var errorDescription: String? { message }
}

/// The matter (project) data rules: field validation, dates in India, money and the court-case
/// fill rules — a port of the platform's `lib/projects/rules.js`, the module every project write
/// on the server goes through. `MatterGoldenTests` holds each function to answers produced by
/// running that file (`scripts/generate-matter-fixtures.mjs`).
///
/// Every day here is a day in India: a string `YYYY-MM-DD`, compared as text, never a `Date` in
/// the device's zone.
enum MatterRules {

    // MARK: - Text and vocabularies

    /// `optText`: absent and whitespace are nil; longer than `max` UTF-16 units is refused.
    static func optText(_ value: String?, label: String, max: Int) throws -> String? {
        guard let value else { return nil }
        let s = JSCompat.trim(value)
        if s.isEmpty { return nil }
        if s.utf16.count > max { throw MatterRuleError(message: "\(label) is longer than \(max) characters") }
        return s
    }

    /// `reqText`: as `optText`, and nil is refused.
    static func reqText(_ value: String?, label: String, max: Int) throws -> String {
        guard let s = try optText(value, label: label, max: max) else {
            throw MatterRuleError(message: "\(label) is required")
        }
        return s
    }

    /// `oneOf`: one value of a vocabulary, matched case-insensitively; blank is `fallback`.
    static func oneOf(_ value: String?, allowed: [String], label: String, fallback: String? = nil) throws -> String? {
        guard let value, !JSCompat.trim(value).isEmpty else { return fallback }
        let v = JSCompat.trim(value).lowercased()
        guard allowed.contains(v) else {
            throw MatterRuleError(message: "\(label) must be one of: \(allowed.joined(separator: ", "))")
        }
        return v
    }

    // MARK: - Dates (IST)

    /// India's calendar day for an instant: UTC+5:30 all year, so plain arithmetic.
    static func istDay(_ at: Date = Date()) -> String {
        istDay(epochMillis: at.timeIntervalSince1970 * 1000)
    }

    static func istDay(epochMillis: Double) -> String {
        JSCompat.isoDay(epochMillis: epochMillis + 330 * 60 * 1000)
    }

    /// A real calendar day between 1800 and 2200.
    private static func realDay(_ y: Int, _ m: Int, _ d: Int) -> Bool {
        guard y >= 1800, y <= 2200, (1...12).contains(m), d >= 1 else { return false }
        return d <= JSCompat.daysInMonth(year: y, month: m)
    }

    private static let isoDayPattern = MatterPattern("^([0-9]{4})-([0-9]{2})-([0-9]{2})$")
    private static let indianDayPattern = MatterPattern("^([0-9]{1,2})[-/.]([0-9]{1,2})[-/.]([0-9]{4})$")
    private static let timestampPrefix = MatterPattern("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")

    /// `istDateOf`: `YYYY-MM-DD`, `DD-MM-YYYY` / `DD/MM/YYYY` / `DD.MM.YYYY`, or an ISO timestamp
    /// read as its day in India; nil for anything else.
    static func istDateOf(_ value: String?) -> String? {
        guard let value else { return nil }
        let s = JSCompat.trim(value)
        if let m = isoDayPattern.groups(in: s) {
            return realDay(Int(m[1]!)!, Int(m[2]!)!, Int(m[3]!)!) ? s : nil
        }
        if let m = indianDayPattern.groups(in: s) {
            let d = Int(m[1]!)!, mo = Int(m[2]!)!, y = Int(m[3]!)!
            return realDay(y, mo, d) ? "\(m[3]!)-\(pad2(m[2]!))-\(pad2(m[1]!))" : nil
        }
        if timestampPrefix.test(s) {
            return JSCompat.parseDate(s).map { istDay(epochMillis: $0) }
        }
        return nil
    }

    private static func pad2(_ s: String) -> String { s.count >= 2 ? s : String(repeating: "0", count: 2 - s.count) + s }

    /// `dayOf`: a day field in any form `istDateOf` reads; blank is nil, junk is refused.
    static func dayOf(_ value: String?, label: String) throws -> String? {
        guard let value, !JSCompat.trim(value).isEmpty else { return nil }
        guard let d = istDateOf(value) else { throw MatterRuleError(message: "\(label) must be a date (YYYY-MM-DD)") }
        return d
    }

    private static let yearPattern = MatterPattern("^([0-9]{4})$")
    private static let monthPattern = MatterPattern("^([0-9]{4})-([0-9]{2})$")

    /// `eventDateOf`: a chronology date — `YYYY`, `YYYY-MM`, a day, or a timestamp (kept as the
    /// instant, in `toISOString` form).
    static func eventDateOf(_ value: String?, label: String = "eventDate") throws -> String? {
        guard let value, !JSCompat.trim(value).isEmpty else { return nil }
        let s = JSCompat.trim(value)
        if let m = yearPattern.groups(in: s), let y = Int(m[1]!), y >= 1800, y <= 2200 { return s }
        if let m = monthPattern.groups(in: s), let y = Int(m[1]!), let mo = Int(m[2]!),
           y >= 1800, y <= 2200, mo >= 1, mo <= 12 { return s }
        if timestampPrefix.test(s) {
            if let t = JSCompat.parseDate(s) { return JSCompat.isoString(epochMillis: t) }
        } else if let d = istDateOf(s) {
            return d
        }
        throw MatterRuleError(message: "\(label) must be a date (YYYY-MM-DD, YYYY-MM or YYYY)")
    }

    /// `isTodayOrLaterIst`.
    static func isTodayOrLaterIst(_ value: String?, today: String = istDay()) -> Bool {
        guard let d = istDateOf(value) else { return false }
        return d >= today
    }

    /// `computeNextHearing`: the earliest upcoming of the chronology hearings, the linked case's
    /// next date and the stored date (unless it is the one just removed); a passed stored date is
    /// kept only when nothing upcoming replaces it.
    static func computeNextHearing(stored: String? = nil, removed: String? = nil, hearings: [String?] = [],
                                   caseNext: String? = nil, today: String = istDay()) -> String? {
        let st = istDateOf(stored)
        let rm = istDateOf(removed)
        var upcoming: [String] = []
        for h in hearings {
            if let d = istDateOf(h), d >= today { upcoming.append(d) }
        }
        if let cn = istDateOf(caseNext), cn >= today { upcoming.append(cn) }
        if let st, st >= today, st != rm { upcoming.append(st) }
        if let first = upcoming.min() { return first }
        if let st, st != rm { return st }
        return nil
    }

    // MARK: - Money

    /// What a ledger amount arrives as: a number from a picker, or text a person typed.
    enum AmountInput: Equatable, Sendable {
        case number(Double)
        case text(String)
    }

    /// The server's ceiling: ₹10,000 crore. The amount field's own (`INR.maxRupees`) is higher.
    static let maxRupees: Double = 1e11

    private static let plainAmount = MatterPattern("^[0-9]+(\\.[0-9]+)?$")
    private static let amountNoise = MatterPattern("[\(JSCompat.spaceChars),₹]")

    /// `rupeesToPaise`: rupees → whole paise, as the server stores them.
    static func rupeesToPaise(_ amount: AmountInput, label: String = "amount") throws -> Int {
        var n = Double.nan
        switch amount {
        case .number(let v): n = v
        case .text(let text):
            let s = amountNoise.replace(in: text, with: "")
            if plainAmount.test(s) { n = Double(s) ?? .nan }
        }
        guard n.isFinite else { throw MatterRuleError(message: "\(label) must be a number of rupees") }
        if n <= 0 { throw MatterRuleError(message: "\(label) must be more than zero") }
        if n > maxRupees { throw MatterRuleError(message: "\(label) is too large") }
        // toPrecision(15) first: 1.005 * 100 is 100.49999999999999 in binary and must give 101.
        let rounded = Double(String(format: "%.15g", n * 100)) ?? n * 100
        return Int(JSCompat.round(rounded))
    }

    static func paiseToRupees(_ paise: Int) -> Double { Double(paise) / 100 }

    /// The fees card's four numbers, in rupees. `outstanding` is negative for an advance.
    struct LedgerTotals: Equatable, Sendable {
        var billed: Double
        var received: Double
        var outstanding: Double
        var expenses: Double
    }

    static func ledgerTotals(_ rows: [(kind: String, paise: Int)]) -> LedgerTotals {
        var fee = 0, payment = 0, expense = 0
        for r in rows {
            switch r.kind {
            case "fee": fee += r.paise
            case "payment": payment += r.paise
            case "expense": expense += r.paise
            default: break
            }
        }
        return LedgerTotals(billed: Double(fee) / 100, received: Double(payment) / 100,
                            outstanding: Double(fee - payment) / 100, expenses: Double(expense) / 100)
    }

    // MARK: - Projects

    /// `bannerOf`: a preset key, `image`, or nil for anything else.
    static func bannerOf(_ value: String?) -> String? {
        guard let value else { return nil }
        let v = JSCompat.trim(value).lowercased()
        return v == "image" || MatterVocabulary.BannerPreset(rawValue: v) != nil ? v : nil
    }

    /// `ourSideOf`: a known side (lower-cased), or the user's own words.
    static func ourSideOf(_ value: String?) throws -> String? {
        guard let s = try optText(value, label: "ourSide", max: 60) else { return nil }
        return MatterVocabulary.OurSide(rawValue: s.lowercased()) != nil ? s.lowercased() : s
    }

    /// The longest text the server accepts for a field. Project fields by their body key
    /// (`name`, `client`, `ourSide`…); the others prefixed: `task.title`, `ledger.reference`,
    /// `person.address`, `update.body`.
    static func fieldLimit(_ key: String) -> Int? { fieldLimits[key] }

    static let fieldLimits: [String: Int] = [
        "name": 200, "client": 300, "description": 5000, "forumName": 200, "caseNumber": 100,
        "caseYear": 10, "caseType": 100, "cnr": 100, "stage": 200, "oppositeParty": 300, "ourSide": 60,
        "update.title": 300, "update.body": 50000, "update.status": 40, "update.sourceRef": 300,
        "task.title": 300, "task.notes": 5000,
        "ledger.title": 300, "ledger.reference": 120, "ledger.notes": 5000, "ledger.receiptFile": 500,
        "person.name": 200, "person.address": 1000, "person.notes": 5000, "person.email": 200, "person.phone": 40,
    ]

    /// `confirmMatches`: DELETE /project's guard — the exact name, verbatim.
    static func confirmMatches(name: String?, confirm: String?) -> Bool {
        guard let confirm, !confirm.isEmpty else { return false }
        return confirm == (name ?? "")
    }

    /// The identity fields of a tracked court case, as `fieldsFromCase` reads them.
    struct CaseIdentity: Equatable, Sendable {
        var courtType: String?
        var courtName: String?
        var caseType: String?
        var caseNumber: String?
        var caseYear: String?
        var cnr: String?
        var diaryNumber: String?
        var nextHearingDate: String?
    }

    /// The same fields on the matter.
    struct MatterIdentity: Equatable, Sendable {
        var forumType: String?
        var forumName: String?
        var caseType: String?
        var caseNumber: String?
        var caseYear: String?
        var cnr: String?
        var nextHearingDate: String?
    }

    static let forumTypeByCourtType: [String: String] = [
        "sc": "supreme_court", "hc": "high_court", "district": "district",
        "tribunal": "tribunal", "nclt": "tribunal", "nclat": "tribunal", "forum": "other",
    ]

    private static func empty(_ v: String?) -> Bool { v == nil || JSCompat.trim(v!).isEmpty }

    /// `fieldsFromCase`: the columns a newly linked case fills — only where the matter left them
    /// empty. Keys are the server's column names.
    static func fieldsFromCase(project p: MatterIdentity, kase k: CaseIdentity) -> [String: String] {
        var cols: [String: String] = [:]
        let forumType = k.courtType.flatMap { forumTypeByCourtType[$0] }
        if empty(p.forumType) || p.forumType == "other", let forumType, forumType != "other" { cols["forum_type"] = forumType }
        if empty(p.forumName), !empty(k.courtName) { cols["forum_name"] = JSCompat.trim(k.courtName!) }
        if empty(p.caseType), !empty(k.caseType) { cols["case_type"] = JSCompat.trim(k.caseType!) }
        if empty(p.caseNumber), !empty(k.caseNumber) { cols["case_number"] = JSCompat.trim(k.caseNumber!) }
        if empty(p.caseYear), !empty(k.caseYear) { cols["case_year"] = JSCompat.trim(k.caseYear!) }
        let cnr = !empty(k.cnr) ? k.cnr : k.diaryNumber
        if empty(p.cnr), !empty(cnr) { cols["cnr"] = JSCompat.trim(cnr!) }
        if empty(p.nextHearingDate), let next = istDateOf(k.nextHearingDate) { cols["next_hearing_date"] = next }
        return cols
    }

    /// `fieldsClearedOnUnlink`: the columns that still hold exactly what the case copied in,
    /// cleared (`nil`), and `forum_type` reset to `other`.
    static func fieldsClearedOnUnlink(project p: MatterIdentity, kase k: CaseIdentity) -> [String: String?] {
        func same(_ a: String?, _ b: String?) -> Bool {
            guard let a, let b else { return false }
            let ta = JSCompat.trim(a)
            return !ta.isEmpty && ta == JSCompat.trim(b)
        }
        var cols: [String: String?] = [:]
        if same(p.forumName, k.courtName) {
            cols["forum_name"] = .some(nil)
            if let forumType = k.courtType.flatMap({ forumTypeByCourtType[$0] }), p.forumType == forumType {
                cols["forum_type"] = .some("other")
            }
        }
        if same(p.caseType, k.caseType) { cols["case_type"] = .some(nil) }
        if same(p.caseNumber, k.caseNumber) { cols["case_number"] = .some(nil) }
        if same(p.caseYear, k.caseYear) { cols["case_year"] = .some(nil) }
        if same(p.cnr, k.cnr) || same(p.cnr, k.diaryNumber) { cols["cnr"] = .some(nil) }
        if same(istDateOf(p.nextHearingDate), istDateOf(k.nextHearingDate)) { cols["next_hearing_date"] = .some(nil) }
        return cols
    }

    private static let practiceRules: [(MatterPattern, String)] = [
        (MatterPattern("ARB|O\\.?M\\.?P|EX\\.?P\\.?\\(?COMM|SEC(TION)?\\.?(9|11|34|37)"), "arbitration"),
        (MatterPattern("CRL|CRIM|BAIL|^BA\\b|^ABA|CRM|CR\\.?REV|SESSIONS|^SC$|^CC$|N\\.?I\\.?ACT|MCRC|CRLMC"), "criminal"),
        (MatterPattern("W\\.?P|WRIT|L\\.?P\\.?A|CONT\\.?CAS|SLP"), "writ"),
        (MatterPattern("MAT|HMA|DIV|GUARD|G\\.?P\\.?|MAINT"), "family"),
        (MatterPattern("TM|PAT|COPY|DESIGN|C\\.?O\\.?\\(COMM\\.?\\)\\.?IPD|IPD|IPR"), "ipr"),
        (MatterPattern("ITA|ITR|GST|VAT|TAX|CUS|CEXA|SERV.?TAX"), "tax"),
        (MatterPattern("CO\\.?PET|C\\.?A\\.?\\(?CAA|COMP|IB|CIRP"), "corporate"),
        (MatterPattern("LAB|I\\.?D\\.?|SERV|EMP"), "labour"),
        (MatterPattern("CS|SUIT|RFA|RSA|FAO|CRP|C\\.?R\\.?|EX|O\\.?S|CIVIL|COMM"), "civil"),
    ]

    /// `practiceAreaFromCase`: the practice area a tracked case most likely belongs to, or nil.
    static func practiceAreaFromCase(caseType: String?, courtType: String?) -> String? {
        let t = JSCompat.removeSpaces(caseType ?? "").uppercased()
        let court = courtType ?? ""
        if court == "nclt" || court == "nclat" { return "insolvency" }
        if court == "forum" { return "consumer" }
        for (pattern, area) in practiceRules where pattern.test(t) { return area }
        return nil
    }

    /// `matterNameFromCase`: the cause title read as the server names a matter made from a case.
    static func matterNameFromCase(title: String?, caseType: String?, caseNumber: String?, caseYear: String?) -> String {
        let raw = JSCompat.clean(title)
        var number: String?
        if let caseNumber, !caseNumber.isEmpty {
            number = caseNumber + ((caseYear?.isEmpty ?? true) ? "" : "/\(caseYear!)")
        }
        let fallback = [caseType, number].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if raw.isEmpty { return fallback.isEmpty ? "Untitled matter" : fallback }
        return CourtNames.tidy(raw, title: true)
    }

    // MARK: - Storage paths

    static let projectsDirectory = "_projects"

    /// `safeSegment`: each UTF-16 unit outside `[a-zA-Z0-9._-]` becomes `_`; nothing or all dots is `_`.
    static func safeSegment(_ seg: String?) -> String {
        let units = (seg ?? "").utf16.map { u -> UInt16 in
            switch u {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2E, 0x5F, 0x2D: return u
            default: return 0x5F
            }
        }
        let cleaned = String(decoding: units, as: UTF16.self)
        if cleaned.isEmpty || cleaned.allSatisfy({ $0 == "." }) { return "_" }
        return cleaned
    }

    /// `segmentsOf`: `/`-separated segments, with empty and `.` segments dropped.
    static func segmentsOf(_ rel: String?) -> [String] {
        (rel ?? "").replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true).map(String.init).filter { $0 != "." }
    }

    /// `receiptPathOf`: a ledger entry's receipt as a path in this matter's storage, or a refusal.
    static func receiptPathOf(_ value: String?, projectID: String) throws -> String? {
        guard let s = try optText(value, label: "receiptFile", max: 500) else { return nil }
        let outside = MatterRuleError(message: "receiptFile must be a file in this project's storage")
        if s.hasPrefix("/") || s.hasPrefix("\\") { throw outside }
        let parts = segmentsOf(s)
        if parts.isEmpty || parts.contains(where: { $0.allSatisfy { $0 == "." } }) { throw outside }
        let full = parts[0] == projectsDirectory ? parts : segmentsOf("\(projectsDirectory)/\(projectID)") + parts
        guard full[0] == projectsDirectory, full.count >= 3, full[1] == projectID else { throw outside }
        return full.map(safeSegment).joined(separator: "/")
    }

    // MARK: - People

    private static let emailPattern = MatterPattern("^[^\(JSCompat.spaceChars)@]+@[^\(JSCompat.spaceChars)@]+\\.[^\(JSCompat.spaceChars)@]+$")
    private static let phonePattern = MatterPattern(
        "^[0-9+()\\-./\(JSCompat.spaceChars)]+((ext\\.?|x)\(JSCompat.spaceClass)*[0-9]+)?$",
        caseInsensitive: true)

    /// The address check `POST /project-person` applies (blank passes: the field is optional).
    static func validEmail(_ value: String?) -> Bool {
        do {
            guard let s = try optText(value, label: "email", max: 200) else { return true }
            return emailPattern.test(s)
        } catch { return false }
    }

    /// The phone check `POST /project-person` applies: lenient — landlines, STD codes,
    /// extensions — but at least three digits (blank passes).
    static func validPhone(_ value: String?) -> Bool {
        do {
            guard let s = try optText(value, label: "phone", max: 40) else { return true }
            let digits = s.unicodeScalars.filter { (48...57).contains($0.value) }.count
            return phonePattern.test(s) && digits >= 3
        } catch { return false }
    }

    // MARK: - Banner image

    static let bannerMaxBytes = 2 * 1024 * 1024
    static let bannerExtensions: [String: String] = ["image/png": "png", "image/jpeg": "jpg", "image/webp": "webp"]
    static let bannerMIMEByExtension: [String: String] = ["png": "image/png", "jpg": "image/jpeg", "webp": "image/webp"]

    /// The MIME type and extension the server would accept these bytes as, from their signature
    /// (`signatureMatches`), or nil — so a picked image is checked before it is sent.
    static func bannerImageType(_ data: Data) -> (mime: String, ext: String)? {
        let b = [UInt8](data.prefix(12))
        if data.count > 8, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47,
           b[4] == 0x0D, b[5] == 0x0A, b[6] == 0x1A, b[7] == 0x0A { return ("image/png", "png") }
        if data.count > 3, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return ("image/jpeg", "jpg") }
        if data.count > 12, b[0...3] == [0x52, 0x49, 0x46, 0x46], b[8...11] == [0x57, 0x45, 0x42, 0x50] {
            return ("image/webp", "webp")
        }
        return nil
    }

    // MARK: - Court refresh throttle

    /// At most one on-demand case refresh per five minutes.
    static let caseRefreshGapMillis: Double = 5 * 60 * 1000

    /// Seconds left before a refresh may run again; 0 means go.
    static func refreshWaitSeconds(lastAt: Date?, now: Date = Date()) -> Int {
        refreshWaitSeconds(lastAtMillis: lastAt.map { $0.timeIntervalSince1970 * 1000 },
                           nowMillis: now.timeIntervalSince1970 * 1000)
    }

    static func refreshWaitSeconds(lastAtMillis: Double?, nowMillis: Double) -> Int {
        guard let lastAtMillis, lastAtMillis != 0 else { return 0 }
        let left = lastAtMillis + caseRefreshGapMillis - nowMillis
        return left > 0 ? Int((left / 1000).rounded(.up)) : 0
    }
}

// MARK: - JavaScript semantics

/// The handful of JavaScript behaviours the matter ports depend on, restated once: JS whitespace,
/// UTF-16 lengths, `Date.parse` of the ISO shapes this API stores, `toISOString`, `Math.round`,
/// ICU's `localeCompare` ordering, and `toLocaleString('en-IN')` grouping — all without
/// `Locale`, so the answer is the same on Linux and on a phone.
enum JSCompat {

    /// JavaScript's `\s` (and `trim`) set.
    static let spaceScalars: Set<UInt32> = [
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005,
        0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF,
    ]

    /// The same set as a regular-expression class.
    static let spaceChars = "\\t\\n\\x{0B}\\f\\r \\x{A0}\\x{1680}\\x{2000}-\\x{200A}\\x{2028}\\x{2029}\\x{202F}\\x{205F}\\x{3000}\\x{FEFF}"
    static let spaceClass = "[\(spaceChars)]"

    static func isSpace(_ s: Unicode.Scalar) -> Bool { spaceScalars.contains(s.value) }

    /// `String.prototype.trim`.
    static func trim(_ s: String) -> String {
        let scalars = Array(s.unicodeScalars)
        guard let start = scalars.firstIndex(where: { !isSpace($0) }),
              let end = scalars.lastIndex(where: { !isSpace($0) }) else { return "" }
        return String(String.UnicodeScalarView(scalars[start...end]))
    }

    /// `.replace(/\s+/g, ' ')`.
    static func collapse(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var inSpace = false
        for scalar in s.unicodeScalars {
            if isSpace(scalar) {
                if !inSpace { out.append(" ") }
                inSpace = true
            } else {
                out.append(scalar)
                inSpace = false
            }
        }
        return String(out)
    }

    /// `.replace(/\s+/g, '')`.
    static func removeSpaces(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { !isSpace($0) }))
    }

    /// `String(s ?? '').replace(/\s+/g, ' ').trim()` — the `clean` every web module defines.
    static func clean(_ s: String?) -> String { trim(collapse(s ?? "")) }

    /// The first `n` UTF-16 units, as `slice(0, n)`.
    static func prefixUTF16(_ s: String, _ n: Int) -> String {
        String(decoding: Array(s.utf16.prefix(n)), as: UTF16.self)
    }

    // MARK: Numbers

    /// `Math.round`: halves go up (towards +∞).
    static func round(_ x: Double) -> Double {
        guard x.isFinite else { return x }
        let f = x.rounded(.down)
        return x - f >= 0.5 ? f + 1 : f
    }

    /// `String(n)` for a number, the way a value read from JSON prints in JavaScript.
    static func numberString(_ n: Double) -> String {
        if n.isNaN { return "NaN" }
        if n.isInfinite { return n > 0 ? "Infinity" : "-Infinity" }
        if n == n.rounded(), abs(n) < 1e21 {
            let digits = shortestDigits(n)
            return (n < 0 ? "-" : "") + digits.integer
        }
        let digits = shortestDigits(n)
        return (n < 0 ? "-" : "") + digits.integer + (digits.fraction.isEmpty ? "" : "." + digits.fraction)
    }

    /// The shortest decimal that reads back as `x` (what ICU and V8 print from), split into
    /// integer and fraction digits, without sign or exponent.
    static func shortestDigits(_ x: Double) -> (integer: String, fraction: String) {
        var text = "\(abs(x))"
        var exponent = 0
        if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            exponent = Int(text[text.index(after: e)...]) ?? 0
            text = String(text[..<e])
        }
        var intPart = text
        var fracPart = ""
        if let dot = text.firstIndex(of: ".") {
            intPart = String(text[..<dot])
            fracPart = String(text[text.index(after: dot)...])
        }
        var digits = intPart + fracPart
        var point = intPart.count + exponent
        while digits.count > 1, digits.first == "0" {
            digits.removeFirst()
            point -= 1
        }
        if point <= 0 {
            digits = String(repeating: "0", count: -point + 1) + digits
            point = 1
        }
        if digits.count < point { digits += String(repeating: "0", count: point - digits.count) }
        var integer = String(digits.prefix(point))
        var fraction = String(digits.dropFirst(point))
        while fraction.last == "0" { fraction.removeLast() }
        while integer.count > 1, integer.first == "0" { integer.removeFirst() }
        if integer.isEmpty { integer = "0" }
        return (integer, fraction)
    }

    /// `n.toLocaleString('en-IN', { minimumFractionDigits, maximumFractionDigits })`: the shortest
    /// decimal of `n`, rounded half away from zero, with Indian digit grouping.
    static func indianNumber(_ n: Double, minFraction: Int = 0, maxFraction: Int = 3) -> String {
        if n.isNaN { return "NaN" }
        if n.isInfinite { return n > 0 ? "∞" : "-∞" }
        let parts = shortestDigits(n)
        var integer = Array(parts.integer)
        var fraction = Array(parts.fraction)
        if fraction.count > maxFraction {
            let roundUp = fraction[maxFraction] >= "5"
            fraction = Array(fraction.prefix(maxFraction))
            if roundUp {
                var all = integer + fraction
                var i = all.count - 1
                var carry = true
                while carry, i >= 0 {
                    if all[i] == "9" { all[i] = "0"; i -= 1 } else {
                        all[i] = Character(String(all[i].wholeNumberValue! + 1)); carry = false
                    }
                }
                if carry { all.insert("1", at: 0) }
                integer = Array(all.prefix(all.count - fraction.count))
                fraction = Array(all.suffix(fraction.count))
            }
        }
        while fraction.count > minFraction, fraction.last == "0" { fraction.removeLast() }
        while fraction.count < minFraction { fraction.append("0") }
        let grouped = indianGrouping(String(integer))
        let sign = n < 0 || (n == 0 && n.sign == .minus) ? "-" : ""
        return sign + grouped + (fraction.isEmpty ? "" : "." + String(fraction))
    }

    /// "1234567" → "12,34,567".
    static func indianGrouping(_ digits: String) -> String {
        guard digits.count > 3 else { return digits }
        var head = Array(digits.dropLast(3))
        let tail = String(digits.suffix(3))
        var groups: [String] = []
        while head.count > 2 {
            groups.insert(String(head.suffix(2)), at: 0)
            head.removeLast(2)
        }
        if !head.isEmpty { groups.insert(String(head), at: 0) }
        return (groups + [tail]).joined(separator: ",")
    }

    // MARK: Dates

    /// Days since 1970-01-01 for a proleptic Gregorian date (month 1...12, day may overflow).
    static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let m = month
        let doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    static func pad(_ n: Int, _ width: Int) -> String {
        let s = String(abs(n))
        return (n < 0 ? "-" : "") + String(repeating: "0", count: max(0, width - s.count)) + s
    }

    /// `new Date(ms).toISOString().slice(0, 10)`.
    static func isoDay(epochMillis: Double) -> String {
        let days = Int((epochMillis / 86_400_000).rounded(.down))
        let c = civilFromDays(days)
        return "\(pad(c.year, 4))-\(pad(c.month, 2))-\(pad(c.day, 2))"
    }

    /// `new Date(ms).toISOString()`.
    static func isoString(epochMillis: Double) -> String {
        let ms = Int(epochMillis.rounded(.down))
        let days = Int((Double(ms) / 86_400_000).rounded(.down))
        var rest = ms - days * 86_400_000
        let h = rest / 3_600_000; rest -= h * 3_600_000
        let mi = rest / 60_000; rest -= mi * 60_000
        let s = rest / 1000
        let milli = rest - s * 1000
        return "\(isoDay(epochMillis: epochMillis))T\(pad(h, 2)):\(pad(mi, 2)):\(pad(s, 2)).\(pad(milli, 3))Z"
    }

    private static let dateOnly = MatterPattern("^([0-9]{4})(?:-([0-9]{2})(?:-([0-9]{2}))?)?$")
    private static let dateTime = MatterPattern(
        "^([0-9]{4})-([0-9]{2})-([0-9]{2})[T ]([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\\.([0-9]+))?)?([Zz]|[+-][0-9]{2}:?[0-9]{2})?$")

    /// `Date.parse` (and the web's `toDate`) for the shapes this API stores: `YYYY`, `YYYY-MM`,
    /// `YYYY-MM-DD` (UTC midnight), and a date and time with an optional `T`, fraction and zone
    /// (no zone is UTC — the web appends the `Z` SQLite leaves off). V8 rolls a day past the
    /// month's end over (`2026-02-30` is 2 March) and so does this. Epoch milliseconds, or nil.
    /// The legacy shapes V8 also guesses at (`12/10/2026`, month names) are not read.
    static func parseDate(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let s = trim(raw)
        if let m = dateOnly.groups(in: s) {
            let y = Int(m[1]!)!
            let mo = m[2].flatMap { Int($0) } ?? 1
            let d = m[3].flatMap { Int($0) } ?? 1
            guard (1...12).contains(mo), (1...31).contains(d) else { return nil }
            return Double(daysFromCivil(y, mo, d)) * 86_400_000
        }
        guard let m = dateTime.groups(in: s) else { return nil }
        let y = Int(m[1]!)!, mo = Int(m[2]!)!, d = Int(m[3]!)!
        let h = Int(m[4]!)!, mi = Int(m[5]!)!
        let sec = m[6].flatMap { Int($0) } ?? 0
        let milli = m[7].map { Int(String(($0 + "00").prefix(3)))! } ?? 0
        guard (1...12).contains(mo), (1...31).contains(d), mi <= 59, sec <= 59 else { return nil }
        guard h < 24 || (h == 24 && mi == 0 && sec == 0 && milli == 0) else { return nil }
        var offsetMinutes = 0
        if let zone = m[8], zone != "Z", zone != "z" {
            let digits = zone.filter(\.isNumber)
            let zh = Int(digits.prefix(2))!, zm = Int(digits.suffix(2))!
            offsetMinutes = (zh * 60 + zm) * (zone.hasPrefix("-") ? -1 : 1)
        }
        let days = Double(daysFromCivil(y, mo, d))
        let seconds = Double(h * 3600 + mi * 60 + sec - offsetMinutes * 60)
        return days * 86_400_000 + seconds * 1000 + Double(milli)
    }

    // MARK: Collation

    /// Printable ASCII in the order ICU's root collation sorts it (`localeCompare`), letters
    /// case-paired: what every sort in the web's matter modules uses.
    private static let asciiOrder = " _-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$0123456789aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ"

    private static let asciiRank: [UInt32: Int] = {
        var ranks: [UInt32: Int] = [:]
        var rank = 0
        for ch in asciiOrder.unicodeScalars {
            if ch.properties.isUppercase, let lower = Unicode.Scalar(ch.value + 32), let r = ranks[lower.value] {
                ranks[ch.value] = r
                continue
            }
            rank += 1
            ranks[ch.value] = rank
        }
        return ranks
    }()

    private struct CollationKey {
        var primary: [Int] = []
        var secondary: [Int] = []
        var tertiary: [Int] = []
    }

    private static func collationKey(_ s: String) -> CollationKey {
        var key = CollationKey()
        for scalar in s.decomposedStringWithCanonicalMapping.unicodeScalars {
            if (0x300...0x36F).contains(scalar.value), !key.secondary.isEmpty {
                key.secondary[key.secondary.count - 1] = Int(scalar.value)
                continue
            }
            if let rank = asciiRank[scalar.value] {
                key.primary.append(rank)
            } else {
                key.primary.append(1000 + Int(scalar.value))
            }
            key.secondary.append(0)
            key.tertiary.append(scalar.properties.isUppercase ? 1 : 0)
        }
        return key
    }

    private static func compareArrays(_ a: [Int], _ b: [Int]) -> Int {
        for (x, y) in zip(a, b) where x != y { return x < y ? -1 : 1 }
        return a.count == b.count ? 0 : (a.count < b.count ? -1 : 1)
    }

    /// `a.localeCompare(b)`, as -1, 0 or 1: ICU root order (spaces, punctuation, symbols, digits,
    /// letters), accents after base letters, lower case before upper — the rule each level
    /// compared across the whole string before the next.
    static func localeCompare(_ a: String, _ b: String) -> Int {
        if a == b { return 0 }
        let ka = collationKey(a), kb = collationKey(b)
        let p = compareArrays(ka.primary, kb.primary)
        if p != 0 { return p }
        let s = compareArrays(ka.secondary, kb.secondary)
        if s != 0 { return s }
        return compareArrays(ka.tertiary, kb.tertiary)
    }

    /// A stable sort by a three-way comparison, as `Array.prototype.sort` (TimSort) is.
    static func stableSorted<T>(_ items: [T], by compare: (T, T) -> Int) -> [T] {
        items.enumerated().sorted { lhs, rhs in
            let c = compare(lhs.element, rhs.element)
            return c != 0 ? c < 0 : lhs.offset < rhs.offset
        }.map(\.element)
    }
}

/// A regular expression with JavaScript's habits where they matter here: searched over UTF-16,
/// optional groups returned as nil.
struct MatterPattern: @unchecked Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = false) {
        // A pattern here is a literal in this file; a typo is a programming error caught by the tests.
        regex = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    func test(_ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    /// The whole match and each group (nil when a group did not take part), or nil for no match.
    func groups(in text: String) -> [String?]? {
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }

    /// Every match replaced by a literal string.
    func replace(in text: String, with replacement: String) -> String {
        replace(in: text) { _, _ in replacement }
    }

    /// Every match replaced by what `transform` makes of it (the match and its UTF-16 offset).
    func replace(in text: String, _ transform: (String, Int) -> String) -> String {
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += transform(ns.substring(with: m.range), m.range.location)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}
