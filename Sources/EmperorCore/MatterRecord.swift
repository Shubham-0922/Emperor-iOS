import Foundation

/// The matter workspace's reading of a matter's record — a port of the platform's
/// `src/lib/projectRecord.js`: IST calendar days, the chronology merge (the user's entries plus
/// the linked case's hearings and orders), the next hearing, the identity lines and the
/// "List of Dates & Events" export. `orderLink` is not ported here (order PDFs are opened by the
/// case screens).
enum MatterRecord {

    // MARK: - Inputs

    /// One `project_updates` row.
    struct Update: Equatable, Sendable {
        var id: String
        var kind: String?
        var title: String?
        var body: String?
        var eventDate: String?
        var createdAt: String?
        var source: String?
        var sourceRef: String?

        init(id: String, kind: String? = nil, title: String? = nil, body: String? = nil, eventDate: String? = nil,
             createdAt: String? = nil, source: String? = nil, sourceRef: String? = nil) {
            self.id = id
            self.kind = kind
            self.title = title
            self.body = body
            self.eventDate = eventDate
            self.createdAt = createdAt
            self.source = source
            self.sourceRef = sourceRef
        }
    }

    /// One `case_items` row of the linked case (`courtHistory`).
    struct CourtItem: Equatable, Sendable {
        var id: String
        var section: String
        var title: String?
        var subtitle: String?
        var itemDate: String?
        var data: [String: JSONValue]

        init(id: String, section: String, title: String? = nil, subtitle: String? = nil, itemDate: String? = nil,
             data: [String: JSONValue] = [:]) {
            self.id = id
            self.section = section
            self.title = title
            self.subtitle = subtitle
            self.itemDate = itemDate
            self.data = data
        }

        /// `itemData`: `data` as the server sends it — an object, a JSON string from an older
        /// server, or nothing. A malformed one is empty and costs only itself.
        static func data(fromWire raw: JSONValue?) -> [String: JSONValue] {
            switch raw {
            case .object(let o): return o
            case .string(let s): if case .object(let o)? = JSONValue.decode(from: s) { return o }
            default: break
            }
            return [:]
        }
    }

    enum Source: String, Sendable {
        case manual, ai, court
    }

    /// One line of the merged chronology. `key` is unique across the merge; `id` is the row's own
    /// id (an update's or a case item's), so lists should be keyed on `key`.
    struct Entry: Equatable, Identifiable, Sendable {
        let key: String
        let id: String
        let src: Source
        /// The user's own entry (editable); a court row is not.
        let own: Bool
        let kind: String
        let day: String
        let title: String
        let body: String
        let sourceRef: String
        let created: String
        /// The case item a court row came from.
        let item: CourtItem?
    }

    // MARK: - Calendar days (IST)

    private static let dayPattern = MatterPattern("^([0-9]{4})-([0-9]{2})-([0-9]{2})$")
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// `dayKey`: any stored date → its IST day key; a bare `YYYY-MM-DD` passes untouched; "" when
    /// it is not a date.
    static func dayKey(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let s = JSCompat.trim(value)
        if dayPattern.test(s) { return s }
        guard let ms = JSCompat.parseDate(s) else { return "" }
        return MatterRules.istDay(epochMillis: ms)
    }

    private static func dayKey(json value: JSONValue?) -> String {
        guard let value, value != .null else { return "" }
        return dayKey(jsString(value))
    }

    /// `Date.UTC(y, m - 1, d)` in days, with its overflow and its 19xx reading of years 0–99.
    private static func utcDays(_ key: String) -> Int? {
        guard let m = dayPattern.groups(in: key), var y = Int(m[1]!), var mo = Int(m[2]!), let d = Int(m[3]!) else { return nil }
        if (0...99).contains(y) { y += 1900 }
        mo -= 1
        y += Int((Double(mo) / 12).rounded(.down))
        mo = ((mo % 12) + 12) % 12
        return JSCompat.daysFromCivil(y, mo + 1, 1) + d - 1
    }

    /// `daysFromToday`: 0 today, 1 tomorrow, -3 three days ago; nil without a day.
    static func daysFromToday(_ value: String?, today: String) -> Int? {
        guard let a = utcDays(dayKey(value)), let b = utcDays(today) else { return nil }
        return a - b
    }

    /// `fmtDay` (projectRecord's): "01 Oct 2026" from the day key, unvalidated.
    static func fmtDay(_ value: String?) -> String {
        guard let m = dayPattern.groups(in: dayKey(value)) else { return "" }
        let i = Int(m[2]!)! - 1
        return "\(m[3]!) \(months.indices.contains(i) ? months[i] : "undefined") \(m[1]!)"
    }

    /// `fmtDots`: DD.MM.YYYY, the date column of a List of Dates.
    static func fmtDots(_ value: String?) -> String {
        guard let m = dayPattern.groups(in: dayKey(value)) else { return "" }
        return "\(m[3]!).\(m[2]!).\(m[1]!)"
    }

    static func weekdayOf(_ value: String?) -> String {
        guard let days = utcDays(dayKey(value)) else { return "" }
        return weekdays[((days % 7) + 11) % 7]
    }

    static func relDays(_ n: Int?) -> String {
        guard let n else { return "" }
        switch n {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        default: return n > 0 ? "in \(n) days" : "\(-n) days ago"
        }
    }

    private static let docIso = MatterPattern("^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})")
    private static let docIndian = MatterPattern("^([0-9]{1,2})[./-]([0-9]{1,2})[./-]([0-9]{4})$")

    /// `parseDocDate`: a date the AI read out of a document, day first (05-01-2024 is 5 January);
    /// "" for anything that is not a whole, real day.
    static func parseDocDate(_ raw: String?) -> String {
        let t = JSCompat.trim(raw ?? "")
        let y: Int, mo: Int, d: Int
        if let m = docIso.groups(in: t) {
            (y, mo, d) = (Int(m[1]!)!, Int(m[2]!)!, Int(m[3]!)!)
        } else if let m = docIndian.groups(in: t) {
            (d, mo, y) = (Int(m[1]!)!, Int(m[2]!)!, Int(m[3]!)!)
        } else { return "" }
        guard y > 99, (1...12).contains(mo), d >= 1, d <= JSCompat.daysInMonth(year: y, month: mo) else { return "" }
        return "\(y)-\(JSCompat.pad(mo, 2))-\(JSCompat.pad(d, 2))"
    }

    // MARK: - Vocabulary

    /// `kindMeta(k).label`: an unknown kind reads as the first, Event.
    static func kindLabel(_ kind: String?) -> String {
        kind.flatMap(MatterVocabulary.ChronoKind.init(rawValue:))?.label ?? MatterVocabulary.ChronoKind.event.label
    }

    static func sourceLabel(_ source: Source) -> String {
        MatterVocabulary.UpdateSource(rawValue: source.rawValue)!.label
    }

    // MARK: - Court record

    /// What a hearing says, in the words a lawyer reads a cause list in.
    struct HearingFacts: Equatable, Sendable {
        let purpose: String
        let `where`: String
        let coram: String
        let remarks: String
        let supplementary: Bool
        let nextDate: String
    }

    private static let listingWord = MatterPattern("^listing$", caseInsensitive: true)
    private static let supplementaryWord = MatterPattern("supplementary", caseInsensitive: true)

    /// `hearingFacts`.
    static func hearingFacts(_ item: CourtItem) -> HearingFacts {
        let d = item.data
        let rawTitle: JSONValue? = (item.title?.isEmpty == false) ? .string(item.title!) : d["purpose"]
        let raw = JSCompat.clean(jsString(rawTitle))
        let purpose = listingWord.test(raw) ? "" : raw
        let court = CauseListText.courtLabel(d["courtNo"].flatMap { $0 == .null ? nil : jsString($0) }) ?? ""
        let where_ = [court, truthy(d["itemNo"]) ? "Item \(JSCompat.clean(jsString(d["itemNo"])))" : "",
                      JSCompat.clean(jsString(d["time"]))].filter { !$0.isEmpty }.joined(separator: " · ")
        let coramSource: JSONValue? = truthy(d["coram"]) ? d["coram"]
            : (item.subtitle?.isEmpty == false ? .string(item.subtitle!) : d["bench"])
        let listType = truthy(d["listType"]) ? jsString(d["listType"]) : ""
        return HearingFacts(purpose: purpose, where: where_, coram: JSCompat.clean(jsString(coramSource)),
                            remarks: JSCompat.clean(jsString(d["remarks"])),
                            supplementary: supplementaryWord.test(listType),
                            nextDate: dayKey(json: d["nextDate"]))
    }

    private static let orderCodes = ["O": "Order", "J": "Judgment", "OJ": "Order / Judgment"]

    /// `orderTitle`: an order's title, with the one-letter codes some courts store spelled out.
    static func orderTitle(_ raw: String?) -> String {
        let t = JSCompat.clean(raw)
        return orderCodes[t.uppercased()] ?? t
    }

    private static let closingBracket = MatterPattern("\\)$")
    private static let closingBrackets = MatterPattern("\\)+$")
    private static let threeCaps = MatterPattern("[A-Z]{3}")
    private static let courtNumber = MatterPattern("\\bcourt\(JSCompat.spaceClass)*no\\.?\(JSCompat.spaceClass)*", caseInsensitive: true)

    /// `plainCourtText`: a court's capitals as a sentence — "TO BE LISTED IN COURT NO.42" →
    /// "To be listed in Court 42".
    static func plainCourtText(_ raw: String?) -> String {
        var t = JSCompat.clean(raw)
        if closingBracket.test(t) && !t.contains("(") { t = closingBrackets.replace(in: t, with: "") }
        if !t.isEmpty, t == t.uppercased(), threeCaps.test(t) {
            t = JSCompat.prefixUTF16(t, 1) + String(decoding: Array(t.utf16.dropFirst()), as: UTF16.self).lowercased()
        }
        return JSCompat.trim(JSCompat.collapse(courtNumber.replace(in: t, with: "Court ")))
    }

    /// `ordersOf`: the case's orders with a date, latest first.
    static func orders(_ court: [CourtItem]) -> [CourtItem] {
        JSCompat.stableSorted(court.filter { $0.section == "orders" && !dayKey($0.itemDate).isEmpty }) {
            JSCompat.localeCompare(dayKey($1.itemDate), dayKey($0.itemDate))
        }
    }

    // MARK: - The chronology

    private static let nonAlnum = MatterPattern("[^a-z0-9]+")
    private static func normTitle(_ s: String) -> String {
        JSCompat.trim(nonAlnum.replace(in: JSCompat.clean(s).lowercased(), with: " "))
    }
    private static let orderWord = MatterPattern("^order$", caseInsensitive: true)

    /// `chronologyEntries`: the user's entries and the court's hearings and orders as one list
    /// (a court fact the server copied into the updates is not shown twice).
    static func chronology(updates: [Update], court: [CourtItem]) -> [Entry] {
        let own = updates.map { u -> Entry in
            let src: Source = u.source == "ai" ? .ai : u.source == "court" ? .court : .manual
            let when = (u.eventDate?.isEmpty == false) ? u.eventDate : u.createdAt
            return Entry(key: "u:\(u.id)", id: u.id, src: src, own: true,
                         kind: (u.kind?.isEmpty == false) ? u.kind! : "note",
                         day: dayKey(when), title: JSCompat.clean(u.title), body: JSCompat.trim(u.body ?? ""),
                         sourceRef: JSCompat.clean(u.sourceRef), created: u.createdAt ?? "", item: nil)
        }
        let copied = Set(own.filter { $0.src == .court }.map { "\($0.day)|\(normTitle($0.title))" })
        var courtEntries: [Entry] = []
        for it in court where it.section == "hearings" || it.section == "orders" {
            let day = dayKey(it.itemDate)
            if day.isEmpty { continue }
            let title: String, body: String
            if it.section == "hearings" {
                let h = hearingFacts(it)
                title = h.purpose.isEmpty ? "Listed before the court" : "Listed — \(h.purpose)"
                body = [h.coram, h.where, h.remarks].filter { !$0.isEmpty }.joined(separator: " · ")
            } else {
                let d = it.data
                let raw = (it.title?.isEmpty == false) ? it.title! : jsString(d["title"])
                let t = orderTitle(raw)
                title = t.isEmpty ? "Order passed" : t
                let type = jsString(d["type"])
                body = JSCompat.clean(truthy(d["type"]) && !orderWord.test(type) ? type : "")
            }
            if copied.contains("\(day)|\(normTitle(title))") { continue }
            courtEntries.append(Entry(key: "c:\(it.id)", id: it.id, src: .court, own: false,
                                      kind: it.section == "hearings" ? "hearing" : "order", day: day,
                                      title: title, body: body, sourceRef: "", created: "", item: it))
        }
        return own + courtEntries
    }

    /// `sortChronology`: oldest first (a List of Dates' order); on one day the court's listing,
    /// then its order, then the user's notes. Undated entries last.
    static func sorted(_ entries: [Entry], newestFirst: Bool = false) -> [Entry] {
        func rank(_ e: Entry) -> Int { e.src == .court && !e.own ? (e.kind == "hearing" ? 0 : 1) : 2 }
        let dated = JSCompat.stableSorted(entries.filter { !$0.day.isEmpty }) { a, b in
            let d = JSCompat.localeCompare(a.day, b.day)
            if d != 0 { return d }
            if rank(a) != rank(b) { return rank(a) - rank(b) }
            return JSCompat.localeCompare(a.created, b.created)
        }
        return (newestFirst ? dated.reversed() : dated) + entries.filter { $0.day.isEmpty }
    }

    // MARK: - The next hearing

    struct NextHearing: Equatable, Sendable {
        enum From: String, Sendable { case project, court }
        let day: String
        let from: From
        let days: Int?
        /// The court's own listing for that day.
        let listing: CourtItem?
        /// Failing that, the latest listing on record — the LAST hearing's, not the next one's.
        let latest: CourtItem?
    }

    /// `nextHearing`: the earliest date still ahead of the matter's and the linked case's; when
    /// both have passed, the later one.
    static func nextHearing(projectNext: String?, caseNext: String?, court: [CourtItem], today: String) -> NextHearing? {
        let cands = [(day: dayKey(projectNext), from: NextHearing.From.project),
                     (day: dayKey(caseNext), from: NextHearing.From.court)].filter { !$0.day.isEmpty }
        guard !cands.isEmpty else { return nil }
        let ahead = JSCompat.stableSorted(cands.filter { $0.day >= today }) { JSCompat.localeCompare($0.day, $1.day) }
        let pick = ahead.first ?? JSCompat.stableSorted(cands) { JSCompat.localeCompare($1.day, $0.day) }[0]
        let from: NextHearing.From = cands.contains { $0.day == pick.day && $0.from == .court } ? .court : pick.from
        let hearings = JSCompat.stableSorted(court.filter { $0.section == "hearings" && !dayKey($0.itemDate).isEmpty }) {
            JSCompat.localeCompare(dayKey($1.itemDate), dayKey($0.itemDate))
        }
        let listing = hearings.first { dayKey($0.itemDate) == pick.day }
        return NextHearing(day: pick.day, from: from, days: daysFromToday(pick.day, today: today),
                           listing: listing, latest: listing == nil ? hearings.first : nil)
    }

    // MARK: - Identity lines

    /// projectRecord's `ourSideLabel`: a known side's label, "" for `other` (a cause title has no
    /// "Other"), free text as written. `MatterMeta.sideLabel` is the list's reading ("Other").
    static func sideLabelForTitle(_ side: String?) -> String {
        if let known = side.flatMap(MatterVocabulary.OurSide.init(rawValue:)) {
            return known == .other ? "" : known.label
        }
        return JSCompat.clean(side)
    }

    /// `caseNoLabel`: "W.P.(C) 1234/2026" — the type left out when the number starts with it.
    static func caseNoLabel(number: String?, type: String?, year: String?) -> String {
        let num = JSCompat.clean(number)
        let t = JSCompat.clean(type)
        guard !num.isEmpty else { return "" }
        let head = !t.isEmpty && !num.lowercased().hasPrefix(t.lowercased()) ? "\(t) \(num)" : num
        if let year, !year.isEmpty { return "\(head)/\(JSCompat.clean(year))" }
        return head
    }

    private static let diaryShape = MatterPattern("^\(JSCompat.spaceClass)*[0-9]+\(JSCompat.spaceClass)*/\(JSCompat.spaceClass)*[0-9]{4}\(JSCompat.spaceClass)*$")

    /// `cnrLabel`: what the `cnr` field holds — "Diary no." for a number/year, else "CNR".
    static func cnrLabel(_ value: String?) -> String {
        diaryShape.test(value ?? "") ? "Diary no." : "CNR"
    }

    private static let formalNumber = MatterPattern("^(.*?)\(JSCompat.spaceClass)*([0-9][A-Za-z0-9_/-]*)$")

    /// `caseNoFormal`: "W.P.(C) No. 1234 of 2026", as a court document writes it.
    static func caseNoFormal(number: String?, type: String?, year: String?) -> String {
        let num = JSCompat.clean(number)
        guard !num.isEmpty else { return "" }
        let t = JSCompat.clean(type)
        let y = JSCompat.clean(year)
        let m = formalNumber.groups(in: num)
        let lead = [!t.isEmpty && !num.lowercased().hasPrefix(t.lowercased()) ? t : "", m?[1] ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " ")
        let body = m.map { "No. \($0[2]!)" } ?? num
        return "\(lead.isEmpty ? "" : "\(lead) ")\(body)\(y.isEmpty ? "" : " of \(y)")"
    }

    private static let opposite = [
        "petitioner": "Respondent", "plaintiff": "Defendant", "appellant": "Respondent", "complainant": "Accused",
        "applicant": "Respondent", "respondent": "Petitioner", "defendant": "Plaintiff", "accused": "Complainant",
    ]
    private static let firstNamed: Set<String> = ["petitioner", "plaintiff", "appellant", "complainant", "applicant"]

    /// The matter, as the List of Dates heads it.
    struct ListOfDatesInput: Equatable, Sendable {
        var name: String?
        var forumName: String?
        var caseType: String?
        var caseNumber: String?
        var caseYear: String?
        var client: String?
        var oppositeParty: String?
        var ourSide: String?

        init(name: String? = nil, forumName: String? = nil, caseType: String? = nil, caseNumber: String? = nil,
             caseYear: String? = nil, client: String? = nil, oppositeParty: String? = nil, ourSide: String? = nil) {
            self.name = name
            self.forumName = forumName
            self.caseType = caseType
            self.caseNumber = caseNumber
            self.caseYear = caseYear
            self.client = client
            self.oppositeParty = oppositeParty
            self.ourSide = ourSide
        }
    }

    /// The linked case's identity, for a matter that has none of its own.
    struct LinkedCaseInput: Equatable, Sendable {
        var courtName: String?
        var caseType: String?
        var caseNumber: String?
        var caseYear: String?

        init(courtName: String? = nil, caseType: String? = nil, caseNumber: String? = nil, caseYear: String? = nil) {
            self.courtName = courtName
            self.caseType = caseType
            self.caseNumber = caseNumber
            self.caseYear = caseYear
        }
    }

    private static func causeTitle(_ p: ListOfDatesInput) -> [(name: String, role: String)]? {
        let client = JSCompat.clean(p.client)
        let other = JSCompat.clean(p.oppositeParty)
        let side = (p.ourSide ?? "").lowercased()
        guard !client.isEmpty, !other.isEmpty, let theirRole = opposite[side] else { return nil }
        let ours = (name: client, role: sideLabelForTitle(side))
        let theirs = (name: other, role: theirRole)
        return firstNamed.contains(side) ? [ours, theirs] : [theirs, ours]
    }

    private static let orderDated = MatterPattern("^order dated\\b", caseInsensitive: true)
    private static let endsSentence = MatterPattern("[.!?:;]$")

    /// `eventText`: one entry in the Event column of a List of Dates.
    static func eventText(_ e: Entry) -> String {
        if e.src == .court, !e.own, let item = e.item {
            if e.kind == "hearing" {
                let h = hearingFacts(item)
                return "The matter was listed\(h.purpose.isEmpty ? "" : " for \(h.purpose)")\(h.coram.isEmpty ? "" : " before \(h.coram)")."
            }
            return orderDated.test(e.title) || e.title.isEmpty ? "Order passed by the Court." : e.title
        }
        let title = JSCompat.clean(e.title)
        let body = JSCompat.clean(e.body)
        if body.isEmpty { return title.isEmpty ? kindLabel(e.kind) : title }
        if title.isEmpty { return body }
        return endsSentence.test(title) ? "\(title) \(body)" : "\(title). \(body)"
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// `listOfDatesHtml`: the synopsis format — court, case, cause title, then one row per date.
    static func listOfDatesHtml(project p: ListOfDatesInput, linkedCase: LinkedCaseInput?, entries: [Entry]) -> String {
        let court = JSCompat.clean((p.forumName?.isEmpty == false) ? p.forumName : linkedCase?.courtName)
        var caseNo = caseNoFormal(number: p.caseNumber, type: p.caseType, year: p.caseYear)
        if caseNo.isEmpty {
            caseNo = caseNoFormal(number: linkedCase?.caseNumber, type: linkedCase?.caseType, year: linkedCase?.caseYear)
        }
        var out: [String] = []
        if !court.isEmpty { out.append("<p style=\"text-align:center\"><strong>IN THE \(esc(court.uppercased()))</strong></p>") }
        if !caseNo.isEmpty { out.append("<p style=\"text-align:center\"><strong>\(esc(caseNo.uppercased()))</strong></p>") }
        out.append("<p style=\"text-align:center\">IN THE MATTER OF:</p>")
        if let parties = causeTitle(p) {
            out.append("<p style=\"text-align:center\"><strong>\(esc(parties[0].name))</strong> … \(esc(parties[0].role))</p>")
            out.append("<p style=\"text-align:center\">VERSUS</p>")
            out.append("<p style=\"text-align:center\"><strong>\(esc(parties[1].name))</strong> … \(esc(parties[1].role))</p>")
        } else {
            let name = (p.name?.isEmpty == false) ? p.name! : "Untitled matter"
            out.append("<p style=\"text-align:center\"><strong>\(esc(name))</strong></p>")
        }
        out.append("<h1>LIST OF DATES AND EVENTS</h1>")
        var rows: [(day: String, events: [String])] = []
        for e in sorted(entries.filter { !$0.day.isEmpty }, newestFirst: false) {
            if let last = rows.last, last.day == e.day {
                rows[rows.count - 1].events.append(eventText(e))
            } else {
                rows.append((e.day, [eventText(e)]))
            }
        }
        out.append("<table><thead><tr><th>Date</th><th>Event</th></tr></thead><tbody>")
        for r in rows {
            out.append("<tr><td>\(esc(fmtDots(r.day)))</td><td>\(r.events.map { "<p>\(esc($0))</p>" }.joined())</td></tr>")
        }
        out.append("</tbody></table>")
        return out.joined(separator: "\n")
    }

    /// `totalsFromLedger`: rupee totals for a payload without `totals` (the rupee float when sent,
    /// else paise / 100; an unreadable amount is skipped).
    static func totalsFromLedger(_ ledger: [Ledger.Entry]) -> MatterRules.LedgerTotals {
        var t = MatterRules.LedgerTotals(billed: 0, received: 0, outstanding: 0, expenses: 0)
        for e in ledger {
            let amt = e.amount ?? Double(e.amountPaise ?? 0) / 100
            guard amt.isFinite else { continue }
            switch e.kind {
            case "fee": t.billed += amt
            case "payment": t.received += amt
            case "expense": t.expenses += amt
            default: break
            }
        }
        t.outstanding = t.billed - t.received
        return t
    }

    // MARK: - JavaScript values

    /// `String(v ?? '')` for a value read from JSON.
    static func jsString(_ v: JSONValue?) -> String {
        switch v {
        case nil, .null?: return ""
        case .string(let s)?: return s
        case .number(let n)?: return JSCompat.numberString(n)
        case .bool(let b)?: return b ? "true" : "false"
        case .array(let a)?: return a.map { $0 == .null ? "" : jsString($0) }.joined(separator: ",")
        case .object?: return "[object Object]"
        }
    }

    /// JavaScript truthiness of a JSON value.
    static func truthy(_ v: JSONValue?) -> Bool {
        switch v {
        case nil, .null?: return false
        case .bool(let b)?: return b
        case .number(let n)?: return n != 0 && !n.isNaN
        case .string(let s)?: return !s.isEmpty
        case .array?, .object?: return true
        }
    }
}
