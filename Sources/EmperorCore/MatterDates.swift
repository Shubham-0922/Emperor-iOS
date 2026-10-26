import Foundation

/// Calendar days for a matter's tasks and ledger — a port of the platform's
/// `src/components/projects/money/dates.js`, plus `hearingTone` from
/// `src/components/projects/shared.jsx`.
///
/// A task's `due_date` and an entry's `entry_date` are days (`YYYY-MM-DD`), compared and printed
/// from their own parts. Only "today" needs a zone, and it is India's: pass `today` from
/// `WireDate.todayKey()` (or `MatterRules.istDay()`), never from `Calendar.current`.
enum MatterDates {

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let dayPrefix = MatterPattern("^([0-9]{4})-([0-9]{2})-([0-9]{2})")

    /// `dayKeyOf`: `YYYY-MM-DD` for a real calendar day (a full ISO string keeps its date part);
    /// "" otherwise — 2026-02-30 included.
    static func dayKeyOf(_ value: String?) -> String {
        guard let m = dayPrefix.groups(in: value ?? ""),
              let y = Int(m[1]!), let mo = Int(m[2]!), let d = Int(m[3]!) else { return "" }
        // Date.UTC reads a year below 100 as 19xx, so the web finds no such day either.
        guard y > 99, (1...12).contains(mo), d >= 1, d <= JSCompat.daysInMonth(year: y, month: mo) else { return "" }
        return "\(m[1]!)-\(m[2]!)-\(m[3]!)"
    }

    /// `fmtDay`: "01 Oct 2026" — fixed English months, so September is "Sep"; "" for no day.
    static func fmtDay(_ value: String?) -> String {
        let k = dayKeyOf(value)
        guard !k.isEmpty else { return "" }
        let parts = k.split(separator: "-").map(String.init)
        return "\(parts[2]) \(months[Int(parts[1])! - 1]) \(parts[0])"
    }

    private static func dayNumber(_ key: String) -> Int {
        let p = key.split(separator: "-").compactMap { Int($0) }
        return JSCompat.daysFromCivil(p[0], p[1], p[2])
    }

    /// `daysBetween`: whole days from one day to another (negative when `to` is earlier).
    static func daysBetween(_ from: String?, _ to: String?) -> Int? {
        let a = dayKeyOf(from), b = dayKeyOf(to)
        guard !a.isEmpty, !b.isEmpty else { return nil }
        return dayNumber(b) - dayNumber(a)
    }

    /// `addDays`: the day `n` days after `from`; "" without a day.
    static func addDays(_ from: String?, _ n: Int) -> String {
        let k = dayKeyOf(from)
        guard !k.isEmpty else { return "" }
        return JSCompat.isoDay(epochMillis: Double(dayNumber(k) + n) * 86_400_000)
    }

    // MARK: - Tasks

    /// The groups of the Tasks section, in the order a practitioner reads a diary.
    enum TaskGroup: String, CaseIterable, Sendable {
        case overdue, week, later, nodate, done
        var title: String {
            switch self {
            case .overdue: return "Overdue"
            case .week: return "Due this week"
            case .later: return "Later"
            case .nodate: return "No date"
            case .done: return "Done"
            }
        }
    }

    /// "This week" is the next seven days.
    static let soonDays = 7

    /// `taskBucket`.
    static func taskBucket(status: String?, dueDate: String?, today: String) -> TaskGroup {
        if status == "done" { return .done }
        let k = dayKeyOf(dueDate)
        guard !k.isEmpty, let d = daysBetween(today, k) else { return .nodate }
        if d < 0 { return .overdue }
        if d <= soonDays { return .week }
        return .later
    }

    enum Tone: String, Sendable {
        case danger, warn, mute
    }

    /// A due date as a row shows it.
    struct DueInfo: Equatable, Sendable {
        let text: String
        let rel: String
        let tone: Tone
        let days: Int?
    }

    /// `dueInfo`: today is danger (the last day of limitation is an alarm, not a reminder); a
    /// finished task keeps its date and loses the urgency.
    static func dueInfo(_ dueDate: String?, today: String, done: Bool = false) -> DueInfo? {
        let k = dayKeyOf(dueDate)
        guard !k.isEmpty else { return nil }
        let d = daysBetween(today, k)
        let text = fmtDay(k)
        if done { return DueInfo(text: text, rel: "", tone: .mute, days: d) }
        guard let days = d else { return DueInfo(text: text, rel: "In nulld", tone: .warn, days: nil) }
        if days < 0 { return DueInfo(text: text, rel: "\(-days)d overdue", tone: .danger, days: days) }
        if days == 0 { return DueInfo(text: text, rel: "Today", tone: .danger, days: days) }
        if days == 1 { return DueInfo(text: text, rel: "Tomorrow", tone: .warn, days: days) }
        if days <= soonDays { return DueInfo(text: text, rel: "In \(days)d", tone: .warn, days: days) }
        return DueInfo(text: text, rel: "In \(days)d", tone: .mute, days: days)
    }

    /// Limitation and certified-copy dates sit above everything else in an open group.
    static let criticalKinds = ["limitation", "certified_copy"]
    private static let priorityRank = ["high": 0, "normal": 1, "low": 2]

    /// What `compareTasks` reads of a task.
    struct TaskSortKey: Equatable, Sendable {
        var status: String?
        var kind: String?
        var dueDate: String?
        var priority: String?
        var createdAt: String?
        var completedAt: String?
        var updatedAt: String?

        init(status: String? = nil, kind: String? = nil, dueDate: String? = nil, priority: String? = nil,
             createdAt: String? = nil, completedAt: String? = nil, updatedAt: String? = nil) {
            self.status = status
            self.kind = kind
            self.dueDate = dueDate
            self.priority = priority
            self.createdAt = createdAt
            self.completedAt = completedAt
            self.updatedAt = updatedAt
        }
    }

    private static func or(_ a: String?, _ b: String?) -> String {
        if let a, !a.isEmpty { return a }
        return b ?? ""
    }

    /// `compareTasks` as -1, 0 or 1. Done: newest completion first. Open: critical kinds, then
    /// by date (undated last), priority, and age.
    static func compareOrder(_ a: TaskSortKey, _ b: TaskSortKey) -> Int {
        if a.status == "done" && b.status == "done" {
            return JSCompat.localeCompare(or(b.completedAt, b.updatedAt), or(a.completedAt, a.updatedAt))
        }
        func crit(_ t: TaskSortKey) -> Int { criticalKinds.contains(t.kind ?? "") ? 0 : 1 }
        if crit(a) != crit(b) { return crit(a) - crit(b) }
        let da = dayKeyOf(a.dueDate), db = dayKeyOf(b.dueDate)
        if da != db {
            if !da.isEmpty && !db.isEmpty { return JSCompat.localeCompare(da, db) }
            return !da.isEmpty ? -1 : 1
        }
        let pa = priorityRank[a.priority ?? ""] ?? 1, pb = priorityRank[b.priority ?? ""] ?? 1
        if pa != pb { return pa < pb ? -1 : 1 }
        return JSCompat.localeCompare(a.createdAt ?? "", b.createdAt ?? "")
    }

    /// `compareTasks` as an ordering predicate.
    static func compare(_ a: TaskSortKey, _ b: TaskSortKey) -> Bool { compareOrder(a, b) < 0 }

    /// `groupTasks`: every group present, each sorted (stably, as the web's sort is).
    static func group<T>(_ items: [T], key: (T) -> TaskSortKey, today: String) -> [TaskGroup: [T]] {
        var out: [TaskGroup: [T]] = Dictionary(uniqueKeysWithValues: TaskGroup.allCases.map { ($0, []) })
        for item in items {
            let k = key(item)
            out[taskBucket(status: k.status, dueDate: k.dueDate, today: today), default: []].append(item)
        }
        for g in TaskGroup.allCases {
            out[g] = JSCompat.stableSorted(out[g] ?? []) { compareOrder(key($0), key($1)) }
        }
        return out
    }

    // MARK: - Hearings

    enum HearingToneKind: String, Sendable {
        case danger, warn, mute
    }

    /// A hearing date's urgency, as the matter list and workspace show it.
    struct HearingTone: Equatable, Sendable {
        let text: String
        let tone: HearingToneKind
        let days: Int
    }

    /// `hearingTone` (`shared.jsx`), counted in whole days of India's calendar. The web prints the
    /// date with `fmtDate` ("1 Sept 2026" under en-IN); this prints the matter screens' house form
    /// (`fmtDay`, "01 Sep 2026") so one screen does not show September two ways.
    static func hearingTone(_ raw: String?, today: String) -> HearingTone? {
        guard let raw, !raw.isEmpty, let ms = JSCompat.parseDate(raw) else { return nil }
        let day = MatterRules.istDay(epochMillis: ms)
        guard let days = daysBetween(today, day) else { return nil }
        let date = fmtDay(day)
        if days < 0 { return HearingTone(text: "\(date) · passed", tone: .mute, days: days) }
        if days == 0 { return HearingTone(text: "\(date) · today", tone: .danger, days: days) }
        if days == 1 { return HearingTone(text: "\(date) · tomorrow", tone: .warn, days: days) }
        if days <= soonDays { return HearingTone(text: "\(date) · in \(days)d", tone: .warn, days: days) }
        return HearingTone(text: date, tone: .mute, days: days)
    }
}
