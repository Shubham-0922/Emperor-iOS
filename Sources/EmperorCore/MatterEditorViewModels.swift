import Foundation
#if canImport(Darwin)
import Observation
#endif

// The matter forms and actions — the web's NewMatterDialog, ProjectForm ("Edit matter details"),
// the section forms (chronology, task, fee/payment/expense, person), the Court section's link,
// unlink, refresh and "not filed yet", the card menu's archive and delete.
//
// Each editor holds its draft, checks it the way the server will (`validate()`, in the server's or
// the web form's words), and sends it once: `save()` is guarded against a second tap while the
// first is in flight, and is never retried — a failure is shown and the person decides. See
// `ChatViewModel` for why `@Observable` is Apple-only.

/// "A field is longer than the server takes", in the server's own sentence; nil when it fits.
private func tooLong(_ value: String, label: String, key: String) -> String? {
    guard let max = MatterRules.fieldLimit(key) else { return nil }
    do { _ = try MatterRules.optText(value, label: label, max: max); return nil } catch {
        return (error as? MatterRuleError)?.message
    }
}

// MARK: - New matter

#if canImport(Darwin)
@Observable
#endif
@MainActor
final class NewMatterViewModel {

    /// How the court case is settled: find it now, say it is not filed yet, or leave it for later.
    enum Court: String, CaseIterable, Sendable {
        case find
        case notFiled = "not_filed"
        case later

        var label: String {
            switch self {
            case .find: return "Find the case"
            case .notFiled: return "Not filed yet"
            case .later: return "Add later"
            }
        }
    }

    var name = "" { didSet { error = nil } }
    var banner: MatterVocabulary.BannerPreset
    /// A folder colour key, or nil for none.
    var color: String?
    var court: Court = .find { didSet { error = nil } }
    private(set) var pick: CourtSearchResult?
    var error: String?
    /// What the create is doing now, said under the button; nil when idle.
    private(set) var busy: String?

    private let writes: any ProjectWriting
    private let tracking: CaseTracking?

    init(writes: any ProjectWriting, tracking: CaseTracking?, existing: [Project] = []) {
        self.writes = writes
        self.tracking = tracking
        banner = MatterDrafts.leastUsedBanner(existing)
    }

    var isSaving: Bool { busy != nil }

    /// Still looking for the case: Find is chosen and nothing has been picked.
    var searching: Bool { court == .find && pick == nil }

    /// The name a found case gives the matter when the field is left blank — the cause title,
    /// tidied from the capitals courts print it in, as the server will write it.
    var titleFromCase: String {
        guard court == .find, let title = pick?.title, !JSCompat.trim(title).isEmpty else { return "" }
        return CourtNames.tidy(title, title: true)
    }

    /// The name on the preview banner.
    var shownName: String {
        let typed = JSCompat.trim(name)
        return !typed.isEmpty ? typed : !titleFromCase.isEmpty ? titleFromCase : "New matter"
    }

    var namePlaceholder: String {
        titleFromCase.isEmpty ? "Ankit Bhalla v. Vinod Kumari — partition suit" : titleFromCase
    }

    func choose(_ result: CourtSearchResult) {
        pick = result
        error = nil
    }

    func clearPick() { pick = nil }

    func validate() -> String? {
        let typed = JSCompat.trim(name)
        if searching {
            return "Search the court records and choose the case — or pick “Not filed yet” or “Add later”."
        }
        if typed.isEmpty && titleFromCase.isEmpty { return "Give the matter a name." }
        if let long = tooLong(typed, label: "Project name", key: "name") { return long }
        return nil
    }

    static func createdMessage(existed: Bool) -> String {
        existed ? "You already have a matter for this case — opening it." : "Matter created"
    }

    /// Creates the matter — through the found case when there is one — and answers its id, and
    /// whether it was an existing matter for that case. Nil when it did not happen; `error` says why.
    func create() async -> (projectID: String, existed: Bool)? {
        guard busy == nil else { return nil }
        if let problem = validate() {
            error = problem
            return nil
        }
        let typed = JSCompat.trim(name)
        error = nil
        defer { busy = nil }
        do {
            if court == .find, let pick {
                guard let tracking else {
                    error = CaseTracking.fallbackError
                    return nil
                }
                // `/save-case` reads the case's record from the court before it answers.
                busy = "Adding the case… fetching its record from the court"
                let caseID: String
                switch await tracking.track(pick, title: typed) {
                case .success(let id): caseID = id
                case .failure(let failure):
                    error = failure.message
                    return nil
                }
                busy = "Creating the matter…"
                do {
                    let made = try await writes.projectFromCase(
                        caseID: caseID, name: typed.isEmpty ? nil : typed, banner: banner.rawValue, color: color)
                    return (made.project.id, made.existed)
                } catch {
                    self.error = "The case is now tracked, but the matter could not be created: "
                        + "\(DisplayText.message(for: error)). Try again — the case will not be added twice."
                    return nil
                }
            }
            busy = "Creating the matter…"
            let project = try await writes.save(
                .newMatter(name: typed, banner: banner.rawValue, color: color, notFiled: court == .notFiled))
            return (project.id, false)
        } catch {
            self.error = DisplayText.message(for: error)
            return nil
        }
    }
}

// MARK: - Edit matter details

#if canImport(Darwin)
@Observable
#endif
@MainActor
final class MatterDetailsEditor {

    var draft: MatterDraft { didSet { error = nil } }
    /// The preset the banner falls back to when an image is removed or fails to upload.
    private(set) var preset: MatterVocabulary.BannerPreset
    /// A picked picture, not yet uploaded.
    private(set) var image: Data?
    private(set) var imageMime = "image/jpeg"
    var error: String?
    private(set) var busy: String?
    /// The field that takes focus when the form opens (`client`, `side`, `practiceArea`…).
    let focusField: String?
    /// What landed and what did not, once saved — "Saved, but …".
    private(set) var warnings: [String] = []

    private let writes: any ProjectWriting
    private let hadImage: Bool

    init(project: Project?, writes: any ProjectWriting, focusField: String? = nil,
         defaultBanner: MatterVocabulary.BannerPreset = .navy) {
        self.writes = writes
        self.focusField = focusField
        if let project {
            draft = MatterDraft(project)
            preset = MatterMeta.bannerPreset(banner: project.banner, color: project.color)
        } else {
            var d = MatterDraft()
            d.banner = defaultBanner.rawValue
            draft = d
            preset = defaultBanner
        }
        hadImage = project?.banner == "image"
    }

    var isEdit: Bool { draft.id != nil }
    var isSaving: Bool { busy != nil }
    var hasImage: Bool { draft.banner == "image" }

    func pickPreset(_ key: MatterVocabulary.BannerPreset) {
        preset = key
        image = nil
        draft.banner = key.rawValue
    }

    /// A picked picture: refused here when the server would refuse it.
    func pickImage(_ data: Data) {
        do {
            try ProjectWriteService.checkBanner(data)
        } catch {
            self.error = (error as? MatterRuleError)?.message ?? DisplayText.message(for: error)
            return
        }
        image = data
        imageMime = MatterRules.bannerImageType(data)?.mime ?? "image/jpeg"
        draft.banner = "image"
    }

    func removeImage() {
        image = nil
        draft.banner = preset.rawValue
    }

    /// The server's checks, in its words, before anything is sent.
    func validate() -> String? {
        let d = draft
        if JSCompat.trim(d.name).isEmpty { return "Give the matter a name." }
        let texts: [(String, String, String)] = [
            (d.name, "Project name", "name"), (d.client, "client", "client"),
            (d.description, "description", "description"), (d.forumName, "forumName", "forumName"),
            (d.caseNumber, "caseNumber", "caseNumber"), (d.caseYear, "caseYear", "caseYear"),
            (d.caseType, "caseType", "caseType"), (d.cnr, "cnr", "cnr"), (d.stage, "stage", "stage"),
            (d.oppositeParty, "oppositeParty", "oppositeParty"), (d.ourSideValue, "ourSide", "ourSide"),
        ]
        for (value, label, key) in texts {
            if let long = tooLong(value, label: label, key: key) { return long }
        }
        do {
            _ = try MatterRules.dayOf(d.nextHearingDate, label: "nextHearingDate")
            _ = try MatterRules.dayOf(d.filingDate, label: "filingDate")
        } catch {
            return (error as? MatterRuleError)?.message
        }
        return nil
    }

    /// The web's save order: on an existing matter the picture goes first (removing the old one,
    /// uploading the new), then every field; on a new matter the fields first, then the picture —
    /// and if that upload fails, the banner is pointed back at the preset.
    func save() async -> Project? {
        guard busy == nil else { return nil }
        if let problem = validate() {
            error = problem
            return nil
        }
        error = nil
        warnings = []
        defer { busy = nil }
        let banner = draft.banner == "image" ? (image != nil || hadImage ? "image" : preset.rawValue) : draft.banner

        if let id = draft.id {
            if hadImage && banner != "image" {
                busy = "Removing the image…"
                // Not fatal: a stray file is invisible once the row names a preset.
                try? await writes.removeBanner(projectID: id)
            }
            if let image {
                busy = "Uploading the banner…"
                do {
                    try await writes.uploadBanner(projectID: id, jpegOrPNG: image, mime: imageMime)
                } catch {
                    self.error = "The banner image was not uploaded: \(Self.reason(error))."
                    return nil
                }
            }
        }

        busy = isEdit ? "Saving…" : "Creating the matter…"
        let saved: Project
        do {
            saved = try await writes.save(draft.body(banner: banner))
        } catch {
            self.error = DisplayText.message(for: error)
            return nil
        }

        if !isEdit, let image {
            busy = "Uploading the banner…"
            do {
                try await writes.uploadBanner(projectID: saved.id, jpegOrPNG: image, mime: imageMime)
            } catch {
                warnings.append("the banner image was not uploaded (\(Self.reason(error)))")
                _ = try? await writes.patch(projectID: saved.id, fields: .banner(preset.rawValue))
            }
        }
        return saved
    }

    /// "Changes saved", or "Saved, but …" when part of it did not land.
    var savedMessage: String {
        warnings.isEmpty ? (isEdit ? "Changes saved" : "Matter created") : "Saved, but \(warnings.joined(separator: "; and "))."
    }

    private static func reason(_ error: Error) -> String {
        (error as? MatterRuleError)?.message ?? DisplayText.message(for: error)
    }
}

// MARK: - Chronology entry

#if canImport(Darwin)
@Observable
#endif
@MainActor
final class ChronologyEditor {
    var draft: ChronologyDraft { didSet { error = nil } }
    var error: String?
    private(set) var isSaving = false

    private let projectID: String
    private let writes: any ProjectWriting

    init(projectID: String, entry: MatterRecord.Entry? = nil, today: String, writes: any ProjectWriting) {
        self.projectID = projectID
        self.writes = writes
        draft = entry.map { ChronologyDraft($0, today: today) } ?? ChronologyDraft(today: today)
    }

    var isEdit: Bool { draft.id != nil }

    func validate() -> String? {
        if JSCompat.trim(draft.title).isEmpty && JSCompat.trim(draft.body).isEmpty {
            return "A chronology entry needs a title or a note"
        }
        if MatterRecord.dayKey(draft.day).isEmpty { return "Pick the date." }
        do {
            _ = try MatterRules.eventDateOf(draft.eventDate)
        } catch {
            return (error as? MatterRuleError)?.message
        }
        return tooLong(draft.title, label: "title", key: "update.title")
            ?? tooLong(draft.body, label: "body", key: "update.body")
    }

    /// Saves the entry; the answer carries the matter's next hearing as it now stands.
    func save() async -> SavedUpdate? {
        guard !isSaving else { return nil }
        if let problem = validate() {
            error = problem
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        do {
            return try await writes.saveUpdate(draft.body(projectID: projectID))
        } catch {
            self.error = DisplayText.message(for: error)
            return nil
        }
    }
}

// MARK: - Task

#if canImport(Darwin)
@Observable
#endif
@MainActor
final class TaskEditor {
    var draft: TaskDraft { didSet { error = nil } }
    var error: String?
    private(set) var isSaving = false

    private let projectID: String
    private let writes: any ProjectWriting

    init(projectID: String, task: ProjectTask? = nil, kind: String = "task", writes: any ProjectWriting) {
        self.projectID = projectID
        self.writes = writes
        draft = task.map(TaskDraft.init) ?? TaskDraft(kind: kind)
    }

    var isEdit: Bool { draft.id != nil }

    func validate() -> String? {
        if JSCompat.trim(draft.title).isEmpty { return "Give the task a title." }
        if !draft.dueDate.isEmpty, (try? MatterRules.dayOf(draft.dueDate, label: "dueDate")) == nil {
            return "That due date is not a real date."
        }
        if draft.kind == "limitation" && draft.dueDate.isEmpty { return "A limitation entry needs its last date." }
        return tooLong(draft.title, label: "Task title", key: "task.title")
            ?? tooLong(draft.notes, label: "notes", key: "task.notes")
    }

    func save() async -> ProjectTask? {
        guard !isSaving else { return nil }
        if let problem = validate() {
            error = problem
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        do {
            return try await writes.saveTask(draft.body(projectID: projectID))
        } catch {
            self.error = DisplayText.message(for: error)
            return nil
        }
    }
}

// MARK: - Fee, payment, expense

#if canImport(Darwin)
@Observable
#endif
@MainActor
final class LedgerEditor {
    var draft: LedgerDraft { didSet { error = nil } }
    var error: String?
    private(set) var isSaving = false

    private let projectID: String
    private let writes: any ProjectWriting

    init(projectID: String, entry: LedgerEntry? = nil, kind: String = "fee", today: String, writes: any ProjectWriting) {
        self.projectID = projectID
        self.writes = writes
        draft = entry.map { LedgerDraft($0, today: today) } ?? LedgerDraft(kind: kind, today: today)
    }

    var isEdit: Bool { draft.id != nil }

    /// The amount box, read as the web reads it (`parseRupees`).
    var parsed: Result<INR.Parsed, INR.ParseError> { INR.parse(draft.amountText) }

    /// The amount in words, as the receipt will print it — the cheapest check against a slipped
    /// zero; "" while the box does not hold an amount.
    var words: String {
        guard case .success(let p) = parsed, Double(p.paise) <= INR.serverMaxRupees * 100 else { return "" }
        return INR.words(paise: p.paise)
    }

    /// The line under the amount: its words, or why it is not an amount yet.
    var amountHint: String {
        if !words.isEmpty { return words }
        if draft.amountText.isEmpty { return "Rupees, with up to two decimals for paise." }
        return amountError ?? ""
    }

    /// The amount's problem, or nil. The server's ceiling (₹1e11) is lower than the field's.
    var amountError: String? {
        switch parsed {
        case .failure(let failure): return failure.message
        case .success(let p): return Double(p.paise) > INR.serverMaxRupees * 100 ? "That amount is too large." : nil
        }
    }

    /// "Edit payment", or "New entry".
    var title: String {
        guard isEdit else { return "New entry" }
        return MatterVocabulary.LedgerKind(rawValue: draft.kind).map { "Edit \($0.rawValue)" } ?? "Edit entry"
    }

    func validate() -> String? {
        if let amountError { return amountError }
        if (try? MatterRules.dayOf(draft.entryDate, label: "entryDate")) == nil || draft.entryDate.isEmpty {
            return "Pick the date."
        }
        return tooLong(draft.title, label: "title", key: "ledger.title")
            ?? tooLong(draft.reference, label: "reference", key: "ledger.reference")
            ?? tooLong(draft.notes, label: "notes", key: "ledger.notes")
    }

    func save() async -> LedgerEntry? {
        guard !isSaving else { return nil }
        if let problem = validate() {
            error = problem
            return nil
        }
        guard case .success(let amount) = parsed else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            return try await writes.saveLedger(draft.body(projectID: projectID, rupees: amount.rupees))
        } catch {
            self.error = DisplayText.message(for: error)
            return nil
        }
    }
}

// MARK: - Person

#if canImport(Darwin)
@Observable
#endif
@MainActor
final class PersonEditor {
    var draft: PersonDraft { didSet { error = nil } }
    var error: String?
    private(set) var isSaving = false

    private let projectID: String
    private let writes: any ProjectWriting

    init(projectID: String, person: ProjectPerson? = nil, role: String = "client", name: String = "",
         writes: any ProjectWriting) {
        self.projectID = projectID
        self.writes = writes
        draft = person.map(PersonDraft.init) ?? PersonDraft(role: role, name: name)
    }

    var isEdit: Bool { draft.id != nil }

    func validate() -> String? {
        if JSCompat.trim(draft.name).isEmpty { return "Enter a name." }
        let email = JSCompat.trim(draft.email)
        if !email.isEmpty && !MatterRules.validEmail(email) { return "That email address does not look complete." }
        let phone = JSCompat.trim(draft.phone)
        if !phone.isEmpty {
            let digits = phone.unicodeScalars.filter { (48...57).contains($0.value) }.count
            // Not a judgement of the number — a landline or an extension is fine — only a guard
            // against a box holding no number at all; then the server's own shape rule.
            if digits < 6 { return "That phone number looks too short." }
            if !MatterRules.validPhone(phone) { return "phone may contain only digits, spaces and + ( ) - ." }
        }
        return tooLong(draft.name, label: "name", key: "person.name")
            ?? tooLong(draft.address, label: "address", key: "person.address")
            ?? tooLong(draft.notes, label: "notes", key: "person.notes")
    }

    func save() async -> ProjectPerson? {
        guard !isSaving else { return nil }
        if let problem = validate() {
            error = problem
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        do {
            return try await writes.savePerson(draft.body(projectID: projectID))
        } catch {
            self.error = DisplayText.message(for: error)
            return nil
        }
    }
}

// MARK: - The court case

#if canImport(Darwin)
@Observable
#endif
@MainActor
final class MatterCourtActions {
    private(set) var isRefreshing = false
    private(set) var isWorking = false
    /// When the court may be asked again, after a "too soon".
    private(set) var retryAt: Date?
    var message: String?
    var error: String?

    private let projectID: String
    private let writes: any ProjectWriting
    private let tracking: CaseTracking?
    private let now: @Sendable () -> Date

    init(projectID: String, writes: any ProjectWriting, tracking: CaseTracking?,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.projectID = projectID
        self.writes = writes
        self.tracking = tracking
        self.now = now
    }

    /// Seconds before a refresh may be asked for again; 0 means now.
    func waitSeconds(at date: Date? = nil) -> Int {
        guard let retryAt else { return 0 }
        return max(0, Int(retryAt.timeIntervalSince(date ?? now()).rounded(.up)))
    }

    func refreshLabel(at date: Date? = nil) -> String {
        if isRefreshing { return "Asking the court…" }
        let wait = waitSeconds(at: date)
        return wait > 0 ? "Refresh in \(RefreshOutcome.clock(wait))" : "Refresh from court"
    }

    /// The line under the button while the court may not be asked.
    func waitNotice(at date: Date? = nil) -> String? {
        let wait = waitSeconds(at: date)
        guard wait > 0 else { return nil }
        return "The court is asked at most once every five minutes — you can refresh again in \(RefreshOutcome.clock(wait))."
    }

    /// Asks the court to re-read the linked case. True when the record changed and the matter
    /// should be fetched again.
    func refresh() async -> Bool {
        guard !isRefreshing, waitSeconds() == 0 else { return false }
        isRefreshing = true
        error = nil
        defer { isRefreshing = false }
        do {
            switch try await writes.refreshCase(projectID: projectID) {
            case .done(_, let counts):
                message = counts.text
                return true
            case .tooSoon(let seconds, _):
                retryAt = now().addingTimeInterval(TimeInterval(seconds))
                return false
            case .courtFailed(let text):
                error = text
                return false
            }
        } catch {
            self.error = DisplayText.message(for: error)
            return false
        }
    }

    /// Tracks the picked case and links it; a found case ends "not filed yet".
    func link(_ pick: CourtSearchResult, matter: Project) async -> Bool {
        guard !isWorking else { return false }
        guard let tracking else {
            error = CaseTracking.fallbackError
            return false
        }
        isWorking = true
        error = nil
        defer { isWorking = false }
        let caseID: String
        switch await tracking.track(pick, title: matter.name) {
        case .success(let id): caseID = id
        case .failure(let failure):
            error = failure.message
            return false
        }
        do {
            _ = try await writes.linkCase(projectID: projectID, caseID: caseID)
        } catch {
            self.error = DisplayText.message(for: error)
            return false
        }
        if matter.courtStatus == "not_filed" {
            // Not fatal: a linked case already counts as the court step done.
            _ = try? await writes.patch(projectID: projectID, fields: .courtStatus(nil))
        }
        message = "Court case linked — its record now comes from the court"
        return true
    }

    func unlink() async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            _ = try await writes.linkCase(projectID: projectID, caseID: nil)
            message = "Court case unlinked"
            return true
        } catch {
            self.error = DisplayText.message(for: error)
            return false
        }
    }

    /// "Not filed yet", and taking it back.
    func setNotFiled(_ on: Bool) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            _ = try await writes.patch(projectID: projectID, fields: .courtStatus(on ? "not_filed" : nil))
            return true
        } catch {
            self.error = DisplayText.message(for: error)
            return false
        }
    }
}

// MARK: - Delete

#if canImport(Darwin)
@Observable
#endif
@MainActor
final class MatterDeletion {
    var typed = "" { didSet { error = nil } }
    var error: String?
    private(set) var isDeleting = false

    let project: Project
    private let writes: any ProjectWriting

    init(project: Project, writes: any ProjectWriting) {
        self.project = project
        self.writes = writes
    }

    /// The stored name, as the server compares it.
    var storedName: String { project.name ?? "" }

    /// Surrounding spaces forgiven, nothing else; the server is sent the stored name.
    func matches(_ typed: String) -> Bool {
        let t = JSCompat.trim(typed)
        return !t.isEmpty && t == JSCompat.trim(storedName)
    }

    var canDelete: Bool { matches(typed) && !isDeleting }

    /// What goes with it, as the web lists it.
    var consequences: [String] {
        let files = project.fileCount ?? 0
        let chats = project.chatCount ?? 0
        return [
            "its files\(files > 0 ? " (\(files))" : "") — they are not kept in My Files or anywhere else;",
            "its Ask Emperor chats\(chats > 0 ? " (\(chats))" : "") and the drafts made in them;",
            "its chronology, tasks, fees and people.",
        ]
    }

    static let footnote = "A court case linked to it stays tracked, and is listed under Matters again as a tracked case. This cannot be undone."

    var deletedMessage: String { "Deleted “\(storedName)”." }

    func delete() async -> Bool {
        guard canDelete else { return false }
        isDeleting = true
        defer { isDeleting = false }
        do {
            _ = try await writes.delete(projectID: project.id, confirmName: storedName)
            return true
        } catch {
            self.error = DisplayText.message(for: error)
            return false
        }
    }
}

// MARK: - One-tap changes

/// The writes that need no form: archive and unarchive, the setup strip's side and practice
/// chips, a task's tick, and removing a chronology entry, task, ledger entry or person. Each says
/// what went wrong in `error`; the caller reloads the matter on success.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class MatterQuickActions {
    /// The row being changed, so only its control shows the wait.
    private(set) var busyID: String?
    var error: String?

    let projectID: String
    private let writes: any ProjectWriting

    init(projectID: String, writes: any ProjectWriting) {
        self.projectID = projectID
        self.writes = writes
    }

    /// Archive; unarchive makes it active again.
    func setArchived(_ archived: Bool) async -> Bool {
        await run(projectID, "Could not change the matter's status.") {
            _ = try await self.writes.patch(projectID: self.projectID, fields: .status(archived ? .archived : .active))
        }
    }

    func setSide(_ side: String?) async -> Bool {
        await run(projectID, "Could not save that to the matter.") {
            _ = try await self.writes.patch(projectID: self.projectID, fields: .ourSide(side))
        }
    }

    func setPracticeArea(_ area: String?) async -> Bool {
        await run(projectID, "Could not save that to the matter.") {
            _ = try await self.writes.patch(projectID: self.projectID, fields: .practiceArea(area))
        }
    }

    /// Ticks or unticks a task — the whole task goes back, as the web sends it.
    func toggle(_ task: ProjectTask) async -> Bool {
        let body = TaskDraft(task).toggled.body(projectID: projectID)
        return await run(task.id, "Could not update the task.") {
            _ = try await self.writes.saveTask(body)
        }
    }

    func deleteTask(_ id: String) async -> Bool {
        await run(id, "Could not delete the task.") { try await self.writes.deleteTask(id: id) }
    }

    func deleteUpdate(_ id: String) async -> Bool {
        await run(id, "Could not delete this entry.") { try await self.writes.deleteUpdate(id: id) }
    }

    func deleteLedger(_ id: String) async -> Bool {
        await run(id, "Could not delete the entry.") { try await self.writes.deleteLedger(id: id) }
    }

    func deletePerson(_ id: String) async -> Bool {
        await run(id, "Could not remove this person.") { try await self.writes.deletePerson(id: id) }
    }

    private func run(_ id: String, _ fallback: String, _ work: @MainActor () async throws -> Void) async -> Bool {
        guard busyID == nil else { return false }
        busyID = id
        error = nil
        defer { busyID = nil }
        do {
            try await work()
            return true
        } catch {
            let text = DisplayText.message(for: error)
            self.error = text.isEmpty ? fallback : text
            return false
        }
    }
}
