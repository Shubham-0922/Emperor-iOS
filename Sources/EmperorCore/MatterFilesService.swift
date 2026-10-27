import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A matter's own storage, as `GET /project-files` lists it: the `/user-files` item shape, every
/// `path` relative to the user's storage root (`_projects/<id>/Pleadings/Plaint.pdf`).
struct MatterFiles: Equatable, Sendable {
    /// `_projects/<id>`.
    var root: String
    var folders: [FileNode]
    var files: [FileNode]

    /// Every file, for the ledger's receipt picker: Receipts first, then by folder and name.
    var receiptChoices: [Ledger.ProjectFileRef] {
        Ledger.projectFileList(root: root, items: folders + files)
    }

    /// Every file, flattened, as the matter screens read them.
    var all: [MatterFile] { MatterFile.flatten(folders + files, root: root).files }

    /// The documents a new conversation of the matter starts with: every one the model can read
    /// (ready, or an image-only scan) — the web's `defaultProjectFiles`.
    var readyAttachments: [ChatAttachment] { all.filter(\.isReady).map(\.attachment) }
}

/// A document as the attach and chronology routes name one: its folder (relative to the user's
/// storage root) and its name.
struct MatterFileRef: Codable, Equatable, Hashable, Sendable {
    var folderName: String
    var fileName: String
}

/// One file's outcome of an attach, in the server's words.
struct AttachRow: Decodable, Equatable, Sendable {
    /// The name the copy was stored under.
    var name: String
    /// The matter folder it went into.
    var folder: String?
    /// `indexing`, `ready` or `skipped`.
    var status: String
    var source: MatterFileRef?
    /// Why it was skipped.
    var reason: String?
    var already: Bool?
    var existing: MatterFileRef?
    var processing: Bool?
    var detail: String?

    var isSkipped: Bool { status == "skipped" }

    /// The document as the person picked it.
    var sourceName: String {
        let picked = source?.fileName ?? ""
        return picked.isEmpty ? name : picked
    }

    init(name: String, folder: String? = nil, status: String, source: MatterFileRef? = nil,
         reason: String? = nil, already: Bool? = nil, existing: MatterFileRef? = nil,
         processing: Bool? = nil, detail: String? = nil) {
        self.name = name
        self.folder = folder
        self.status = status
        self.source = source
        self.reason = reason
        self.already = already
        self.existing = existing
        self.processing = processing
        self.detail = detail
    }

    private enum CodingKeys: String, CodingKey {
        case name, folder, status, source, reason, already, existing, processing, detail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.wireString(.name) ?? ""
        folder = c.wireString(.folder)
        status = c.wireString(.status) ?? "skipped"
        source = try? c.decodeIfPresent(MatterFileRef.self, forKey: .source)
        reason = c.wireString(.reason)
        already = try? c.decodeIfPresent(Bool.self, forKey: .already)
        existing = try? c.decodeIfPresent(MatterFileRef.self, forKey: .existing)
        processing = try? c.decodeIfPresent(Bool.self, forKey: .processing)
        detail = c.wireString(.detail)
    }
}

/// What an attach did: the folder, and every file's outcome.
struct AttachResult: Equatable, Sendable {
    var folder: String
    var rows: [AttachRow]
}

/// One dated event the AI read out of the matter's documents — a proposal, never saved by itself.
struct ExtractedEvent: Decodable, Equatable, Sendable {
    var date: String?
    var title: String?
    var details: String?
    var kind: String?
    /// Where it was found: "Plaint.pdf, p. 4".
    var sourceRef: String?

    init(date: String? = nil, title: String? = nil, details: String? = nil, kind: String? = nil, sourceRef: String? = nil) {
        self.date = date
        self.title = title
        self.details = details
        self.kind = kind
        self.sourceRef = sourceRef
    }

    private enum CodingKeys: String, CodingKey { case date, title, details, kind, sourceRef }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = c.wireString(.date)
        title = c.wireString(.title)
        details = c.wireString(.details)
        kind = c.wireString(.kind)
        sourceRef = c.wireString(.sourceRef)
    }
}

/// The answer to `POST /project-chronology-extract`.
struct ChronologyProposalSet: Equatable, Sendable {
    var events: [ExtractedEvent]
    /// How many documents were read.
    var files: Int
    /// Documents with no readable text yet.
    var skipped: [String]
    /// Some of the reading did not happen or failed: the list may be incomplete.
    var partial: Bool
    /// Said instead of events when there was nothing to read.
    var message: String?

    init(events: [ExtractedEvent] = [], files: Int = 0, skipped: [String] = [], partial: Bool = false, message: String? = nil) {
        self.events = events
        self.files = files
        self.skipped = skipped
        self.partial = partial
        self.message = message
    }
}

/// A matter's files and the writes on them: listing, a new folder, attaching from My Files and
/// reading a chronology out of them. Renaming and deleting go through `FileManaging`, addressed
/// by the matter's own folder (`_projects/<id>/<sub>`), as the web does.
protocol MatterFilesProviding: Sendable {
    func listing(projectID: String) async throws -> MatterFiles
    /// `name` is relative to the matter: "Drafts" or "Pleadings/Drafts".
    func createFolder(projectID: String, name: String) async throws -> (folder: String, existed: Bool)
    /// Copies My Files documents into the matter's `subfolder`. Nothing is uploaded.
    func attach(projectID: String, files: [MatterFileRef], subfolder: String) async throws -> AttachResult
    /// Reads the matter's documents — all of them when `files` is nil — and proposes dated events.
    func extractChronology(projectID: String, files: [MatterFileRef]?) async throws -> ChronologyProposalSet
}

/// `GET /project-files`, `POST /project-folder`, `POST /project-attach` and
/// `POST /project-chronology-extract`, with the bodies the web sends (`src/lib/projectsApi.js`).
///
/// Only the listing is retried: an attach that reached the server and lost its answer would be
/// skipped as "Already in this matter" on a second try, and a chronology read is a paid AI call.
struct MatterFilesService: MatterFilesProviding {
    let client: APIClient

    /// The matter's standard folders, in their fixed order. Always offered as destinations: the
    /// server makes one when a document is attached into it.
    static let standardFolders = ["Pleadings", "Orders", "Evidence", "Correspondence", "Receipts"]
    /// Documents in one attach. The server refuses more.
    static let maxAttach = 25
    /// The chronology read can run for minutes on long files.
    static let extractTimeout: TimeInterval = 180

    /// `_projects/<id>`, a matter's storage relative to the user's root.
    static func root(_ projectID: String) -> String { "_projects/\(projectID)" }

    func listing(projectID: String) async throws -> MatterFiles {
        let response = try await withRetry {
            let request = try await client.makeRequest("GET", "/project-files", query: ["projectId": projectID])
            return try await client.send(request, as: ListingResponse.self)
        }
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        let root = (response.root ?? "").isEmpty ? Self.root(projectID) : response.root!
        return MatterFiles(root: root, folders: response.folders ?? [], files: response.files ?? [])
    }

    func createFolder(projectID: String, name: String) async throws -> (folder: String, existed: Bool) {
        let response = try await post(
            "/project-folder", ["projectId": .string(projectID), "name": .string(name)], as: FolderResponse.self)
        try ProjectWriteService.check(response.success, response.error, "Could not create the folder")
        return (response.folder ?? "\(Self.root(projectID))/\(name)", response.existed ?? false)
    }

    func attach(projectID: String, files: [MatterFileRef], subfolder: String) async throws -> AttachResult {
        let list: [JSONValue] = files.map {
            .object(["folderName": .string($0.folderName), "fileName": .string($0.fileName)])
        }
        let response = try await post(
            "/project-attach",
            ["projectId": .string(projectID), "files": .array(list), "subfolder": .string(subfolder)],
            as: AttachResponse.self)
        try ProjectWriteService.check(response.success, response.error, "Could not attach these documents. Try again.")
        return AttachResult(folder: response.folder ?? "", rows: response.files ?? [])
    }

    func extractChronology(projectID: String, files: [MatterFileRef]?) async throws -> ChronologyProposalSet {
        var body: [String: JSONValue] = ["projectId": .string(projectID)]
        if let files {
            body["files"] = .array(files.map {
                .object(["folderName": .string($0.folderName), "fileName": .string($0.fileName)])
            })
        }
        let response = try await post(
            "/project-chronology-extract", body, as: ExtractResponse.self, timeout: Self.extractTimeout)
        try ProjectWriteService.check(response.success, response.error, "Emperor could not read the documents.")
        return ChronologyProposalSet(
            events: response.events ?? [], files: response.files ?? 0, skipped: response.skipped ?? [],
            partial: response.partial ?? false, message: response.message)
    }

    // MARK: - Transport

    private func post<T: Decodable & Sendable>(
        _ path: String, _ body: [String: JSONValue], as type: T.Type, timeout: TimeInterval? = nil
    ) async throws -> T {
        guard let credentials = await client.currentCredentials() else { throw APIError.notAuthenticated }
        var payload = body
        payload["userId"] = .string(credentials.userIDString)
        var request = try await client.makeRequest("POST", path, body: payload)
        if let timeout { request.timeoutInterval = timeout }
        return try await client.send(request, as: type)
    }

    // MARK: - Wire

    struct ListingResponse: Decodable, Sendable {
        var success: Bool?
        var error: String?
        var root: String?
        var folders: [FileNode]?
        var files: [FileNode]?
    }

    struct FolderResponse: Decodable, Sendable {
        var success: Bool?
        var error: String?
        var folder: String?
        var existed: Bool?
    }

    struct AttachResponse: Decodable, Sendable {
        var success: Bool?
        var error: String?
        var folder: String?
        var files: [AttachRow]?
    }

    struct ExtractResponse: Decodable, Sendable {
        var success: Bool?
        var error: String?
        var events: [ExtractedEvent]?
        var files: Int?
        var skipped: [String]?
        var partial: Bool?
        var message: String?

        private enum CodingKeys: String, CodingKey { case success, error, events, files, skipped, partial, message }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            success = try? c.decodeIfPresent(Bool.self, forKey: .success)
            error = c.wireString(.error)
            events = (try? c.decodeIfPresent(LossyList<ExtractedEvent>.self, forKey: .events))?.elements
            files = c.wireInt(.files)
            skipped = try? c.decodeIfPresent([String].self, forKey: .skipped)
            partial = try? c.decodeIfPresent(Bool.self, forKey: .partial)
            message = c.wireString(.message)
        }
    }
}
