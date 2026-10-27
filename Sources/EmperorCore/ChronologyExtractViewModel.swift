import Foundation
#if canImport(Darwin)
import Observation
#endif

/// "Build from documents" — the web's `BuildFlow` (`ChronologySection.jsx`): the AI reads the
/// matter's documents (all, or the ones picked) and proposes the dated events in them, each with
/// where it was found. Nothing is written until the person ticks it: a misread date must never
/// land unseen in a list that ends up in a court filing. Proposals that look like an entry already
/// on the record start unticked, so building twice does not double up. The ticked ones are saved
/// one by one, as AI entries.
///
/// See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class ChronologyExtractViewModel {

    enum Phase: Equatable, Sendable { case pick, reading, review, saving, failed }
    enum Scope: String, CaseIterable, Sendable { case all, some }

    /// One proposed event, as the review list edits it.
    struct Proposal: Equatable, Identifiable, Sendable {
        let id: Int
        /// `YYYY-MM-DD`, or "" when the AI's date is not a whole, real day.
        var day: String
        /// The date as the AI wrote it.
        let rawDate: String
        var title: String
        let details: String
        let kind: String
        let sourceRef: String
        /// Looks like an entry already on the record.
        let dup: Bool
        var on: Bool

        var undated: Bool { day.isEmpty }
        /// Dated and titled: the only proposals that can be saved.
        var usable: Bool { !day.isEmpty && !JSCompat.trim(title).isEmpty }
    }

    let projectID: String
    private(set) var phase: Phase = .pick
    private(set) var scope: Scope = .all
    /// The matter's files, once "Choose documents" is picked.
    private(set) var files: [MatterFile]?
    private(set) var filesError: String?
    private(set) var chosen: Set<String> = []
    var proposals: [Proposal] = []
    private(set) var error: String?
    private(set) var partial = false
    private(set) var message: String?
    private(set) var progress = (done: 0, total: 0)
    /// What the save did, once it is over.
    private(set) var result: String?
    private(set) var resultIsFailure = false

    private let service: any MatterFilesProviding
    private let writes: any ProjectWriting
    private let existing: [MatterRecord.Entry]
    /// Each read takes a ticket; closing the sheet abandons a read in flight.
    private var run = 0

    init(projectID: String, service: any MatterFilesProviding, writes: any ProjectWriting, existing: [MatterRecord.Entry]) {
        self.projectID = projectID
        self.service = service
        self.writes = writes
        self.existing = existing
    }

    static let intro = "Emperor reads this matter’s documents and proposes the dated events in them — agreements, notices, payments, filings, orders — each with the page it was found on. Nothing is added until you tick it."
    static let readingNote = "Long files can take a minute or two. Nothing is saved until you have reviewed the list; closing this window stops the review."

    // MARK: - Choosing

    func chooseAll() { scope = .all }

    func chooseSome() async {
        scope = .some
        guard files == nil else { return }
        do {
            let listing = try await service.listing(projectID: projectID)
            files = MatterFile.flatten(listing.folders + listing.files, root: listing.root).files
        } catch {
            files = []
            filesError = DisplayText.message(for: error)
        }
    }

    func toggleFile(_ file: MatterFile) {
        guard file.isReady else { return }
        if chosen.contains(file.id) { chosen.remove(file.id) } else { chosen.insert(file.id) }
    }

    var canStart: Bool { phase == .pick && (scope == .all || !chosen.isEmpty) }

    // MARK: - Reading

    func start() async {
        guard phase == .pick, scope == .all || !chosen.isEmpty else { return }
        run += 1
        let mine = run
        phase = .reading
        error = nil
        let selection: [MatterFileRef]? = scope == .some
            ? (files ?? []).filter { chosen.contains($0.id) }.map(\.ref) : nil
        do {
            let set = try await service.extractChronology(projectID: projectID, files: selection)
            guard mine == run else { return }
            proposals = Self.proposals(set.events, existing: existing)
            partial = set.partial
            message = set.message
            phase = .review
        } catch {
            guard mine == run else { return }
            self.error = DisplayText.message(for: error)
            phase = .failed
        }
    }

    /// Closing the sheet: a read still in flight must not open a review nobody is looking at.
    func abandon() { run += 1 }

    func back() { phase = .pick }

    /// Said when the read found nothing.
    var emptyMessage: String {
        let whose = scope == .some ? "those documents" : "this matter’s documents"
        return "No dated events were found in \(whose). Scanned files that are still being read appear once processing finishes."
    }

    // MARK: - Reviewing

    var picked: [Proposal] { proposals.filter { $0.on && $0.usable } }

    func toggle(_ id: Int) {
        guard let i = proposals.firstIndex(where: { $0.id == id }), proposals[i].usable else { return }
        proposals[i].on.toggle()
    }

    func tickAll() { for i in proposals.indices { proposals[i].on = proposals[i].usable } }
    func untickAll() { for i in proposals.indices { proposals[i].on = false } }

    /// "Add 3 to the chronology".
    var saveTitle: String { phase == .saving ? "Adding…" : "Add \(picked.count) to the chronology" }

    /// Saves the ticked proposals one at a time: a failure part-way leaves a clear count of what
    /// landed. Answers whether anything was added.
    @discardableResult
    func accept() async -> Bool {
        let list = picked
        guard !list.isEmpty, phase == .review else { return false }
        let mine = run
        phase = .saving
        progress = (0, list.count)
        var ok = 0
        var failed = 0
        var lastError = ""
        for p in list {
            do {
                _ = try await writes.saveUpdate(Self.body(p, projectID: projectID))
                ok += 1
                if let i = proposals.firstIndex(where: { $0.id == p.id }) { proposals[i].on = false }
            } catch {
                failed += 1
                lastError = DisplayText.message(for: error)
            }
            if mine == run { progress = (ok + failed, list.count) }
        }
        resultIsFailure = failed > 0
        result = Self.resultMessage(added: ok, failed: failed, lastError: lastError)
        phase = .review
        return ok > 0
    }

    nonisolated static func resultMessage(added ok: Int, failed: Int, lastError: String) -> String {
        if failed > 0 {
            let why = lastError.isEmpty ? "" : " — \(lastError)"
            return "\(ok) added; \(failed) could not be saved\(why)."
        }
        return "\(ok) \(ok == 1 ? "event" : "events") added to the chronology"
    }

    /// An AI entry: the kind, title, details as the body, the day, and where it was found.
    nonisolated static func body(_ p: Proposal, projectID: String) -> [String: JSONValue] {
        var b: [String: JSONValue] = [
            "projectId": .string(projectID), "kind": .string(p.kind), "title": .string(JSCompat.trim(p.title)),
            "body": .string(p.details), "eventDate": .string(p.day), "source": .string("ai"),
        ]
        if !p.sourceRef.isEmpty { b["sourceRef"] = .string(p.sourceRef) }
        return b
    }

    // MARK: - toProposals

    /// `norm`: lower case, every run of anything but a–z and 0–9 one space, trimmed.
    nonisolated static func norm(_ s: String) -> String {
        var out = ""
        var gap = false
        for ch in s.lowercased().unicodeScalars {
            let v = ch.value
            let keep = (v >= 0x61 && v <= 0x7A) || (v >= 0x30 && v <= 0x39)
            if keep {
                if gap && !out.isEmpty { out.append(" ") }
                gap = false
                out.unicodeScalars.append(ch)
            } else {
                gap = true
            }
        }
        return out
    }

    /// `sameEvent`: equal, or one inside the other when both run to twelve characters.
    nonisolated static func sameEvent(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        return min(a.count, b.count) >= 12 && (a.contains(b) || b.contains(a))
    }

    nonisolated static func proposals(_ events: [ExtractedEvent], existing: [MatterRecord.Entry]) -> [Proposal] {
        let known = existing.map { (day: $0.day, t: norm($0.title)) }
        return events.enumerated().map { i, ev in
            let day = MatterRecord.parseDocDate(ev.date)
            let title = JSCompat.trim(ev.title ?? "")
            let t = norm(title)
            let dup = !day.isEmpty && known.contains { $0.day == day && sameEvent($0.t, t) }
            let kind = ev.kind.flatMap(MatterVocabulary.ChronoKind.init(rawValue:))?.rawValue ?? "event"
            return Proposal(
                id: i, day: day, rawDate: JSCompat.trim(ev.date ?? ""), title: title,
                details: JSCompat.trim(ev.details ?? ""), kind: kind, sourceRef: JSCompat.trim(ev.sourceRef ?? ""),
                dup: dup, on: !day.isEmpty && !title.isEmpty && !dup)
        }
    }
}
