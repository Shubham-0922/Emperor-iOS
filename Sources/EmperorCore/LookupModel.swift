import Foundation

/// What Fetch Orders needs to know about a record read from a court — a port of the platform's
/// `src/components/lookup/lookupModel.js` and the status words of its `Dossier.jsx`.
///
/// Titles, case numbers and side words are `MatterMeta`'s (already ported for matters), names are
/// tidied by `CourtNames`, days are printed and counted by `MatterRecord`. "Today" is always
/// India's day, passed in (`WireDate.todayKey()`), never the device's.
enum LookupModel {

    /// `caseNumberOf`: "W.P.(C) 12/2025".
    static func caseNumberOf(_ c: LookupRecord.Case) -> String {
        MatterMeta.lookupCaseNumber(caseType: c.caseType, caseNumber: c.caseNumber, caseYear: c.caseYear)
    }

    /// `titleOf`: the cause title tidied, else the case number, else "Untitled case".
    static func titleOf(_ c: LookupRecord.Case) -> String {
        MatterMeta.lookupTitle(title: c.title, caseType: c.caseType, caseNumber: c.caseNumber, caseYear: c.caseYear)
    }

    private static let disposedWords = MatterPattern("dispos|decided|dismiss|closed|withdrawn", caseInsensitive: true)

    /// `isDisposed`: whether the court's status says the case is over.
    static func isDisposed(_ status: String?) -> Bool {
        disposedWords.test(status ?? "")
    }

    private static let words: [String: String] = [
        "Pending": "Still going", "Disposed": "Decided", "Dismissed": "Dismissed",
        "Allowed": "Allowed", "Withdrawn": "Withdrawn",
    ]

    /// `statusWord`: the court's status in a client's words; nil when the court gave none.
    static func statusWord(_ status: String?) -> String? {
        guard let status, !status.isEmpty else { return nil }
        return words[status] ?? status
    }

    private static let roomNumber = MatterPattern("^[0-9]+[A-Za-z]?$")

    /// `roomOf`: "Court 51", or the court's own words when its number is a place.
    static func roomOf(_ raw: String?) -> String {
        let t = JSCompat.trim(JSCompat.collapse(raw ?? ""))
        if t.isEmpty { return "" }
        return roomNumber.test(t) ? "Court \(t)" : MatterRecord.plainCourtText(t)
    }

    /// `ago`: how long ago, or how far off, in a client's words — "3 weeks ago", "in 2 days",
    /// "today"; "" without a day.
    static func ago(_ day: String?, today: String) -> String {
        guard let d = MatterRecord.daysFromToday(day, today: today) else { return "" }
        if d == 0 { return "today" }
        let n = abs(d)
        let unit: String
        if n >= 365 {
            let years = n / 365
            unit = "\(years) year\(years == 1 ? "" : "s")"
        } else if n >= 60 {
            unit = "\(n / 30) months"
        } else if n >= 14 {
            unit = "\(n / 7) weeks"
        } else {
            unit = "\(n) day\(n == 1 ? "" : "s")"
        }
        return d < 0 ? "\(unit) ago" : "in \(unit)"
    }

    /// One row of the timeline: a hearing (past or upcoming) or an order.
    struct TimelineRow: Equatable, Sendable, Identifiable {
        enum Kind: String, Sendable { case next, hearing, order }
        var key: String
        var day: String
        var kind: Kind
        var title: String
        var sub: String

        var id: String { key }
    }

    /// `timelineOf`: hearings and orders together, newest first. An order with no day is left
    /// out, as is a hearing with none (the server sends none such).
    static func timelineOf(_ record: LookupRecord, today: String) -> [TimelineRow] {
        var rows: [TimelineRow] = []
        for h in record.hearings {
            guard let day = h.date else { continue }
            let purpose = MatterRecord.plainCourtText(h.purpose)
            let kind: TimelineRow.Kind = day > today ? .next : .hearing
            rows.append(TimelineRow(
                key: "h\(day)\(h.purpose ?? "null")", day: day, kind: kind,
                title: purpose.isEmpty ? "Listed before the court" : purpose,
                sub: roomOf(h.courtNo)))
        }
        for o in record.orders {
            guard let day = o.date, !day.isEmpty else { continue }
            let title = MatterRecord.orderTitle(o.title)
            rows.append(TimelineRow(
                key: "o\(day)\(o.url ?? "null")", day: day, kind: .order,
                title: title.isEmpty ? "Order" : title, sub: ""))
        }
        // A stable sort, as JavaScript's: equal days keep the order they were added in.
        let indexed = rows.enumerated().map { ($0.offset, $0.element) }
        let sorted = indexed.sorted { a, z in
            if a.1.day != z.1.day { return a.1.day > z.1.day }
            return a.0 < z.0
        }
        return sorted.map { $0.1 }
    }

    /// `summaryText`: the lines people paste into a message.
    static func summaryText(_ record: LookupRecord, today: String) -> String {
        let c = record.case
        var lines: [String] = [titleOf(c)]
        let court = c.courtName ?? ""
        lines.append("\(court) · \(caseNumberOf(c))")
        if let status = c.status, !status.isEmpty { lines.append("Status: \(status)") }
        if let next = c.nextHearing, !next.isEmpty, next >= today {
            lines.append("Next hearing: \(MatterRecord.fmtDay(next))")
        }
        if let first = record.orders.first {
            lines.append("Latest order: \(MatterRecord.fmtDay(first.date))")
        }
        lines.append("\(record.orders.count) orders · \(record.hearings.count) hearings")
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// `yearsOf`: the years the orders span, newest first, for the filter chips.
    static func yearsOf(_ orders: [LookupRecord.Order]) -> [String] {
        var seen = Set<String>()
        var years: [String] = []
        for o in orders {
            let y = String(String(decoding: Array((o.date ?? "").utf16.prefix(4)), as: UTF16.self))
            guard !y.isEmpty, !seen.contains(y) else { continue }
            seen.insert(y)
            years.append(y)
        }
        return years.sorted().reversed()
    }

    /// The orders a year chip shows: all of them for "" (All), else those dated in that year.
    static func orders(_ orders: [LookupRecord.Order], inYear year: String) -> [LookupRecord.Order] {
        guard !year.isEmpty else { return orders }
        return orders.filter { ($0.date ?? "").hasPrefix(year) }
    }

    /// One side of the case: its names and counsel tidied, and its lead party.
    struct Side: Equatable, Sendable {
        var names: [String]
        var counsel: [String]
        var lead: String
    }

    /// `sidesOf`: the first-named side (petitioner, plaintiff, appellant) and the other.
    static func sidesOf(_ parties: LookupRecord.Parties) -> (first: Side, second: Side) {
        func tidy(_ list: [String]) -> [String] { list.map { CourtNames.tidy($0) } }
        func lead(_ list: [String]) -> String { list.first.map { CourtNames.tidy($0) } ?? "" }
        let first = Side(names: tidy(parties.petitioners), counsel: tidy(parties.petitionerAdvocates),
                         lead: lead(parties.petitioners))
        let second = Side(names: tidy(parties.respondents), counsel: tidy(parties.respondentAdvocates),
                          lead: lead(parties.respondents))
        return (first, second)
    }

    /// The next hearing still to come, or nil (`Dossier.jsx`: `nextHearing >= today`).
    static func upcoming(_ c: LookupRecord.Case, today: String) -> String? {
        guard let next = c.nextHearing, !next.isEmpty, next >= today else { return nil }
        return next
    }

    /// "Read from the court just now · not saved to your account".
    static func readFootnote(cached: Bool) -> String {
        let when = cached ? "a few minutes ago" : "just now"
        return "Read from the court \(when) · not saved to your account"
    }

    /// A court fee as the dossier prints it: "₹1,25,000" (`toLocaleString('en-IN')`), or "—".
    static func feeText(_ amount: Double?) -> String {
        guard let amount else { return "—" }
        return "₹" + JSCompat.indianNumber(amount)
    }

    /// A connected case's line: "W.P. 12/2020 · Delhi · order 01 Oct 2020".
    static func connectedText(_ x: LookupRecord.Connected) -> String {
        var text = (x.caseNo?.isEmpty == false) ? x.caseNo! : "Connected case"
        if let court = x.court, !court.isEmpty { text += " · \(court)" }
        if let day = x.orderDate, !day.isEmpty { text += " · order \(MatterRecord.fmtDay(day))" }
        return text
    }

    /// The Next hearing tile's line under the date: "Today", "Tomorrow", "in 9 days".
    static func dueWords(_ days: Int) -> String {
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return "in \(days) days"
    }
}
