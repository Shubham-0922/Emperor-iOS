import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The matter operations a view model needs.
protocol ProjectProviding: Sendable {
    func projects(includeArchived: Bool) async throws -> [Project]
    func project(id: String) async throws -> ProjectDetail
    /// An uploaded banner's bytes (png, jpeg or webp). `version` is the matter's `updated_at`,
    /// so a changed picture is a different request.
    func bannerImage(projectID: String, version: String) async throws -> Data
}

extension ProjectProviding {
    /// Stand-ins that draw no pictures need not answer; the banner then falls back to its preset.
    func bannerImage(projectID: String, version: String) async throws -> Data {
        throw APIError.server(status: 404, message: "No banner image.")
    }
}

/// One matter and everything hanging off it — the web's `normalize`d payload: every list
/// present (empty when the server sent none), `courtHistory[].data` an object, and totals summed
/// from the ledger wherever the server sent none.
struct ProjectDetail: Equatable, Sendable {
    var project: Project
    /// The matter's own record, newest first as the server sends it; rows with neither a title
    /// nor a body are dropped.
    var updates: [ProjectUpdate]
    var chats: [ProjectChat]
    /// The linked case's record. Empty when nothing is linked, or the user is not in the team
    /// that tracks the case.
    var courtHistory: [CourtHistoryItem]
    var linkedCase: LinkedCase?
    var tasks: [ProjectTask]
    var ledger: [LedgerEntry]
    var people: [ProjectPerson]
    var totals: MatterRules.LedgerTotals

    init(
        project: Project, updates: [ProjectUpdate] = [], chats: [ProjectChat] = [],
        courtHistory: [CourtHistoryItem] = [], linkedCase: LinkedCase? = nil,
        tasks: [ProjectTask] = [], ledger: [LedgerEntry] = [], people: [ProjectPerson] = [],
        totals: MatterRules.LedgerTotals? = nil
    ) {
        self.project = project
        self.updates = updates
        self.chats = chats
        self.courtHistory = courtHistory
        self.linkedCase = linkedCase
        self.tasks = tasks
        self.ledger = ledger
        self.people = people
        self.totals = totals ?? Ledger.totals(ledger.map(\.ledgerEntry))
    }

    /// The payload as the screens read it.
    init(response: ProjectDetailResponse, project: Project) {
        let ledger = response.ledger ?? []
        let summed = Ledger.totals(ledger.map(\.ledgerEntry))
        self.init(
            project: project,
            updates: (response.updates ?? []).filter(\.isRenderable),
            chats: response.chats ?? [],
            courtHistory: (response.courtHistory ?? []).filter(\.isRenderable),
            linkedCase: response.linkedCase,
            tasks: response.tasks ?? [],
            ledger: ledger,
            people: response.people ?? [],
            totals: response.totals.map { $0.over(summed) } ?? summed)
    }
}

/// `GET /projects`, `GET /project` and `GET /project-banner` — the user's matters.
///
/// ## Reads only, in this build
///
/// The matter screens here show what the web keeps; nothing on them writes yet. The writes land
/// with the matter forms, each behind the web's own validation (`MatterRules`).
///
/// ## Every matter, archived ones too
///
/// The list always asks for archived matters (`includeArchived=1`), as the web's Matters page
/// does: an archived matter still owns its linked case, so leaving it out would bring that case
/// back onto the list as an unlinked "tracked case". The status filter is applied on the phone.
///
/// ## The order is the screen's
///
/// The server sends the list by priority, next hearing and last update; the Matters screen sorts
/// it itself (`MattersListViewModel`) by recent activity, next hearing or name, as the web does.
struct ProjectService: ProjectProviding {
    let client: APIClient

    /// Every matter this user owns; archived ones only when asked for.
    func projects(includeArchived: Bool = false) async throws -> [Project] {
        // Sent only when true, as the literal "1" the route reads.
        let query = includeArchived ? ["includeArchived": "1"] : [:]

        let response = try await withRetry {
            let request = try await client.makeRequest("GET", "/projects", query: query)
            return try await client.send(request, as: ProjectListResponse.self)
        }
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        return response.projects ?? []
    }

    /// One matter, its own record, its tasks, money and people, and the linked case's record.
    ///
    /// - Important: a missing matter and someone else's matter are the same answer, a 404 with
    ///   an error envelope. It is reworded here to `projectGoneMessage`, which is also how the
    ///   workspace recognises "this matter is not there" (`MatterWorkspaceViewModel`). A 404
    ///   with no envelope is a server without the route and keeps its own wording — it is a
    ///   failure to load, not a deleted matter.
    func project(id: String) async throws -> ProjectDetail {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.server(status: 404, message: Self.projectGoneMessage)
        }

        do {
            let response = try await withRetry {
                let request = try await client.makeRequest(
                    "GET", "/project", query: ["id": trimmed])
                return try await client.send(request, as: ProjectDetailResponse.self)
            }
            try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
            guard let project = response.project else {
                throw APIError.server(status: 404, message: Self.projectGoneMessage)
            }
            return ProjectDetail(response: response, project: project)
        } catch let error as APIError {
            throw Self.rewritingMissing(error)
        }
    }

    /// An uploaded banner, as bytes. The bearer header carries the session, so the screen loads
    /// it through here rather than through a plain image URL.
    func bannerImage(projectID: String, version: String) async throws -> Data {
        var query = ["id": projectID]
        if !version.isEmpty { query["v"] = version }
        let request = try await client.makeRequest("GET", "/project-banner", query: query)
        let (data, response) = try await client.perform(request)
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.classify(status: response.statusCode, body: data)
        }
        guard !data.isEmpty else {
            throw APIError.server(status: 404, message: "No banner image.")
        }
        return data
    }

    static let projectGoneMessage =
        "This matter no longer exists, or belongs to another account."

    /// The wording `APIError.classify` gives a status whose body carried no error.
    static let bareStatusPrefix = "The server returned status"

    /// A 404 that came with the server's own word becomes `projectGoneMessage`; every other
    /// failure is left exactly as it was.
    static func rewritingMissing(_ error: APIError) -> APIError {
        guard case .server(404, let message) = error, !message.hasPrefix(bareStatusPrefix) else {
            return error
        }
        return .server(status: 404, message: projectGoneMessage)
    }
}
