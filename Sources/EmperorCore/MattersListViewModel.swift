import Foundation
#if canImport(Darwin)
import Observation
#endif

/// The matters of the Matters tab's "All matters" segment — the web's `/matters` list
/// (`src/pages/Projects.jsx`): every matter, archived ones included, filtered on the phone by
/// status (Active first), practice area and the search, and sorted by recent activity, next
/// hearing or name.
///
/// The tracked cases under it are `CaseListViewModel`'s docket, minus every case a matter links
/// (`linkedCaseIDs`, archived matters included — an archived matter still owns its case).
///
/// See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class MattersListViewModel {

    /// The status menu: one status, or all of them.
    enum StatusScope: String, CaseIterable, Sendable {
        case active, onHold = "on_hold", disposed, archived, all

        var label: String {
            switch self {
            case .all: return "All statuses"
            default: return MatterVocabulary.ProjectStatus(rawValue: rawValue)!.label
            }
        }

        /// How the summary names a count in this scope ("3 matters on hold").
        func words(_ n: Int) -> String {
            let s = n == 1 ? "" : "s"
            switch self {
            case .active: return "\(n) active matter\(s)"
            case .onHold: return "\(n) matter\(s) on hold"
            case .disposed: return "\(n) disposed matter\(s)"
            case .archived: return "\(n) archived matter\(s)"
            case .all: return "\(n) matter\(s)"
            }
        }
    }

    enum Sort: String, CaseIterable, Sendable {
        case recent, hearing, name

        var label: String {
            switch self {
            case .recent: return "Recent activity"
            case .hearing: return "Next hearing"
            case .name: return "Name A–Z"
            }
        }
    }

    /// One choice of the practice-area menu. `key` nil is "All practice areas".
    struct AreaOption: Equatable, Identifiable, Sendable {
        let key: String?
        let label: String
        var id: String { key ?? "" }
    }

    /// What a filter that hides every matter says, and the ways out of it.
    struct NoMatches: Equatable, Sendable {
        let title: String
        let message: String
        /// "Clear search and filters", when a search or an area is set.
        let clearTitle: String?
        /// "Show all statuses", unless that is already the scope.
        let showAllTitle: String?
    }

    /// The practice-area key for a matter that has none.
    static let noArea = "__none"

    private(set) var projects: [Project] = []
    private(set) var state: LoadState = .idle
    /// Uploaded banners, by `bannerKey`.
    private(set) var banners: [String: Data] = [:]

    /// The search — shared with the docket's field on the same screen.
    var query = ""
    var status: StatusScope = .active
    /// A practice-area key, `noArea`, or nil for every area.
    var area: String?
    var sort: Sort = .recent

    private let service: any ProjectProviding
    private let now: @Sendable () -> Date
    private var bannerRequests: Set<String> = []

    init(service: any ProjectProviding, now: @escaping @Sendable () -> Date = { Date() }) {
        self.service = service
        self.now = now
    }

    var presentation: ListPresentation {
        ListPresentation(state: state, isEmpty: projects.isEmpty)
    }

    /// Today in India, as hearing dates count it.
    var todayKey: String { MatterRules.istDay(now()) }

    // MARK: - Counts and menus

    /// Matters per status; an unknown status counts as active. `.all` is every matter.
    var counts: [StatusScope: Int] {
        var c: [StatusScope: Int] = [.active: 0, .onHold: 0, .disposed: 0, .archived: 0]
        for p in projects {
            let key = StatusScope(rawValue: p.statusKey.rawValue) ?? .active
            c[key, default: 0] += 1
        }
        c[.all] = projects.count
        return c
    }

    /// "Active · 3": a status with its count.
    func statusLabel(_ scope: StatusScope) -> String {
        "\(scope.label) · \(counts[scope] ?? 0)"
    }

    /// The practice areas the matters actually have, in the vocabulary's order, then any the
    /// vocabulary does not know, then "No practice area" — and the chosen one, even if no matter
    /// has it any more, so the menu never shows a selection it does not hold.
    var areaOptions: [AreaOption] {
        let present = Set(projects.map { areaKey($0) })
        var options = [AreaOption(key: nil, label: "All practice areas")]
        for area in MatterVocabulary.PracticeArea.allCases where present.contains(area.rawValue) {
            options.append(AreaOption(key: area.rawValue, label: area.label))
        }
        for key in present.sorted() where key != Self.noArea && MatterVocabulary.PracticeArea(rawValue: key) == nil {
            options.append(AreaOption(key: key, label: MatterMeta.practiceAreaLabel(key)))
        }
        if present.contains(Self.noArea), options.count > 1 {
            options.append(AreaOption(key: Self.noArea, label: "No practice area"))
        }
        if let area, !options.contains(where: { $0.key == area }) {
            options.append(AreaOption(key: area, label: area == Self.noArea ? "No practice area" : MatterMeta.practiceAreaLabel(area)))
        }
        return options
    }

    var areaLabel: String {
        areaOptions.first { $0.key == area }?.label ?? "All practice areas"
    }

    private func areaKey(_ p: Project) -> String {
        let a = p.practiceArea ?? ""
        return a.isEmpty ? Self.noArea : a
    }

    // MARK: - What is shown

    /// The matters in the chosen status.
    var scoped: [Project] {
        status == .all ? projects : projects.filter { $0.statusKey.rawValue == status.rawValue }
    }

    var isFiltering: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || area != nil
    }

    /// The matters the status, area and search let through, in the chosen order.
    var visible: [Project] {
        let term = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let bare = Self.squash(query)
        let list = scoped.filter { p in
            if let area, areaKey(p) != area { return false }
            guard !term.isEmpty else { return true }
            let text = Self.haystack(p)
            return text.lowercased().contains(term) || (bare.count >= 2 && Self.squash(text).contains(bare))
        }
        let today = todayKey
        switch sort {
        case .name:
            return JSCompat.stableSorted(list) { Self.byName($0, $1) }
        case .hearing:
            func key(_ p: Project) -> (Int, Int) {
                guard let h = MatterDates.hearingTone(p.nextHearingDateRaw, today: today) else { return (2, 0) }
                return h.days >= 0 ? (0, h.days) : (1, -h.days)
            }
            return JSCompat.stableSorted(list) { a, b in
                let ka = key(a), kb = key(b)
                if ka.0 != kb.0 { return ka.0 < kb.0 ? -1 : 1 }
                if ka.1 != kb.1 { return ka.1 < kb.1 ? -1 : 1 }
                return Self.byName(a, b)
            }
        case .recent:
            let at = Dictionary(list.map { p in
                (p.id, MatterMeta.activityAt(updated: p.updatedAtRaw, created: p.createdAtRaw,
                                             lastActivity: p.lastActivityRaw, now: now())?
                    .timeIntervalSince1970 ?? 0)
            }, uniquingKeysWith: { a, _ in a })
            return JSCompat.stableSorted(list) { a, b in
                let ta = at[a.id] ?? 0, tb = at[b.id] ?? 0
                if ta != tb { return ta > tb ? -1 : 1 }
                return Self.byName(a, b)
            }
        }
    }

    /// Hearings in the next seven days among the matters in scope — the chip that sorts by them.
    var hearingsThisWeek: Int {
        let today = todayKey
        return scoped.filter { p in
            guard let h = MatterDates.hearingTone(p.nextHearingDateRaw, today: today) else { return false }
            return h.days >= 0 && h.days <= 7
        }.count
    }

    /// "2 hearings in the next 7 days".
    var hearingsThisWeekText: String {
        let n = hearingsThisWeek
        return "\(n) hearing\(n == 1 ? "" : "s") in the next 7 days"
    }

    /// Every case some matter links — archived matters included — to leave off the docket.
    var linkedCaseIDs: Set<String> {
        Set(MatterMeta.matterByCase(projects.map { ($0.id, $0.linkedCaseID, $0.createdAtRaw) }).keys)
    }

    /// "3 active matters", or "1 of 3 active matters" while a search or area narrows it.
    var summary: String {
        (isFiltering ? "\(visible.count) of " : "") + status.words(scoped.count)
    }

    /// Set when there are matters but none in view.
    var noMatches: NoMatches? {
        guard !projects.isEmpty, visible.isEmpty else { return nil }
        let scope = status == .all ? "" : status.label.lowercased()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = scope.isEmpty ? "" : "\(scope) "
        let title: String
        let message: String
        if isFiltering {
            title = q.isEmpty ? "No \(lead)matter in that practice area" : "No \(lead)matter matches “\(q)”"
            message = "Try a client, a party, a case number or a CNR — or clear the search and filters."
        } else {
            title = "No \(scope) matters"
            message = "Matters with other statuses are under the Status menu."
        }
        return NoMatches(
            title: title, message: message,
            clearTitle: isFiltering ? "Clear search and filters" : nil,
            showAllTitle: status == .all ? nil : "Show all statuses")
    }

    func clearFilters() {
        query = ""
        area = nil
    }

    func showAllStatuses() { status = .all }

    // MARK: - Loading

    /// Every matter, archived ones included, always. A failed refresh keeps the rows on screen.
    func load() async {
        state = .loading
        do {
            projects = try await service.projects(includeArchived: true)
            state = .loaded
        } catch {
            state = .failed(LoadFailure(error))
        }
    }

    // MARK: - A row

    /// What a matter's row says — the web's `ProjectCard`, line by line.
    struct Card: Equatable, Sendable {
        enum Tone: String, Sendable { case danger, warn, mute, accent }

        let name: String
        /// The practice area's label, "" for none.
        let area: String
        let description: String
        /// "Ankit Bhalla (Petitioner)".
        let client: String
        /// "Punjab and Haryana High Court · CWP 4412/2025".
        let court: String
        /// "14 Oct 2026 · in 2d", with its urgency; a far-off hearing is accent, not grey.
        let hearing: (text: String, tone: Tone)?
        /// The next open task's due date; a date gone by is overdue, in danger.
        let taskDue: (text: String, tone: Tone)?
        /// "3 files · 1 chat · 2 open tasks" — only the counts the server sent.
        let counts: String
        let isHigh: Bool
        let status: MatterVocabulary.ProjectStatus

        static func == (a: Card, b: Card) -> Bool {
            a.name == b.name && a.area == b.area && a.description == b.description && a.client == b.client
                && a.court == b.court && a.hearing?.text == b.hearing?.text && a.hearing?.tone == b.hearing?.tone
                && a.taskDue?.text == b.taskDue?.text && a.taskDue?.tone == b.taskDue?.tone
                && a.counts == b.counts && a.isHigh == b.isHigh && a.status == b.status
        }

        /// The row read aloud as one sentence.
        var spoken: String {
            var parts = [name]
            if !area.isEmpty { parts.append(area) }
            if !client.isEmpty { parts.append(client) }
            if !court.isEmpty { parts.append(court) }
            if let hearing { parts.append("Next hearing \(hearing.text)") }
            if let taskDue { parts.append("Task due \(taskDue.text)") }
            if !counts.isEmpty { parts.append(counts) }
            if isHigh { parts.append("High priority") }
            parts.append(status.label)
            return parts.joined(separator: ". ")
        }
    }

    func card(_ p: Project) -> Card {
        let today = todayKey
        func tone(_ t: MatterDates.HearingToneKind) -> Card.Tone { Card.Tone(rawValue: t.rawValue) ?? .mute }
        var hearing: (String, Card.Tone)?
        if let h = MatterDates.hearingTone(p.nextHearingDateRaw, today: today) {
            hearing = (h.text, h.tone == .mute && h.days >= 0 ? .accent : tone(h.tone))
        }
        var due: (String, Card.Tone)?
        if (p.openTasks ?? 0) > 0, let raw = p.nextTaskDueRaw, !raw.isEmpty,
           let t = MatterDates.hearingTone(raw, today: today) {
            due = t.days < 0
                ? ("\(MatterDates.fmtDay(MatterRecord.dayKey(raw))) · overdue", .danger)
                : (t.text, tone(t.tone))
        }
        func count(_ n: Int?, _ one: String, _ many: String) -> String? {
            n.map { "\($0) \($0 == 1 ? one : many)" }
        }
        let counts = [count(p.fileCount, "file", "files"), count(p.chatCount, "chat", "chats"),
                      count(p.openTasks, "open task", "open tasks")].compactMap { $0 }.joined(separator: " · ")
        return Card(
            name: p.displayName, area: MatterMeta.practiceAreaLabel(p.practiceArea),
            description: (p.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            client: p.clientLine,
            court: [p.courtName, p.caseRef].filter { !$0.isEmpty }.joined(separator: " · "),
            hearing: hearing, taskDue: due, counts: counts, isHigh: p.isHighPriority, status: p.statusKey)
    }

    // MARK: - Banners

    /// Where an uploaded banner is kept: per matter and per edit, so a new picture is fetched.
    nonisolated static func bannerKey(_ p: Project) -> String { "\(p.id)|\(p.updatedAtRaw ?? "")" }

    func bannerImage(for p: Project) -> Data? {
        p.hasBannerImage ? banners[Self.bannerKey(p)] : nil
    }

    /// Fetches an uploaded banner once; a failure leaves the preset showing.
    func loadBanner(for p: Project) async {
        guard p.hasBannerImage else { return }
        let key = Self.bannerKey(p)
        guard banners[key] == nil, !bannerRequests.contains(key) else { return }
        bannerRequests.insert(key)
        if let data = try? await service.bannerImage(projectID: p.id, version: p.updatedAtRaw ?? "") {
            banners[key] = data
        }
    }

    // MARK: - Matching and ordering

    /// What the search reads: name, client, opposite party, case reference, number, CNR, court.
    nonisolated static func haystack(_ p: Project) -> String {
        [p.name, p.client, p.oppositeParty, p.caseRef, p.caseNumber, p.cnr, p.forumName]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • ")
    }

    /// Letters and digits only, lower case: "W.P.(C) 4412/2025" → "wpc44122025".
    nonisolated static func squash(_ s: String) -> String {
        String(String.UnicodeScalarView(s.lowercased().unicodeScalars.filter {
            (48...57).contains($0.value) || (97...122).contains($0.value)
        }))
    }

    /// Names compared as the web's `localeCompare(…, { numeric: true, sensitivity: 'base' })`:
    /// case and accents ignored, runs of digits by value.
    nonisolated static func byName(_ a: Project, _ b: Project) -> Int {
        naturalCompare(a.name ?? "", b.name ?? "")
    }

    nonisolated static func naturalCompare(_ a: String, _ b: String) -> Int {
        let ca = chunks(fold(a)), cb = chunks(fold(b))
        for (x, y) in zip(ca, cb) {
            if let nx = Double(x), let ny = Double(y), x.first?.isNumber == true, y.first?.isNumber == true {
                if nx != ny { return nx < ny ? -1 : 1 }
                continue
            }
            let c = JSCompat.localeCompare(x, y)
            if c != 0 { return c }
        }
        return ca.count == cb.count ? 0 : (ca.count < cb.count ? -1 : 1)
    }

    private nonisolated static func fold(_ s: String) -> String {
        String(String.UnicodeScalarView(
            s.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars.filter {
                !(0x300...0x36F).contains($0.value)
            }))
    }

    /// Runs of ASCII digits and runs of everything else.
    private nonisolated static func chunks(_ s: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inDigits: Bool?
        for ch in s {
            let digit = ch.isASCII && ch.isNumber
            if inDigits != nil, inDigits != digit {
                out.append(current)
                current = ""
            }
            current.append(ch)
            inDigits = digit
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
