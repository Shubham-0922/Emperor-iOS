import Foundation
@testable import EmperorCore

// The matter content stand-ins: the matter's files, attach and chronology read, the file writes
// and the case → matter bridge.

final class FakeMatterFiles: MatterFilesProviding, @unchecked Sendable {
    var listings: [MatterFiles] = []
    var listingError: Error?
    var folderAnswer: (folder: String, existed: Bool) = ("_projects/p/Drafts", false)
    var attachResult = AttachResult(folder: "_projects/p/Pleadings", rows: [])
    var attachError: Error?
    var proposals = ChronologyProposalSet()
    var extractError: Error?
    /// Runs before the extract answers, so a test can act while a read is in flight.
    var onExtract: (() async -> Void)?

    private(set) var listingCalls = 0
    private(set) var folders: [String] = []
    private(set) var attached: [(files: [MatterFileRef], subfolder: String)] = []
    private(set) var extracted: [[MatterFileRef]?] = []

    func listing(projectID: String) async throws -> MatterFiles {
        listingCalls += 1
        if let listingError { throw listingError }
        guard !listings.isEmpty else { return MatterFiles(root: "_projects/\(projectID)", folders: [], files: []) }
        // Each call takes the next listing; the last one repeats.
        return listings.count > 1 ? listings.removeFirst() : listings[0]
    }

    func createFolder(projectID: String, name: String) async throws -> (folder: String, existed: Bool) {
        folders.append(name)
        return folderAnswer
    }

    func attach(projectID: String, files: [MatterFileRef], subfolder: String) async throws -> AttachResult {
        attached.append((files, subfolder))
        if let attachError { throw attachError }
        return attachResult
    }

    func extractChronology(projectID: String, files: [MatterFileRef]?) async throws -> ChronologyProposalSet {
        extracted.append(files)
        await onExtract?()
        if let extractError { throw extractError }
        return proposals
    }
}

final class FakeFileManaging: FileManaging, @unchecked Sendable {
    private(set) var calls: [String] = []
    var error: Error?

    func delete(name: String, folderName: String?) async throws {
        calls.append("delete \(folderName ?? "")/\(name)")
        if let error { throw error }
    }

    func rename(name: String, in folderName: String?, to newName: String) async throws -> FileOperationResult {
        calls.append("rename \(folderName ?? "")/\(name) → \(newName)")
        if let error { throw error }
        return FileOperationResult(fileName: newName, folderName: folderName ?? "")
    }

    func move(name: String, from folderName: String?, to destination: String?) async throws {}

    func setFavorite(_ favorite: Bool, name: String, folderName: String?) async throws -> Bool { favorite }

    func createFolder(named path: String) async throws {}

    func renameFolder(at path: String, to newName: String) async throws -> String {
        calls.append("renameFolder \(path) → \(newName)")
        if let error { throw error }
        let parent = path.components(separatedBy: "/").dropLast().joined(separator: "/")
        return parent.isEmpty ? newName : "\(parent)/\(newName)"
    }

    func deleteFolder(named path: String) async throws {
        calls.append("deleteFolder \(path)")
        if let error { throw error }
    }

    func awaitIngestion(name: String, folderName: String?) async throws -> IngestState { .ready }

    func downloadSearchable(name: String, folderName: String?) async throws -> Data { Data() }
}

final class FakeMatterCreation: MatterCreating, @unchecked Sendable {
    var added: Result<MatterCreated, MatterRuleError> = .success(MatterCreated(projectID: "prj-1", existed: false))
    var opened: Result<MatterCreated, CaseToMatterFailure> = .success(MatterCreated(projectID: "prj-1", existed: true))
    var existing: String?
    private(set) var requests: [AddToMattersRequest] = []
    private(set) var openedCases: [String] = []

    func addToMatters(_ r: AddToMattersRequest) async -> Result<MatterCreated, MatterRuleError> {
        requests.append(r)
        return added
    }

    func existingMatter(for pick: CourtSearchResult) async -> String? { existing }

    func openCaseAsMatter(caseID: String) async -> Result<MatterCreated, CaseToMatterFailure> {
        openedCases.append(caseID)
        return opened
    }
}

final class FakeMatterDrafts: DraftHistoryProviding, @unchecked Sendable {
    var documents: [DraftedItem] = []
    var tables: [DraftedItem] = []
    var tablesError: Error?
    var documentsError: Error?
    private(set) var asked: [String] = []

    func drafts(_ kind: DraftKind) async throws -> [DraftedItem] { [] }

    func drafts(_ kind: DraftKind, projectID: String) async throws -> [DraftedItem] {
        asked.append("\(kind.rawValue) \(projectID)")
        if kind == .table, let tablesError { throw tablesError }
        if kind == .document, let documentsError { throw documentsError }
        return kind == .table ? tables : documents
    }

    func content(id: String) async throws -> String { "<h1>\(id)</h1>" }
}

/// A file node of a matter's listing.
func matterFileNode(_ path: String, status: String? = "ready", modified: String? = nil) -> FileNode {
    let name = path.components(separatedBy: "/").last ?? path
    return .file(FileNode.StoredFile(name: name, path: path, size: 10, modified: modified, status: status))
}

func matterFolderNode(_ path: String, _ files: [FileNode] = []) -> FileNode {
    let name = path.components(separatedBy: "/").last ?? path
    return .folder(FileNode.Folder(name: name, path: path, created: nil, files: files))
}
