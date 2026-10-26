import Foundation
#if canImport(Darwin)
import Observation
#endif

/// Filing Assembly: a saved draft, its annexures and a cover page made into one paginated
/// bundle by the server (`src/pages/FilingAssembly.jsx`, the standalone page).
///
/// The server owns the marks, the order's effect, the index and the checklist's verdicts; this
/// holds the page's state and its sentences. Every annexure change is shown at once and then
/// read back, because the server may answer with something other than what was asked.
///
/// See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class FilingAssemblyViewModel {

    static let subtitle =
        "Turn a draft and its annexures into a court-ready, paginated bundle with cover, index and list of annexures."
    static let noDrafts =
        "No saved drafts yet. Create a draft with the drafting tools first, then come back to assemble it for filing."
    static let noAnnexures =
        "No annexures yet. Documents cited during drafting appear here automatically; you can also add PDFs from your files."
    static let annexuresHint = "Marks are sticky — reordering never renumbers P-1, P-2, …"
    static let coverHint = "Used for the court-style caption page at the front of the bundle"
    static let noPDFs =
        "No PDF files found in your library. Upload PDFs via My Files first — only PDFs can be attached as annexures."
    static let addFootnote =
        "Scanned documents that have been OCR’d default to a typed true copy (B2) and will need human verification before filing."
    static let failureTitle = "Assembly failed — nothing was generated"
    static let failureHint = "The assembler fails closed: fix every item below, then assemble again."
    static let forumMissing = "Select the forum for the cover page"
    static let forumUnsupported =
        "Assembly supports NCLT, NCLAT, High Court and Supreme Court covers"
    static let unreachable = "Could not reach the filing service"

    // MARK: - State

    private(set) var draftsState: LoadState = .idle
    private(set) var drafts: [FilingDraft] = []
    var draftQuery = ""
    private(set) var draft: FilingDraft?

    private(set) var annexState: LoadState = .idle
    private(set) var annexures: [FilingAnnexure] = []
    private(set) var isMutating = false
    private(set) var isAdding = false

    private(set) var filesState: LoadState = .idle
    private(set) var pdfFiles: [FileNode.StoredFile] = []
    var fileQuery = ""

    var cover = FilingCover()
    private(set) var isAssembling = false
    /// The last run's answer — a bundle, or the list of what stopped it.
    var outcome: FilingAssemblyResult?
    private(set) var bundles: [FilingBundle] = []
    private(set) var checklist: FilingChecklist?

    /// A short confirmation — "P-1 marked verified against the original".
    var toast: String?
    /// What went wrong with the last change, worded by the server where it said.
    var notice: String?
    /// The account's plan does not include filing assembly.
    private(set) var refusal: Refusal?

    private let service: any FilingProviding
    private let files: any FileProviding
    private let now: @Sendable () -> Date

    init(
        service: any FilingProviding, files: any FileProviding,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.service = service
        self.files = files
        self.now = now
    }

    // MARK: - Derived

    var filteredDrafts: [FilingDraft] {
        let q = draftQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return drafts }
        return drafts.filter { ($0.title ?? "").lowercased().contains(q) }
    }

    var filteredFiles: [FileNode.StoredFile] { FileService.search(fileQuery, in: pdfFiles) }

    /// The banner shown when the binding order no longer follows the marks, or `nil`.
    var orderWarning: String? {
        let marks = annexures.map(\.mark)
        guard !marks.isEmpty, !FilingMarks.isInMarkOrder(marks) else { return nil }
        return "Annexure order no longer matches the mark sequence (\(FilingMarks.sorted(marks).joined(separator: ", "))). Marks stay as assigned — the Index and List of Annexures will follow this binding order."
    }

    var pendingTypedCount: Int { annexures.filter(\.isPendingVerification).count }

    /// "2 typed copies not yet verified — assembly will proceed, but the checklist will flag
    /// them", or `nil` when there are none.
    var pendingTypedText: String? {
        let n = pendingTypedCount
        guard n > 0 else { return nil }
        return "\(n) typed \(n == 1 ? "copy" : "copies") not yet verified — assembly will proceed, but the checklist will flag \(n == 1 ? "it" : "them")"
    }

    private var forum: String { cover.forum.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Whether the assembler can make a cover for this forum. Any other renders the whole bundle
    /// and then fails, so it is stopped here.
    var forumSupported: Bool { FilingForum.normalize(forum) != nil }

    var canAssemble: Bool {
        draft != nil && !forum.isEmpty && forumSupported && !isMutating && !isAssembling
    }

    /// Why Assemble is not available, when the forum is the reason.
    var assembleHint: String? {
        guard draft != nil else { return nil }
        if forum.isEmpty { return Self.forumMissing }
        if !forumSupported { return Self.forumUnsupported }
        return nil
    }

    /// The question asked before an annexure is removed.
    nonisolated static func removePrompt(for annexure: FilingAnnexure) -> String {
        "Remove annexure \(annexure.mark) — “\(annexure.title)”? Its mark will not be reused."
    }

    // MARK: - Drafts

    func loadDrafts() async {
        if drafts.isEmpty { draftsState = .loading }
        do {
            drafts = try await service.drafts()
            draftsState = .loaded
        } catch {
            note(error)
            if drafts.isEmpty { draftsState = .failed(LoadFailure(error)) } else { draftsState = .loaded }
        }
    }

    func pick(_ picked: FilingDraft) async {
        draft = picked
        annexures = []
        annexState = .idle
        outcome = nil
        checklist = nil
        bundles = []
        await reloadAnnexures()
        await refreshBundles()
        await refreshChecklist()
    }

    /// Back to the list: the annexures and the last result go with the draft.
    func changeDraft() {
        draft = nil
        annexures = []
        annexState = .idle
        outcome = nil
        checklist = nil
        bundles = []
    }

    // MARK: - Annexures

    func reloadAnnexures() async {
        guard let current = draft else { return }
        if annexures.isEmpty { annexState = .loading }
        do {
            let rows = try await service.annexures(draftID: current.id, chatID: current.chatID)
            guard draft?.id == current.id else { return }
            annexures = rows
            annexState = .loaded
        } catch {
            guard draft?.id == current.id else { return }
            note(error)
            if annexures.isEmpty { annexState = .failed(LoadFailure(error)) } else { annexState = .loaded }
        }
    }

    func loadFiles() async {
        if pdfFiles.isEmpty { filesState = .loading }
        do {
            pdfFiles = FileService.allFiles(in: try await files.tree())
                .filter { $0.name.lowercased().hasSuffix(".pdf") }
            filesState = .loaded
        } catch {
            if pdfFiles.isEmpty { filesState = .failed(LoadFailure(error)) } else { filesState = .loaded }
        }
    }

    /// Registers a PDF from My Files as the next annexure. Answers whether it was added, so the
    /// picker can close.
    @discardableResult
    func add(_ file: FileNode.StoredFile) async -> Bool {
        guard let current = draft, !isAdding else { return false }
        isAdding = true
        notice = nil
        defer { isAdding = false }
        do {
            _ = try await service.addAnnexure(
                draftID: current.id, folderName: file.folderPath, fileName: file.name)
            toast = "Added \(file.name) as an annexure"
            await reloadAnnexures()
            return true
        } catch {
            notice = text(for: error, fallback: "Could not add annexure")
            return false
        }
    }

    func rename(_ annexure: FilingAnnexure, to newTitle: String) async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != annexure.title else { return }
        await mutate("Rename failed", optimistic: { list in
            list = list.map { var a = $0; if a.id == annexure.id { a.title = title }; return a }
        }) { service in
            _ = try await service.update(id: annexure.id, title: title, treatment: nil, verifyStatus: nil)
        }
    }

    /// Original pages or a typed copy. A typed copy keeps a verification already given;
    /// otherwise it waits for one.
    func setTreatment(_ annexure: FilingAnnexure, _ treatment: FilingTreatment) async {
        guard treatment.rawValue != annexure.treatment else { return }
        let verify: FilingVerify = treatment == .typed
            ? (annexure.isVerified ? .verified : .pending) : .notApplicable
        await mutate("Could not change treatment", optimistic: { list in
            list = list.map {
                var a = $0
                if a.id == annexure.id {
                    a.treatment = treatment.rawValue
                    a.verifyStatus = verify.rawValue
                }
                return a
            }
        }) { service in
            _ = try await service.update(
                id: annexure.id, title: nil, treatment: treatment, verifyStatus: verify)
        }
    }

    /// The human gate on a typed copy: checked against the original, or reopened.
    func toggleVerify(_ annexure: FilingAnnexure) async {
        let verify: FilingVerify = annexure.isVerified ? .pending : .verified
        let ok = await mutate("Could not update verification", optimistic: { list in
            list = list.map {
                var a = $0
                if a.id == annexure.id { a.verifyStatus = verify.rawValue }
                return a
            }
        }) { service in
            _ = try await service.update(
                id: annexure.id, title: nil, treatment: nil, verifyStatus: verify)
        }
        if ok, verify == .verified {
            toast = "\(annexure.mark) marked verified against the original"
        }
    }

    func moveUp(_ annexure: FilingAnnexure) async {
        guard let i = annexures.firstIndex(where: { $0.id == annexure.id }), i > 0 else { return }
        var next = annexures
        next.swapAt(i, i - 1)
        await reorder(next)
    }

    func moveDown(_ annexure: FilingAnnexure) async {
        guard let i = annexures.firstIndex(where: { $0.id == annexure.id }),
              i < annexures.count - 1 else { return }
        var next = annexures
        next.swapAt(i, i + 1)
        await reorder(next)
    }

    /// A drag in the list: the rows at `offsets` moved to before `destination`.
    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) async {
        let moving = offsets.filter { $0 < annexures.count }.map { annexures[$0] }
        guard !moving.isEmpty else { return }
        var next = annexures.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let before = offsets.filter { $0 < destination }.count
        let at = max(0, min(next.count, destination - before))
        next.insert(contentsOf: moving, at: at)
        await reorder(next)
    }

    func delete(_ annexure: FilingAnnexure) async {
        await mutate("Delete failed", optimistic: { list in
            list.removeAll { $0.id == annexure.id }
        }) { service in
            try await service.delete(id: annexure.id)
        }
    }

    private func reorder(_ next: [FilingAnnexure]) async {
        guard let current = draft, next.map(\.id) != annexures.map(\.id) else { return }
        let ids = next.map(\.id)
        await mutate("Reorder failed", optimistic: { list in list = next }) { service in
            _ = try await service.reorder(draftID: current.id, orderedIDs: ids)
        }
    }

    /// One change: shown at once, sent, then the list read back whatever the answer.
    @discardableResult
    private func mutate(
        _ fallback: String,
        optimistic: (inout [FilingAnnexure]) -> Void,
        _ call: (any FilingProviding) async throws -> Void
    ) async -> Bool {
        guard draft != nil, !isMutating else { return false }
        isMutating = true
        notice = nil
        optimistic(&annexures)
        var ok = false
        do {
            try await call(service)
            ok = true
        } catch {
            notice = text(for: error, fallback: fallback)
        }
        isMutating = false
        await reloadAnnexures()
        return ok
    }

    // MARK: - Assembly

    /// Assembles the bundle, once. If the answer is lost on the way back — a dropped connection
    /// on a run that takes minutes — the bundles are read, and one made since the tap is taken
    /// as this run's.
    func assemble() async {
        guard canAssemble, let current = draft else { return }
        let started = now()
        isAssembling = true
        outcome = nil
        notice = nil
        defer { isAssembling = false }
        do {
            let result = try await service.assemble(draftID: current.id, cover: cover)
            guard draft?.id == current.id else { return }
            outcome = result
            if result.success {
                toast = result.successTitle
                await reloadAnnexures()
            }
            await refreshBundles()
        } catch {
            guard draft?.id == current.id else { return }
            if let refused = (error as? APIError)?.refusal {
                refusal = refused
                return
            }
            if case APIError.transport = error, let bundle = await bundleMade(since: started, for: current) {
                let result = FilingAssemblyResult(
                    success: true, bundleId: bundle.id, pageCount: bundle.pageCount)
                outcome = result
                toast = result.successTitle
                await reloadAnnexures()
                return
            }
            outcome = FilingAssemblyResult(
                success: false, errors: [.string(text(for: error, fallback: Self.unreachable))])
        }
    }

    private func bundleMade(since start: Date, for current: FilingDraft) async -> FilingBundle? {
        guard let list = try? await service.bundles(draftID: current.id) else { return nil }
        bundles = list
        return list
            .filter { $0.isReady && ($0.createdDate.map { $0 >= start } ?? false) }
            .max { ($0.createdAt ?? 0) < ($1.createdAt ?? 0) }
    }

    func dismissOutcome() { outcome = nil }

    func refreshBundles() async {
        guard let current = draft else { return }
        do {
            let list = try await service.bundles(draftID: current.id)
            guard draft?.id == current.id else { return }
            bundles = list
        } catch {
            note(error)
        }
    }

    /// What the forum asks for before filing, from the server, once the forum is one it reads.
    func refreshChecklist() async {
        guard let current = draft, forumSupported else {
            checklist = nil
            return
        }
        let asked = forum
        do {
            let list = try await service.checklist(draftID: current.id, forum: asked)
            guard draft?.id == current.id, forum == asked else { return }
            checklist = list
        } catch {
            note(error)
        }
    }

    func pdf(for bundle: FilingBundle) async throws -> Data {
        try await service.bundlePDF(id: bundle.id)
    }

    /// The name a bundle is shared under.
    func shareName(for bundle: FilingBundle) -> String {
        "\(draft?.displayTitle ?? "Filing") — bundle \(bundle.id).pdf"
    }

    // MARK: - Errors

    /// Remembers a plan refusal, which replaces the page.
    private func note(_ error: Error) {
        if let refused = (error as? APIError)?.refusal { refusal = refused }
    }

    private func text(for error: Error, fallback: String) -> String {
        note(error)
        let message = DisplayText.message(for: error)
        return message.isEmpty ? fallback : message
    }
}
