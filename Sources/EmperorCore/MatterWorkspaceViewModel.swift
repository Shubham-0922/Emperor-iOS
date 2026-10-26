import Foundation
#if canImport(Darwin)
import Observation
#endif

/// One matter's workspace — the web's `src/pages/ProjectWorkspace.jsx` and its read-only
/// sections: the header over the banner, the section bar with its counts, and Overview,
/// Chronology, Court, Tasks, Fees and People. Ask, Files and Drafts join the bar once
/// `MatterAvailability.contentSections` is on.
///
/// Every reading rule is the web's own, ported in `MatterRecord`, `MatterDates`, `Ledger`,
/// `MatterMeta` and `MatterSetup`; this type only assembles them for the screen.
///
/// See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class MatterWorkspaceViewModel {

    typealias Section = MatterVocabulary.MatterSection
    typealias Tone = MatterDates.Tone

    enum State: Equatable, Sendable {
        case idle, loading, loaded
        /// The server says the matter is not there, or not this user's.
        case missing
        case failed(LoadFailure)
    }

    /// A small number in the section bar: things waiting, never totals for their own sake.
    struct NavCount: Equatable, Sendable {
        var count: Int?
        /// Court: linked — a dot, not a number.
        var dot = false
        /// Tasks: one is overdue.
        var danger = false
    }

    /// The header over the banner.
    struct Header: Equatable, Sendable {
        let name: String
        let status: MatterVocabulary.ProjectStatus
        let next: MatterRecord.NextHearing?
        /// "Next hearing 14 Oct 2026 · in 2 days", or "No hearing date".
        let nextText: String
        /// danger today and tomorrow, warn within the week, accent further out, mute when passed.
        let nextTone: HearingChipTone
        let forum: String
        let caseNo: String
        /// "CNR" or "Diary no.".
        let cnrLabel: String
        let cnr: String
        let side: String
        let client: String
        let other: String
        let notFiled: Bool

        /// "Ankit Bhalla (Petitioner) v. State" — whoever is named.
        var parties: String {
            var out = client
            if !client.isEmpty, !side.isEmpty { out += " (\(side))" }
            if !other.isEmpty { out += client.isEmpty ? "v. \(other)" : " v. \(other)" }
            return out
        }

        /// "Delhi High Court · W.P.(C) 4412/2025".
        var forumLine: String { [forum, caseNo].filter { !$0.isEmpty }.joined(separator: " · ") }
    }

    enum HearingChipTone: String, Sendable { case danger, warn, accent, mute }

    /// Overview's "Where things stand": one sentence and the line under it.
    struct Standing: Equatable, Sendable {
        let headline: String
        let detail: String
    }

    /// Overview's To do tile.
    struct TodoSummary: Equatable, Sendable {
        let open: Int
        let overdue: Int
        let rows: [TodoRow]
    }

    struct TodoRow: Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        let dueText: String
        let tone: Tone
        let isHigh: Bool
    }

    /// Overview's Fees tile.
    struct FeesSummary: Equatable, Sendable {
        let isEmpty: Bool
        let paid: Double
        let stillDue: Double
        let billed: Double
        let spent: Double
        /// Received out of billed, when anything was billed.
        let percent: Int?
    }

    /// Overview's Latest order tile.
    struct LatestOrder: Equatable, Sendable {
        let title: String
        /// "12 Oct 2026 · 3 days ago".
        let when: String
        /// From the court's record, rather than entered by hand.
        let fromCourt: Bool
        let count: Int
    }

    /// A row of the Tasks section.
    struct TaskRow: Equatable, Identifiable, Sendable {
        let task: ProjectTask
        let kindLabel: String
        /// Limitation and certified-copy tasks still open.
        let critical: Bool
        let due: MatterDates.DueInfo?
        /// "Done 01 Oct 2026", for a finished task.
        let doneText: String
        var id: String { task.id }
        var title: String { (task.title ?? "").isEmpty ? "Untitled task" : task.title! }
    }

    struct TaskGroupRows: Equatable, Identifiable, Sendable {
        let group: MatterDates.TaskGroup
        let rows: [TaskRow]
        var id: String { group.rawValue }
    }

    /// One of the four totals at the head of Fees.
    struct FeeTile: Equatable, Identifiable, Sendable {
        enum Tone: String, Sendable { case plain, success, warning, accent }
        let label: String
        let value: String
        let detail: String
        let tone: Tone
        var id: String { label }
    }

    /// One of Fees' three columns.
    struct FeeColumn: Equatable, Identifiable, Sendable {
        let kind: String
        let title: String
        let total: String
        /// Every entry of the kind; `entries` is after the category filter.
        let count: Int
        let entries: [FeeRow]
        let empty: String
        var id: String { kind }
    }

    struct FeeRow: Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        let amount: String
        let date: String
        /// The payment's mode, or the expense's category when it has a title of its own.
        let badge: String?
        let reference: String?
        let receipt: String?
        let notes: String?
    }

    struct PeopleGroup: Equatable, Identifiable, Sendable {
        let role: MatterVocabulary.PeopleRole
        let people: [ProjectPerson]
        var id: String { role.rawValue }
    }

    /// One part of the court record, as the Court section lists it.
    struct CourtGroup: Equatable, Identifiable, Sendable {
        let key: String
        let title: String
        let rows: [CourtRow]
        /// Said when the record has none.
        let empty: String
        var id: String { key }
    }

    struct CourtRow: Equatable, Identifiable, Sendable {
        let id: String
        /// "12 Oct 2026", or "—".
        let date: String
        /// "in 2 days", for a hearing still ahead.
        let rel: String?
        let title: String
        let lines: [String]
        /// An application's status, or "Supplementary list".
        let badge: String?
        let badgeTone: BadgeTone
    }

    enum BadgeTone: String, Sendable { case neutral, success, warning, danger }

    /// The parties of the court record, by side.
    struct CourtParties: Equatable, Sendable {
        var first: [String] = []
        var firstCounsel: [String] = []
        var second: [String] = []
        var secondCounsel: [String] = []
        var others: [String] = []
    }

    // MARK: - State

    let projectID: String
    private(set) var detail: ProjectDetail?
    private(set) var state: State = .idle
    /// A refresh that failed while a record was on screen; the view shows and clears it.
    var toast: String?
    var section: Section = .overview
    /// The chronology's order.
    var newestFirst = true
    /// The expense category Fees is narrowed to, or nil.
    var feeCategory: String?
    /// The uploaded banner, once fetched.
    private(set) var bannerData: Data?

    private let fileCount: Int?
    private let service: any ProjectProviding
    private let now: @Sendable () -> Date
    private var bannerVersion: String?

    /// - Parameters:
    ///   - section: the section to open on, as a route names it; an unknown or unavailable one
    ///     opens the overview.
    ///   - fileCount: the matter's file count from the list, when it came from there — the
    ///     detail route does not carry it.
    init(
        projectID: String, service: any ProjectProviding, section: String? = nil,
        fileCount: Int? = nil, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.projectID = projectID
        self.service = service
        self.fileCount = fileCount
        self.now = now
        if let section, let wanted = Section(rawValue: section), Self.visibleSections.contains(wanted) {
            self.section = wanted
        }
    }

    var project: Project? { detail?.project }
    var title: String { project?.displayName ?? "Matter" }
    var todayKey: String { MatterRules.istDay(now()) }

    // MARK: - Loading

    /// Fetches the matter. A failure while a record is on screen keeps it and says so in
    /// `toast`; a 404 with the server's word says the matter is gone.
    func load() async {
        if detail == nil { state = .loading }
        do {
            let fresh = try await service.project(id: projectID)
            detail = fresh
            state = .loaded
        } catch {
            if Self.isMissing(error) {
                detail = nil
                state = .missing
            } else if detail != nil {
                state = .loaded
                toast = LoadFailure(error).message.isEmpty
                    ? "Could not refresh this matter." : LoadFailure(error).message
            } else {
                state = .failed(LoadFailure(error))
            }
        }
    }

    func reload() async { await load() }

    /// The next hearing a chronology write answered with, shown at once; the reload that
    /// follows brings the rest of the matter in step.
    func applyNextHearing(_ raw: String?) {
        guard var fresh = detail else { return }
        fresh.project.nextHearingDateRaw = raw
        detail = fresh
    }

    /// Whether a failure means "this matter is not there" (`ProjectService.project`).
    nonisolated static func isMissing(_ error: Error) -> Bool {
        guard case .server(404, let message)? = error as? APIError else { return false }
        return message == ProjectService.projectGoneMessage
    }

    /// Fetches an uploaded banner once per version; a failure leaves the preset.
    func loadBanner() async {
        guard let project, project.hasBannerImage else { return }
        let version = project.updatedAtRaw ?? ""
        guard bannerVersion != version else { return }
        bannerVersion = version
        bannerData = try? await service.bannerImage(projectID: project.id, version: version)
    }

    // MARK: - Sections

    nonisolated static var visibleSections: [Section] {
        Section.allCases.filter {
            MatterAvailability.contentSections || !MatterAvailability.contentSectionKeys.contains($0)
        }
    }

    var visibleSections: [Section] { Self.visibleSections }

    private var courtItems: [MatterRecord.CourtItem] { (detail?.courtHistory ?? []).map(\.recordItem) }

    /// The merged chronology, unsorted.
    private var entries: [MatterRecord.Entry] {
        MatterRecord.chronology(updates: (detail?.updates ?? []).map(\.recordUpdate), court: courtItems)
    }

    /// `navCounts`.
    var navCounts: [Section: NavCount] {
        guard let detail else { return [:] }
        let today = todayKey
        var out: [Section: NavCount] = [:]
        if !detail.chats.isEmpty { out[.ask] = NavCount(count: detail.chats.count) }
        let dated = entries.count
        if dated > 0 { out[.chronology] = NavCount(count: dated) }
        if detail.linkedCase != nil { out[.court] = NavCount(dot: true) }
        let open = detail.tasks.filter { ($0.status ?? "open") != "done" }
        if !open.isEmpty {
            let overdue = open.contains { t in
                guard let due = t.dueDateRaw, !due.isEmpty else { return false }
                let day = MatterRecord.dayKey(due)
                return !day.isEmpty && day < today
            }
            out[.tasks] = NavCount(count: open.count, danger: overdue)
        }
        if !detail.people.isEmpty { out[.people] = NavCount(count: detail.people.count) }
        return out
    }

    // MARK: - Header

    var nextHearing: MatterRecord.NextHearing? {
        guard let detail else { return nil }
        return MatterRecord.nextHearing(
            projectNext: detail.project.nextHearingDateRaw, caseNext: detail.linkedCase?.nextHearingDateRaw,
            court: courtItems, today: todayKey)
    }

    var header: Header? {
        guard let detail else { return nil }
        let p = detail.project
        let linked = detail.linkedCase
        let next = nextHearing
        var forum = p.forumName ?? ""
        if forum.isEmpty { forum = linked?.courtName ?? "" }
        if forum.isEmpty, let type = p.forumType, !type.isEmpty, type != "other" {
            forum = MatterVocabulary.Forum.of(type).label
        }
        var caseNo = MatterRecord.caseNoLabel(number: p.caseNumber, type: p.caseType, year: p.caseYear)
        if caseNo.isEmpty, let linked {
            caseNo = MatterRecord.caseNoLabel(number: linked.caseNumber, type: linked.caseType, year: linked.caseYear)
        }
        var cnr = p.cnr ?? ""
        if cnr.isEmpty { cnr = linked?.cnr ?? "" }
        let (text, tone) = Self.hearingChip(next)
        return Header(
            name: p.displayName, status: p.statusKey, next: next, nextText: text, nextTone: tone,
            forum: forum, caseNo: caseNo, cnrLabel: cnr.isEmpty ? "" : MatterRecord.cnrLabel(cnr), cnr: cnr,
            side: MatterRecord.sideLabelForTitle(p.ourSide),
            client: (p.client ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            other: (p.oppositeParty ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            notFiled: p.isNotFiled)
    }

    /// The header's hearing chip: "Next hearing 14 Oct 2026 · in 2 days".
    nonisolated static func hearingChip(_ next: MatterRecord.NextHearing?) -> (String, HearingChipTone) {
        guard let next else { return ("No hearing date", .mute) }
        let tone: HearingChipTone
        switch next.days {
        case nil: tone = .mute
        case let d? where d < 0: tone = .mute
        case let d? where d <= 1: tone = .danger
        case let d? where d <= 7: tone = .warn
        default: tone = .accent
        }
        let when = (next.days ?? -1) < 0 ? "passed" : MatterRecord.relDays(next.days)
        return ("Next hearing \(MatterRecord.fmtDay(next.day)) · \(when)", tone)
    }

    // MARK: - Overview

    var setupSteps: [MatterSetup.Step] {
        guard let detail else { return [] }
        return MatterSetup.steps(project: detail.project, people: detail.people, fileCount: fileCount)
    }

    var setupPercent: Int { MatterSetup.percent(setupSteps) }

    /// "Where things stand".
    var standing: Standing? {
        guard let detail else { return nil }
        let p = detail.project
        let next = nextHearing
        if let next, let d = next.days, d >= 0 {
            let headline = d == 0 ? "The case is in court today."
                : d == 1 ? "The case is in court tomorrow." : "Next in court in \(d) days."
            let room = next.listing.map { MatterRecord.hearingFacts($0).where } ?? ""
            let court = detail.linkedCase?.courtName ?? p.forumName ?? ""
            let when = "\(MatterRecord.weekdayOf(next.day)), \(MatterRecord.fmtDay(next.day))"
            return Standing(headline: headline,
                            detail: [when, room, court].filter { !$0.isEmpty }.joined(separator: " · "))
        }
        if p.courtStatus == "not_filed" {
            return Standing(headline: "Not filed in court yet.",
                            detail: "Once it is filed, find the case and every hearing is tracked here for you.")
        }
        if detail.linkedCase != nil {
            if let next {
                return Standing(
                    headline: "Waiting for the next date.",
                    detail: "Last heard on \(MatterRecord.fmtDay(next.day)). The new date appears here as soon as the court gives one.")
            }
            return Standing(headline: "No hearing date yet.",
                            detail: "The date appears here as soon as the court lists the case.")
        }
        return Standing(headline: "Add the court case to follow it here.",
                        detail: "Find it by case number and its hearings, orders and next date fill in by themselves.")
    }

    /// The To do tile: open tasks, the late ones first, then the soonest, then the undated.
    var todo: TodoSummary {
        let today = todayKey
        let rank = ["high": 0, "normal": 1, "low": 2]
        let open = (detail?.tasks ?? []).filter { ($0.status ?? "open") != "done" }.map { t in
            (t: t, days: (t.dueDateRaw ?? "").isEmpty ? nil : MatterRecord.daysFromToday(t.dueDateRaw, today: today))
        }
        let sorted = JSCompat.stableSorted(open) { a, b in
            let ao = (a.days ?? 0) < 0 && a.days != nil, bo = (b.days ?? 0) < 0 && b.days != nil
            if ao != bo { return ao ? -1 : 1 }
            if (a.days == nil) != (b.days == nil) { return a.days == nil ? 1 : -1 }
            let d = (a.days ?? 0) - (b.days ?? 0)
            if d != 0 { return d < 0 ? -1 : 1 }
            let pa = rank[a.t.priority ?? ""] ?? 1, pb = rank[b.t.priority ?? ""] ?? 1
            return pa == pb ? 0 : (pa < pb ? -1 : 1)
        }
        let rows = sorted.prefix(3).map { item -> TodoRow in
            let (text, tone) = Self.dueOf(item.days, due: item.t.dueDateRaw)
            return TodoRow(id: item.t.id, title: (item.t.title ?? "").isEmpty ? "Untitled task" : item.t.title!,
                           dueText: text, tone: tone, isHigh: item.t.priority == "high")
        }
        return TodoSummary(open: open.count, overdue: open.filter { ($0.days ?? 0) < 0 }.count, rows: rows)
    }

    /// `dueOf` (Overview): "3d late", "Today", "Tomorrow", "In 4 days", the date, "No date".
    nonisolated static func dueOf(_ days: Int?, due: String?) -> (String, Tone) {
        guard let days else { return ("No date", .mute) }
        if days < 0 { return ("\(-days)d late", .danger) }
        if days == 0 { return ("Today", .danger) }
        if days == 1 { return ("Tomorrow", .warn) }
        if days <= 7 { return ("In \(days) days", .warn) }
        return (MatterRecord.fmtDay(due), .mute)
    }

    var feesSummary: FeesSummary {
        let t = detail?.totals ?? MatterRules.LedgerTotals(billed: 0, received: 0, outstanding: 0, expenses: 0)
        let empty = t.billed == 0 && t.received == 0 && t.expenses == 0 && (detail?.ledger ?? []).isEmpty
        let pct: Int? = t.billed > 0 ? min(100, Int((t.received / t.billed * 100).rounded())) : nil
        return FeesSummary(isEmpty: empty, paid: t.received, stillDue: max(0, t.outstanding),
                           billed: t.billed, spent: t.expenses, percent: pct)
    }

    /// The latest order: the court's, else one entered by hand.
    var latestOrder: LatestOrder? {
        guard let detail else { return nil }
        let today = todayKey
        let orders = MatterRecord.orders(courtItems)
        if let latest = orders.first {
            let raw = (latest.title?.isEmpty == false) ? latest.title : latest.data["title"]?.stringValue
            let title = MatterRecord.orderTitle(raw)
            return LatestOrder(
                title: title.isEmpty ? "Order" : title,
                when: Self.dayAndDistance(latest.itemDate, today: today), fromCourt: true, count: orders.count)
        }
        let own = detail.updates.filter { u in
            u.kind == "order" && !MatterRecord.dayKey(u.eventDateRaw ?? u.createdAtRaw).isEmpty
        }
        let latestOwn = JSCompat.stableSorted(own) { a, b in
            JSCompat.localeCompare(MatterRecord.dayKey(b.eventDateRaw ?? b.createdAtRaw),
                                   MatterRecord.dayKey(a.eventDateRaw ?? a.createdAtRaw))
        }.first
        guard let latestOwn else { return nil }
        return LatestOrder(
            title: (latestOwn.title ?? "").isEmpty ? "Order" : latestOwn.title!,
            when: Self.dayAndDistance(latestOwn.eventDateRaw ?? latestOwn.createdAtRaw, today: today),
            fromCourt: false, count: 1)
    }

    /// What the Latest order tile says when there is none.
    var latestOrderEmpty: String {
        guard let detail else { return "" }
        if detail.linkedCase != nil { return "No orders yet" }
        return detail.project.courtStatus == "not_filed" ? "Not filed yet" : "No court case added"
    }

    private nonisolated static func dayAndDistance(_ raw: String?, today: String) -> String {
        let rel = MatterRecord.relDays(MatterRecord.daysFromToday(raw, today: today))
        return [MatterRecord.fmtDay(raw), rel].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Overview's timeline: what has happened, newest first, tasks and the future left out.
    var timeline: [MatterRecord.Entry] {
        let today = todayKey
        let past = entries.filter { !$0.day.isEmpty && $0.kind != "task" && $0.day <= today }
        return Array(MatterRecord.sorted(past, newestFirst: true).prefix(8))
    }

    /// What an entry says on the timeline: "Listed in Court 71", not "Listed — LISTED IN COURT NO.71".
    nonisolated static func entryText(_ e: MatterRecord.Entry) -> String {
        let t = e.title
        let stripped: String
        if t.hasPrefix("Listed"), let r = t.range(of: "—") {
            let head = t[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            stripped = head == "Listed" ? String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces) : t
        } else {
            stripped = t
        }
        let plain = MatterRecord.plainCourtText(stripped)
        return plain.isEmpty ? MatterRecord.kindLabel(e.kind) : plain
    }

    // MARK: - Chronology

    func chronology(newestFirst: Bool) -> [MatterRecord.Entry] {
        MatterRecord.sorted(entries, newestFirst: newestFirst)
    }

    /// The badge an entry wears: who put it on the record.
    nonisolated static func sourceLabel(_ e: MatterRecord.Entry) -> String {
        MatterRecord.sourceLabel(e.src)
    }

    // MARK: - Tasks

    /// The tasks in the web's five groups — Overdue, Due this week, Later, No date, Done — each
    /// sorted; empty groups left out.
    var taskGroups: [TaskGroupRows] {
        guard let detail else { return [] }
        let today = todayKey
        let grouped = MatterDates.group(detail.tasks, key: \.taskKey, today: today)
        return MatterDates.TaskGroup.allCases.compactMap { group in
            let tasks = grouped[group] ?? []
            guard !tasks.isEmpty else { return nil }
            return TaskGroupRows(group: group, rows: tasks.map { taskRow($0, today: today) })
        }
    }

    private func taskRow(_ t: ProjectTask, today: String) -> TaskRow {
        let kind = t.kind.flatMap(MatterVocabulary.TaskKind.init(rawValue:)) ?? .task
        let done = t.isDone
        let doneDay = done ? MatterRecord.dayKey(t.completedAtRaw) : ""
        return TaskRow(
            task: t, kindLabel: kind.label,
            critical: MatterDates.criticalKinds.contains(kind.rawValue) && !done,
            due: MatterDates.dueInfo(t.dueDateRaw, today: today, done: done),
            doneText: doneDay.isEmpty ? "" : "Done \(MatterDates.fmtDay(doneDay))")
    }

    // MARK: - Fees

    var feeTiles: [FeeTile] {
        guard let detail else { return [] }
        let t = detail.totals
        let counts = feeKindCounts
        func plural(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
        let out = t.outstanding
        let outstanding: FeeTile = out < 0
            ? FeeTile(label: "Advance held", value: Ledger.rupees(-out), detail: "Received beyond fees billed", tone: .accent)
            : FeeTile(label: "Outstanding", value: Ledger.rupees(out),
                      detail: out > 0 ? "Billed, not yet received" : (t.billed > 0 ? "Settled" : "Nothing billed yet"),
                      tone: out > 0 ? .warning : .plain)
        return [
            FeeTile(label: "Billed", value: Ledger.rupees(t.billed),
                    detail: plural(counts["fee"] ?? 0, "fee entry", "fee entries"), tone: .plain),
            FeeTile(label: "Received", value: Ledger.rupees(t.received),
                    detail: plural(counts["payment"] ?? 0, "payment", "payments"),
                    tone: t.received > 0 ? .success : .plain),
            outstanding,
            FeeTile(label: "Expenses", value: Ledger.rupees(t.expenses),
                    detail: plural(counts["expense"] ?? 0, "expense", "expenses"), tone: .plain),
        ]
    }

    private var sortedLedger: [LedgerEntry] {
        guard let detail else { return [] }
        let byID = Dictionary(detail.ledger.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return Ledger.sorted(detail.ledger.map(\.ledgerEntry)).compactMap { byID[$0.id] }
    }

    private var feeKindCounts: [String: Int] {
        Dictionary(grouping: sortedLedger, by: { $0.kind ?? "" }).mapValues(\.count)
    }

    /// The expense categories, largest first — shown as chips when there is more than one.
    var feeCategories: [Ledger.CategoryTotal] {
        Ledger.expenseCategories((detail?.ledger ?? []).map(\.ledgerEntry))
    }

    /// The chosen category, if the expenses still have it.
    var activeFeeCategory: String? {
        guard let feeCategory, feeCategories.contains(where: { $0.key == feeCategory }) else { return nil }
        return feeCategory
    }

    var feeColumns: [FeeColumn] {
        guard let detail else { return [] }
        let t = detail.totals
        let columns: [(String, String, Double, String)] = [
            ("fee", "Fees billed", t.billed,
             "Record the fee agreed for this matter — per appearance, per stage, or a lump sum."),
            ("payment", "Payments received", t.received,
             "Record each payment with its UTR or cheque number; any one of them prints as a fee receipt."),
            ("expense", "Expenses", t.expenses,
             "Court fee, stamp duty, process fee, clerkage, copies, travel — what the matter costs, with the challan or slip."),
        ]
        let active = activeFeeCategory
        return columns.map { kind, title, sum, empty in
            let all = sortedLedger.filter { $0.kind == kind }
            var shown = all
            if kind == "expense", let active {
                shown = all.filter { e in
                    let known = e.category.flatMap(MatterVocabulary.ExpenseCategory.init(rawValue:)) != nil
                    return (e.category ?? "other") == active || (active == "other" && !known)
                }
            }
            return FeeColumn(kind: kind, title: title, total: Ledger.rupees(sum), count: all.count,
                             entries: shown.map(feeRow), empty: empty)
        }
    }

    private func feeRow(_ e: LedgerEntry) -> FeeRow {
        let kind = e.kind ?? ""
        let own = (e.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = !own.isEmpty ? own
            : kind == "expense" ? Ledger.categoryLabel(e.category) : kind == "payment" ? "Payment" : "Professional fee"
        var badge: String?
        if kind == "payment", let mode = e.mode, !mode.isEmpty {
            let label = Ledger.modeLabel(mode)
            badge = label.isEmpty ? mode : label
        } else if kind == "expense", !own.isEmpty {
            badge = Ledger.categoryLabel(e.category)
        }
        let ref = (e.reference ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = (e.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let date = MatterDates.fmtDay(e.entryDateRaw)
        return FeeRow(
            id: e.id, title: title, amount: Ledger.rupees(Double(e.paise) / 100),
            date: date.isEmpty ? "No date" : date, badge: badge,
            reference: ref.isEmpty || kind == "fee" ? nil : ref,
            receipt: (e.receiptFile ?? "").isEmpty ? nil : Ledger.receiptFileName(e.receiptFile),
            notes: notes.isEmpty ? nil : notes)
    }

    // MARK: - People

    /// The people by role, in the vocabulary's order, each role in the order its people were
    /// added; empty roles left out. An unknown role files under Other.
    var peopleByRole: [PeopleGroup] {
        guard let detail else { return [] }
        var by: [MatterVocabulary.PeopleRole: [ProjectPerson]] = [:]
        for p in detail.people {
            let role = p.role.flatMap(MatterVocabulary.PeopleRole.init(rawValue:)) ?? .other
            by[role, default: []].append(p)
        }
        return MatterVocabulary.PeopleRole.allCases.compactMap { role in
            guard let list = by[role], !list.isEmpty else { return nil }
            let sorted = JSCompat.stableSorted(list) { a, b in
                let c = JSCompat.localeCompare(a.createdAtRaw ?? "", b.createdAtRaw ?? "")
                return c != 0 ? c : JSCompat.localeCompare(a.name ?? "", b.name ?? "")
            }
            return PeopleGroup(role: role, people: sorted)
        }
    }

    /// `telHref`: a mobile dials in its +91 form; anything else with only its digits and a
    /// leading +. Nil for nothing to dial.
    nonisolated static func telLink(_ phone: String?) -> String? {
        let raw = (phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if IndianMobile.isValid(raw) { return "tel:\(IndianMobile.international(raw))" }
        var dial = ""
        for ch in raw where ch.isASCII && (ch.isNumber || ch == "+") {
            if ch == "+", !dial.isEmpty { continue }
            dial.append(ch)
        }
        return dial.isEmpty || dial == "+" ? nil : "tel:\(dial)"
    }

    /// `phoneShown`: a mobile as "+91 98765 43210", anything else as written.
    nonisolated static func phoneShown(_ phone: String?) -> String {
        let raw = (phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard IndianMobile.isValid(raw) else { return raw }
        return "+91 \(IndianMobile.local(raw))"
    }

    nonisolated static func mailLink(_ email: String?) -> String? {
        let raw = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.contains("@"), !raw.contains(" ") else { return nil }
        return "mailto:\(raw)"
    }

    // MARK: - Court

    /// The court-record copy for a matter without a linked case on screen.
    var courtNotice: String? {
        guard let detail, detail.linkedCase == nil else { return nil }
        if !(detail.project.linkedCaseID ?? "").isEmpty {
            return "The court case linked to this matter is no longer available to you — it is no longer tracked, or you left the team that tracks it."
        }
        if detail.project.courtStatus == "not_filed" {
            return "Not filed yet. Once it is, find the case here: its hearings, orders and next date then come from the court’s own record."
        }
        return "Not linked to a court case — link it to see the hearings, orders and next date from the court’s own record."
    }

    /// The linked case's facts: Stage, Status, Next date, Last synced.
    var linkedFacts: [(label: String, value: String)] {
        guard let c = detail?.linkedCase else { return [] }
        let synced = Self.syncedText(c.lastSyncedAtRaw) ?? "Not yet synced"
        let next = MatterRecord.fmtDay(c.nextHearingDateRaw)
        return [
            ("Stage", (c.stage ?? "").isEmpty ? "—" : c.stage!),
            ("Status", (c.status ?? "").isEmpty ? "—" : c.status!),
            ("Next date", next.isEmpty ? "—" : next),
            ("Last synced", synced),
        ]
    }

    /// "12 Oct 2026, 14:05" — the day and time in India; nil when it cannot be read.
    nonisolated static func syncedText(_ raw: String?) -> String? {
        guard let date = WireDate.parseAny(raw) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Kolkata")
        f.dateFormat = "yyyy-MM-dd|HH:mm"
        let parts = f.string(from: date).split(separator: "|").map(String.init)
        guard parts.count == 2 else { return nil }
        return "\(MatterDates.fmtDay(parts[0])), \(parts[1])"
    }

    /// The linked case's number and title lines.
    var linkedCaseTitle: (number: String, title: String)? {
        guard let c = detail?.linkedCase else { return nil }
        return (MatterRecord.caseNoLabel(number: c.caseNumber, type: c.caseType, year: c.caseYear), c.title ?? "")
    }

    /// The court record's parts: hearings and applications newest first, orders, parties, and
    /// connected matters when there are any.
    var courtGroups: [CourtGroup] {
        guard let detail, detail.linkedCase != nil else { return [] }
        let today = todayKey
        let items = detail.courtHistory
        func section(_ key: String) -> [CourtHistoryItem] { items.filter { $0.section == key } }
        func sortDesc(_ list: [CourtHistoryItem]) -> [CourtHistoryItem] {
            JSCompat.stableSorted(list) {
                JSCompat.localeCompare(MatterRecord.dayKey($1.itemDateRaw), MatterRecord.dayKey($0.itemDateRaw))
            }
        }
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let orders = MatterRecord.orders(items.map(\.recordItem)).compactMap { byID[$0.id] }
        var groups = [
            CourtGroup(key: "hearings", title: "Hearings",
                       rows: sortDesc(section("hearings")).map { hearingRow($0, today: today) },
                       empty: "No hearings on the court record yet."),
            CourtGroup(key: "orders", title: "Orders", rows: orders.map(orderRow),
                       empty: "No orders on the court record yet."),
            CourtGroup(key: "applications", title: "Applications",
                       rows: sortDesc(section("applications")).map(applicationRow),
                       empty: "No applications on the court record."),
        ]
        let connected = section("connected")
        if !connected.isEmpty {
            groups.append(CourtGroup(key: "connected", title: "Connected matters",
                                     rows: connected.map(connectedRow), empty: ""))
        }
        return groups
    }

    private func hearingRow(_ it: CourtHistoryItem, today: String) -> CourtRow {
        let h = MatterRecord.hearingFacts(it.recordItem)
        let day = MatterRecord.dayKey(it.itemDateRaw)
        let ahead = !day.isEmpty && day >= today
        var lines: [String] = []
        if !h.remarks.isEmpty { lines.append(h.remarks) }
        if !h.nextDate.isEmpty { lines.append("Next date given: \(MatterRecord.fmtDay(h.nextDate))") }
        if !h.where.isEmpty { lines.append(h.where) }
        if !h.coram.isEmpty { lines.append(h.coram) }
        return CourtRow(
            id: it.id, date: day.isEmpty ? "—" : MatterRecord.fmtDay(day),
            rel: ahead ? MatterRecord.relDays(MatterRecord.daysFromToday(day, today: today)) : nil,
            title: h.purpose.isEmpty ? "Listed" : h.purpose, lines: lines,
            badge: h.supplementary ? "Supplementary list" : nil, badgeTone: .neutral)
    }

    private func orderRow(_ it: CourtHistoryItem) -> CourtRow {
        let type = it.text("type")
        let shownType = type.lowercased() == "order" ? "" : type
        let sub = [shownType, it.text("summary")].filter { !$0.isEmpty }.joined(separator: " — ")
        let title = (it.title ?? "").isEmpty ? it.text("title") : it.title!
        return CourtRow(id: it.id, date: MatterRecord.fmtDay(it.itemDateRaw), rel: nil,
                        title: title.isEmpty ? "Order" : title, lines: sub.isEmpty ? [] : [sub],
                        badge: nil, badgeTone: .neutral)
    }

    private func applicationRow(_ it: CourtHistoryItem) -> CourtRow {
        let title = (it.title ?? "").isEmpty ? it.text("type") : it.title!
        let first = (it.subtitle ?? "").isEmpty ? it.text("iaNumber") : it.subtitle!
        let sub = [first, it.text("remarks")].filter { !$0.isEmpty }.joined(separator: " · ")
        let status = it.status ?? ""
        return CourtRow(
            id: it.id, date: (it.itemDateRaw ?? "").isEmpty ? "—" : MatterRecord.fmtDay(it.itemDateRaw), rel: nil,
            title: title.isEmpty ? "Application" : title, lines: sub.isEmpty ? [] : [sub],
            badge: status.isEmpty ? nil : status, badgeTone: Self.applicationTone(status))
    }

    private func connectedRow(_ it: CourtHistoryItem) -> CourtRow {
        let title = (it.title ?? "").isEmpty ? it.text("caseNumber") : it.title!
        let second = (it.subtitle ?? "").isEmpty ? it.text("court") : it.subtitle!
        let sub = [it.text("relation"), second, it.text("remarks")].filter { !$0.isEmpty }.joined(separator: " · ")
        return CourtRow(id: it.id, date: "", rel: nil, title: title.isEmpty ? "Connected matter" : title,
                        lines: sub.isEmpty ? [] : [sub], badge: nil, badgeTone: .neutral)
    }

    /// `appTone`: allowed or disposed is good news, pending waits, dismissed or withdrawn is not.
    nonisolated static func applicationTone(_ status: String) -> BadgeTone {
        let s = status.lowercased()
        if s.contains("allowed") || s.contains("disposed") { return .success }
        if s.contains("pending") { return .warning }
        if s.contains("dismiss") || s.contains("withdrawn") || s.contains("reject") { return .danger }
        return .neutral
    }

    /// The court record's parties by side. "Our advocate" and "client" mean a side only once the
    /// matter says which side the user is on.
    var courtParties: CourtParties? {
        guard let detail, detail.linkedCase != nil else { return nil }
        let rows = detail.courtHistory.filter { $0.section == "parties" }
        guard !rows.isEmpty else { return nil }
        let side = (detail.project.ourSide ?? "").lowercased()
        let firstSides: Set<String> = ["petitioner", "plaintiff", "appellant", "complainant", "applicant"]
        let secondSides: Set<String> = ["respondent", "defendant", "accused"]
        let ours: Int? = firstSides.contains(side) ? 1 : secondSides.contains(side) ? 2 : nil
        let theirs: Int? = ours == 1 ? 2 : ours == 2 ? 1 : nil
        var out = CourtParties()
        for it in rows {
            let role = (it.subtitle ?? "").isEmpty ? it.text("role") : it.subtitle!
            let r = role.lowercased()
            let name = (it.title ?? "").isEmpty ? it.text("name") : it.title!
            guard !name.isEmpty else { continue }
            let counsel = ["advocate", "aor", "counsel"].contains { r.contains($0) }
            let bucket: Int?
            if ["petitioner", "appellant", "applicant", "complainant", "plaintiff"].contains(where: { r.contains($0) }) {
                bucket = 1
            } else if ["respondent", "defendant", "accused"].contains(where: { r.contains($0) }) {
                bucket = 2
            } else if r.contains("our") || r.contains("client") {
                bucket = ours
            } else if r.contains("opposing") {
                bucket = theirs
            } else {
                bucket = nil
            }
            switch (bucket, counsel) {
            case (1?, false): out.first.append(name)
            case (1?, true): out.firstCounsel.append(name)
            case (2?, false): out.second.append(name)
            case (2?, true): out.secondCounsel.append(name)
            default: out.others.append(role.isEmpty ? name : "\(name) — \(role)")
            }
        }
        return out
    }
}
