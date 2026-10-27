import Foundation
#if canImport(Darwin)
import Observation
#endif

/// "Attach from My Files" — the web's `AttachFromMyFiles.jsx`, the only way a document gets into a
/// matter: My Files as the Files screen sees it, only documents My Files has finished reading
/// tickable, at most 25 at a time, a destination folder, and every file's outcome in the server's
/// words. The server copies each document with what My Files already read from it; nothing is
/// uploaded from here and nothing is read twice.
///
/// See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class AttachFromMyFilesViewModel {

    /// One My Files document.
    struct Row: Equatable, Identifiable, Sendable {
        let file: FileNode.StoredFile
        /// Its folder relative to the user's root; "" at the root.
        let folder: String
        var id: String { file.path }
        var ref: MatterFileRef { MatterFileRef(folderName: folder, fileName: file.name) }
        var state: IngestState { file.state }

        /// Why it cannot be ticked, in the web's words; nil when it can.
        var whyNot: String? {
            switch state {
            case .ready, .scanned: return nil
            case .failed: return "My Files could not read this document, so it cannot be attached."
            case .inProgress: return "Still being read in My Files. It can be attached once it is ready."
            }
        }
    }

    /// A folder's documents, in the order the picker lists them.
    struct Folder: Equatable, Identifiable, Sendable {
        /// Relative to the user's root; "" for My Files' own root.
        let folder: String
        let rows: [Row]
        var id: String { folder.isEmpty ? "(root)" : folder }
        var title: String { folder.isEmpty ? "My Files" : folder.components(separatedBy: "/").joined(separator: " / ") }
    }

    static let tooMany = "Up to 25 documents at a time. Attach these, then pick the rest."
    static let intro = "Documents live in My Files first — they are read and indexed there, then attached here. Each one is copied into this matter, so My Files keeps its own."
    static let emptyMessage = "My Files is empty. Add the documents there first; they can be attached once they have been read."

    let projectID: String
    /// The matter folders a document can go into.
    let destinations: [String]
    var destination: String
    var query = ""
    private(set) var rows: [Row] = []
    private(set) var state: LoadState = .idle
    private(set) var selected: [MatterFileRef] = []
    /// A word about the selection: the 25-document cap.
    var notice: String?
    /// The whole request was refused.
    var error: String?
    /// A refusal with a code (storage full, plan), for the refusal card.
    private(set) var refusal: Refusal?
    /// Every file's outcome of the last attach.
    private(set) var outcomes: [AttachRow] = []
    private(set) var isAttaching = false

    private let myFiles: any FileProviding
    private let service: any MatterFilesProviding

    init(projectID: String, myFiles: any FileProviding, service: any MatterFilesProviding,
         destinations: [String] = MatterFilesService.standardFolders, destination: String? = nil) {
        self.projectID = projectID
        self.myFiles = myFiles
        self.service = service
        self.destinations = destinations.isEmpty ? MatterFilesService.standardFolders : destinations
        self.destination = destination ?? self.destinations[0]
    }

    // MARK: - Loading

    /// A fresh listing of My Files, every time the picker opens. A matter's own storage is never
    /// offered: a file already in a matter stays in that matter.
    func load() async {
        if rows.isEmpty { state = .loading }
        do {
            let tree = try await myFiles.tree()
            rows = Self.flatten(tree)
            state = .loaded
        } catch {
            state = .failed(LoadFailure(error))
        }
    }

    nonisolated static func flatten(_ tree: [FileNode]) -> [Row] {
        var out: [Row] = []
        func walk(_ nodes: [FileNode]) {
            for node in nodes {
                switch node {
                case .folder(let f):
                    if isMatterStorage(f.path) { continue }
                    walk(f.files ?? [])
                case .file(let f):
                    let row = Row(file: f, folder: f.folderPath)
                    if isMatterStorage(row.folder) { continue }
                    out.append(row)
                }
            }
        }
        walk(tree)
        return out
    }

    /// `_projects/…`: a matter's own storage.
    nonisolated static func isMatterStorage(_ path: String) -> Bool {
        path == "_projects" || path.hasPrefix("_projects/")
    }

    /// The documents by folder — My Files' root first, then the folders by name — or, while
    /// searching, the matches in one list.
    var groups: [Folder] {
        let q = JSCompat.trim(query).lowercased()
        let shown = q.isEmpty ? rows : rows.filter {
            $0.file.name.lowercased().contains(q) || $0.folder.lowercased().contains(q)
        }
        var byFolder: [String: [Row]] = [:]
        for row in shown { byFolder[row.folder, default: []].append(row) }
        let keys = byFolder.keys.sorted { a, b in
            if a.isEmpty != b.isEmpty { return a.isEmpty }
            return JSCompat.localeCompare(a, b) < 0
        }
        return keys.map { key in
            let list = (byFolder[key] ?? []).sorted { JSCompat.localeCompare($0.file.name, $1.file.name) < 0 }
            return Folder(folder: key, rows: list)
        }
    }

    /// How many documents My Files is still reading.
    var readingCount: Int { rows.filter { !$0.state.isTerminal }.count }

    var readingNote: String? {
        let n = readingCount
        guard n > 0 else { return nil }
        let subject = n == 1 ? "1 document is" : "\(n) documents are"
        return "\(subject) still being read in My Files. They can be attached once they are ready."
    }

    // MARK: - Choosing

    func selectable(_ row: Row) -> Bool { row.state.isUsable }

    func isSelected(_ row: Row) -> Bool { selected.contains(row.ref) }

    func toggle(_ row: Row) {
        guard selectable(row) else { return }
        if let index = selected.firstIndex(of: row.ref) {
            selected.remove(at: index)
            notice = nil
            return
        }
        guard selected.count < MatterFilesService.maxAttach else {
            notice = Self.tooMany
            return
        }
        selected.append(row.ref)
    }

    var canAttach: Bool { !selected.isEmpty && !isAttaching }

    /// "Attach 3 documents".
    var attachTitle: String {
        if isAttaching { return "Attaching…" }
        let n = selected.count
        if n == 0 { return "Attach documents" }
        return "Attach \(n) \(n == 1 ? "document" : "documents")"
    }

    // MARK: - Attaching

    /// Sends the selection. What was attached leaves the selection; what was skipped stays ticked
    /// with its reason. Answers the summary — "2 attached · 1 skipped: Still being read…" — or nil
    /// when the whole request was refused (`error`, `refusal`).
    func attach() async -> String? {
        guard canAttach else { return nil }
        isAttaching = true
        defer { isAttaching = false }
        error = nil
        refusal = nil
        notice = nil
        do {
            let result = try await service.attach(projectID: projectID, files: selected, subfolder: destination)
            outcomes = result.rows
            let done = result.rows.filter { !$0.isSkipped }
            let doneSources = Set(done.compactMap(\.source))
            selected.removeAll { doneSources.contains($0) }
            return Self.summary(result.rows)
        } catch {
            if let coded = (error as? APIError)?.refusal {
                refusal = coded
            }
            self.error = DisplayText.message(for: error)
            return nil
        }
    }

    /// "2 attached", "2 attached · 1 skipped: <the first reason>".
    nonisolated static func summary(_ rows: [AttachRow]) -> String {
        let done = rows.filter { !$0.isSkipped }.count
        let skipped = rows.filter(\.isSkipped)
        var text = "\(done) attached"
        if let first = skipped.first {
            text += " · \(skipped.count) skipped: \(first.reason ?? "Not attached")"
        }
        return text
    }

    /// The files the last attach left out, each with its reason.
    var skipped: [AttachRow] { outcomes.filter(\.isSkipped) }

    /// Every file went in, so the sheet can close.
    var finished: Bool { !outcomes.isEmpty && skipped.isEmpty }
}
