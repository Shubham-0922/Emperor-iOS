import Foundation
#if canImport(Darwin)
import Observation
#endif

/// One file of a matter's storage, as the matter screens read it — the web's `flattenStorage`
/// row (`src/lib/storageTree.js`).
struct MatterFile: Equatable, Identifiable, Sendable {
    let name: String
    /// Relative to the user's storage root: `_projects/<id>/Pleadings/Plaint.pdf`.
    let path: String
    /// The server's address for its folder, relative to the user's root — what a chat attachment,
    /// the viewer, a rename or a delete is given.
    let folderName: String
    /// The same folder relative to the matter's root — what a person reads: "Pleadings",
    /// "Evidence/Photos", "" for the matter's own root.
    let sub: String
    let status: String?
    let modified: String?

    var id: String { path }
    var state: IngestState { IngestState.classify(status) }
    /// Ready or an image-only scan: the model can read it.
    var isReady: Bool { state.isUsable }
    var isReading: Bool { !state.isTerminal }
    var isFailed: Bool { if case .failed = state { return true } else { return false } }

    var attachment: ChatAttachment {
        ChatAttachment(name: name, folderName: folderName.isEmpty ? nil : folderName)
    }

    var ref: MatterFileRef { MatterFileRef(folderName: folderName, fileName: name) }

    /// The words under the name while it is not ready.
    var statusText: String? {
        switch state {
        case .ready, .scanned: return nil
        case .failed: return "Could not be read"
        case .inProgress: return "Being read"
        }
    }

    /// Every file in a listing, folders walked; `root` is the matter's (`_projects/<id>`).
    static func flatten(_ nodes: [FileNode], root: String) -> (files: [MatterFile], folders: [String]) {
        var files: [MatterFile] = []
        var folders: [String] = []
        let prefix = root + "/"
        func sub(_ folder: String) -> String {
            if folder == root { return "" }
            return folder.hasPrefix(prefix) ? String(folder.dropFirst(prefix.count)) : folder
        }
        func walk(_ list: [FileNode]) {
            for node in list {
                switch node {
                case .folder(let f):
                    let path = normalise(f.path.isEmpty ? f.name : f.path)
                    let s = sub(path)
                    if !s.isEmpty { folders.append(s) }
                    walk(f.files ?? [])
                case .file(let f):
                    let path = normalise(f.path.isEmpty ? f.name : f.path)
                    let cut = path.lastIndex(of: "/")
                    let folder = cut.map { String(path[..<$0]) } ?? root
                    files.append(MatterFile(
                        name: f.name, path: path, folderName: folder, sub: sub(folder),
                        status: f.status, modified: f.modified))
                }
            }
        }
        walk(nodes)
        return (files, folders)
    }

    private static func normalise(_ path: String) -> String {
        var p = path.replacingOccurrences(of: "\\", with: "/")
        while p.hasPrefix("/") { p.removeFirst() }
        return p
    }
}

/// A folder down the side of Files: the five standard folders, then the user's own, then the
/// matter's root as "Unfiled" when something sits there.
struct MatterFolder: Equatable, Identifiable, Sendable {
    /// Relative to the matter; "" is the root.
    let sub: String
    let name: String
    /// A standard folder or the root: neither can be renamed or deleted here.
    let isStandard: Bool
    let count: Int
    var id: String { sub.isEmpty ? "(root)" : sub }
}

/// A matter's Files section — the web's `FilesSection` and `useProjectFiles`: the folders, the
/// open folder's documents with their reading state, New folder, rename and delete through the
/// ordinary file routes, and the reading followed until it ends. Nothing is uploaded into a
/// matter: documents come from My Files (`AttachFromMyFilesViewModel`).
///
/// See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class MatterFilesViewModel {

    let projectID: String
    private(set) var listing: MatterFiles?
    private(set) var state: LoadState = .idle
    /// A refresh that failed while a listing is on screen: the listing stays, this says why.
    private(set) var refreshError: String?
    /// The open folder, relative to the matter.
    var current = MatterFilesService.standardFolders[0]
    /// What the last write did, for the toast.
    var message: String?
    /// Why the last write did not happen, for the alert.
    var error: String?
    private(set) var isBusy = false

    private let service: any MatterFilesProviding
    private let files: (any FileManaging)?
    private var ticket = 0

    init(projectID: String, service: any MatterFilesProviding, files: (any FileManaging)? = nil) {
        self.projectID = projectID
        self.service = service
        self.files = files
    }

    var root: String { listing?.root ?? MatterFilesService.root(projectID) }

    private var flat: (files: [MatterFile], folders: [String]) {
        guard let listing else { return ([], []) }
        return MatterFile.flatten(listing.folders + listing.files, root: listing.root)
    }

    var allFiles: [MatterFile] { flat.files }

    // MARK: - Loading

    /// Fetches the listing. Only the newest request may write: a poll and a refresh after a write
    /// can overlap, and an older answer must not replace a newer one.
    func load() async {
        ticket += 1
        let mine = ticket
        if listing == nil { state = .loading }
        do {
            let fresh = try await service.listing(projectID: projectID)
            guard mine == ticket else { return }
            listing = fresh
            refreshError = nil
            state = .loaded
        } catch {
            guard mine == ticket else { return }
            if listing == nil {
                state = .failed(LoadFailure(error))
            } else {
                refreshError = DisplayText.message(for: error)
            }
        }
    }

    /// Some document is still being read.
    var isProcessing: Bool { allFiles.contains { $0.isReading } }

    /// The wait before the next look at a reading: 1.5 s, then longer, at most 10 s.
    nonisolated static func pollDelay(attempt: Int) -> TimeInterval {
        let steps: [TimeInterval] = [1.5, 3, 6]
        return attempt < steps.count ? steps[attempt] : 10
    }

    /// How long a reading is followed before the section stops asking.
    nonisolated static let pollLimit: TimeInterval = 600

    /// Follows the reading until nothing is in progress, the limit passes or the task is
    /// cancelled (the section left the screen).
    func followReading(
        sleep: @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) async {
        var waited: TimeInterval = 0
        var attempt = 0
        while isProcessing, waited < Self.pollLimit, !Task.isCancelled {
            let delay = Self.pollDelay(attempt: attempt)
            do { try await sleep(delay) } catch { return }
            if Task.isCancelled { return }
            waited += delay
            attempt += 1
            await load()
        }
    }

    // MARK: - Folders

    /// `rail`: the standard five in their fixed order (offered even before the server has made
    /// them), then the user's own top-level folders by name, then "Unfiled" when the matter's root
    /// holds files.
    var folders: [MatterFolder] {
        let (files, subs) = flat
        func top(_ sub: String) -> String { sub.components(separatedBy: "/").first ?? sub }
        var tops = Set(subs.map(top).filter { !$0.isEmpty })
        for f in files where !f.sub.isEmpty { tops.insert(top(f.sub)) }
        let standard = MatterFilesService.standardFolders
        let own = tops.filter { !standard.contains($0) }.sorted { JSCompat.localeCompare($0, $1) < 0 }
        func count(_ sub: String) -> Int { files.filter { $0.sub == sub || $0.sub.hasPrefix(sub + "/") }.count }
        var out = (standard + own).map {
            MatterFolder(sub: $0, name: $0, isStandard: standard.contains($0), count: count($0))
        }
        let unfiled = files.filter { $0.sub.isEmpty }.count
        if unfiled > 0 { out.append(MatterFolder(sub: "", name: "Unfiled", isStandard: true, count: unfiled)) }
        return out
    }

    /// The folder on screen: the chosen one, or the first when it has gone.
    var openFolder: MatterFolder? {
        let all = folders
        return all.first { $0.sub == current } ?? all.first
    }

    /// The open folder's documents, its sub-folders' included: newest first, then by name.
    var openFiles: [MatterFile] { files(in: openFolder?.sub ?? "") }

    func files(in sub: String) -> [MatterFile] {
        let listed = allFiles.filter { sub.isEmpty ? $0.sub.isEmpty : ($0.sub == sub || $0.sub.hasPrefix(sub + "/")) }
        return listed.sorted { a, b in
            let ta = WireDate.parseAny(a.modified)?.timeIntervalSince1970 ?? 0
            let tb = WireDate.parseAny(b.modified)?.timeIntervalSince1970 ?? 0
            if ta != tb { return ta > tb }
            return JSCompat.localeCompare(a.name, b.name) < 0
        }
    }

    /// The documents a new conversation starts with: every one the model can read.
    var readyFiles: [ChatAttachment] { allFiles.filter(\.isReady).map(\.attachment) }

    func canRename(_ folder: MatterFolder) -> Bool { !folder.isStandard && !folder.sub.isEmpty }
    func canDelete(_ folder: MatterFolder) -> Bool { canRename(folder) }

    /// Where an attach can put documents: the standard five, then every folder the matter has.
    var destinations: [String] {
        var out = MatterFilesService.standardFolders
        for sub in flat.folders where !out.contains(sub) { out.append(sub) }
        return out
    }

    /// "Evidence / Photos".
    nonisolated static func folderLabel(_ sub: String) -> String {
        sub.isEmpty ? "Unfiled" : sub.components(separatedBy: "/").joined(separator: " / ")
    }

    // MARK: - Writes

    static let deleteFileTitle = "Delete this document?"
    static let deleteFolderTitle = "Delete this folder and everything in it?"
    static let deleteFileMessage =
        "It will be permanently deleted from this matter, with the text and search index built from it. Chats that already quoted it keep what they said."

    static func deleteFolderMessage(count n: Int) -> String {
        guard n > 0 else { return "The folder is empty." }
        return "\(n) \(n == 1 ? "document" : "documents") in it will be permanently deleted from this matter, with the text and search index built from \(n == 1 ? "it" : "them")."
    }

    @discardableResult
    func createFolder(_ name: String) async -> Bool {
        let trimmed = JSCompat.trim(name)
        guard !trimmed.isEmpty else {
            error = "Folder name is required"
            return false
        }
        return await write {
            let made = try await self.service.createFolder(projectID: self.projectID, name: trimmed)
            await self.load()
            let prefix = self.root + "/"
            self.current = made.folder.hasPrefix(prefix) ? String(made.folder.dropFirst(prefix.count)) : trimmed
            self.message = "Folder “\(trimmed)” created"
        }
    }

    @discardableResult
    func rename(_ file: MatterFile, to newName: String) async -> Bool {
        guard let files else { return false }
        return await write {
            let result = try await files.rename(name: file.name, in: file.folderName, to: newName)
            self.message = FileEditWording.renamed(result, requested: newName)
            await self.load()
        }
    }

    @discardableResult
    func delete(_ file: MatterFile) async -> Bool {
        guard let files else { return false }
        return await write {
            try await files.delete(name: file.name, folderName: file.folderName)
            self.message = "Deleted \(file.name)"
            await self.load()
        }
    }

    @discardableResult
    func renameFolder(_ folder: MatterFolder, to newName: String) async -> Bool {
        guard let files, canRename(folder) else { return false }
        return await write {
            let path = try await files.renameFolder(at: "\(self.root)/\(folder.sub)", to: newName)
            let prefix = self.root + "/"
            self.current = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : self.current
            self.message = "Renamed to \(MatterFilesViewModel.folderLabel(self.current))"
            await self.load()
        }
    }

    @discardableResult
    func deleteFolder(_ folder: MatterFolder) async -> Bool {
        guard let files, canDelete(folder) else { return false }
        return await write {
            try await files.deleteFolder(named: "\(self.root)/\(folder.sub)")
            self.message = "Deleted the folder \(folder.name)"
            await self.load()
        }
    }

    private func write(_ work: @MainActor () async throws -> Void) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        error = nil
        do {
            try await work()
            return true
        } catch {
            self.error = DisplayText.message(for: error)
            return false
        }
    }
}
