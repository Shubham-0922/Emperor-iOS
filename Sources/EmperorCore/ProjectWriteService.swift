import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The writes on a matter's own record, as a view model needs them.
protocol ProjectWriting: Sendable {
    /// Creates the matter when `body.id` is nil; otherwise updates the keys the body carries.
    func save(_ body: ProjectBody) async throws -> Project
    func patch(projectID: String, fields: ProjectFields) async throws -> Project
    func delete(projectID: String, confirmName: String) async throws -> DeleteSummary
    func uploadBanner(projectID: String, jpegOrPNG image: Data, mime: String) async throws
    func removeBanner(projectID: String) async throws
    func saveUpdate(_ body: [String: JSONValue]) async throws -> SavedUpdate
    func deleteUpdate(id: String) async throws
    func saveTask(_ body: [String: JSONValue]) async throws -> ProjectTask
    func deleteTask(id: String) async throws
    func saveLedger(_ body: [String: JSONValue]) async throws -> LedgerEntry
    func deleteLedger(id: String) async throws
    func savePerson(_ body: [String: JSONValue]) async throws -> ProjectPerson
    func deletePerson(id: String) async throws
    /// Links a tracked case, or unlinks with nil.
    func linkCase(projectID: String, caseID: String?) async throws -> Project
    /// The user's matter for a tracked case — an existing one (`existed`) or a new one.
    func projectFromCase(caseID: String, name: String?, banner: String?, color: String?) async throws
        -> (project: Project, existed: Bool)
    func refreshCase(projectID: String) async throws -> RefreshOutcome
}

/// `POST /project`, `/project-patch`, `DELETE /project`, the banner, chronology, task, ledger and
/// people writes, and the court-case link, matter-from-case and refresh — each called by exactly one
/// method here, with the body the web sends (`src/lib/projectsApi.js`).
///
/// ## Never retried
///
/// None of these goes through `withRetry`. A create, a payment recorded or a refresh that reached
/// the server and lost its answer on the way back would be done twice by a retry — two matters, the
/// same payment counted twice, the court asked again inside its five-minute window. A failure is
/// shown, and the person decides.
///
/// ## The caller is in the body
///
/// Every POST carries `userId` (the session's, as text) beside the bearer token; GET and DELETE carry
/// it in the query, which `APIClient.makeRequest` adds.
struct ProjectWriteService: ProjectWriting {
    let client: APIClient

    /// A banner is up to 2 MB of image, which is ~2.8 MB of JSON on the way up.
    static let bannerTimeout: TimeInterval = 120
    /// The court refresh runs for up to 150 seconds before the server gives up on the court.
    static let refreshTimeout: TimeInterval = 170

    // MARK: - The matter

    func save(_ body: ProjectBody) async throws -> Project {
        let response = try await post("/project", body.json, as: ProjectWriteResponse.self)
        try Self.check(response.success, response.error, "The matter could not be saved.")
        guard let project = response.project else {
            throw APIError.server(status: 200, message: "The matter could not be saved.")
        }
        return project
    }

    func patch(projectID: String, fields: ProjectFields) async throws -> Project {
        let unknown = Set(fields.values.keys).subtracting(ProjectFields.knownKeys)
        if let first = unknown.sorted().first {
            // The route refuses an unknown key; refused here instead of a round trip to learn it.
            throw APIError.server(status: 400, message: "Unknown project field: \(first)")
        }
        let response = try await post(
            "/project-patch",
            ["projectId": .string(projectID), "fields": .object(fields.json)],
            as: ProjectWriteResponse.self)
        try Self.check(response.success, response.error, "Could not save that to the matter.")
        guard let project = response.project else {
            throw APIError.server(status: 200, message: "Could not save that to the matter.")
        }
        return project
    }

    /// Deletes the matter and everything it holds. `confirmName` is the stored name, verbatim.
    func delete(projectID: String, confirmName: String) async throws -> DeleteSummary {
        let response = try await delete(
            "/project", ["id": projectID, "confirm": confirmName], as: DeleteProjectResponse.self)
        try Self.check(response.success, response.error, "The matter could not be deleted.")
        return response.deleted ?? DeleteSummary()
    }

    // MARK: - Banner image

    /// Uploads a banner picture as a data URL. Checked here first against the server's own rules
    /// (size, and the bytes being the image they claim), in the server's words.
    func uploadBanner(projectID: String, jpegOrPNG image: Data, mime: String) async throws {
        try Self.checkBanner(image)
        let declared = MatterRules.bannerImageType(image)?.mime ?? mime
        let dataURL = "data:\(declared);base64,\(image.base64EncodedString())"
        let response = try await post(
            "/project-banner", ["projectId": .string(projectID), "dataUrl": .string(dataURL)],
            as: WriteEnvelope.self, timeout: Self.bannerTimeout)
        try Self.check(response.success, response.error, "The banner image was not uploaded.")
    }

    static func checkBanner(_ image: Data) throws {
        if image.isEmpty { throw MatterRuleError(message: "The banner image is empty") }
        if image.count > MatterRules.bannerMaxBytes {
            throw MatterRuleError(message: "The banner image must be 2 MB or smaller")
        }
        if MatterRules.bannerImageType(image) == nil {
            throw MatterRuleError(message: "The banner must be a PNG, JPEG or WebP image")
        }
    }

    func removeBanner(projectID: String) async throws {
        let response = try await delete("/project-banner", ["id": projectID], as: WriteEnvelope.self)
        try Self.check(response.success, response.error, "The banner image could not be removed.")
    }

    // MARK: - Chronology, tasks, money, people

    func saveUpdate(_ body: [String: JSONValue]) async throws -> SavedUpdate {
        let response = try await post("/project-update", body, as: SavedUpdateResponse.self)
        try Self.check(response.success, response.error, "Could not save this entry.")
        guard let id = response.id ?? response.update?.id else {
            throw APIError.server(status: 200, message: "Could not save this entry.")
        }
        return SavedUpdate(id: id, update: response.update, nextHearingDate: response.nextHearingDate)
    }

    func deleteUpdate(id: String) async throws {
        try await deleteChild("/project-update", id: id, fallback: "Could not delete this entry.")
    }

    func saveTask(_ body: [String: JSONValue]) async throws -> ProjectTask {
        try await saveChild("/project-task", body, fallback: "Could not save the task.")
    }

    func deleteTask(id: String) async throws {
        try await deleteChild("/project-task", id: id, fallback: "Could not delete the task.")
    }

    func saveLedger(_ body: [String: JSONValue]) async throws -> LedgerEntry {
        try await saveChild("/project-ledger", body, fallback: "Could not save the entry.")
    }

    func deleteLedger(id: String) async throws {
        try await deleteChild("/project-ledger", id: id, fallback: "Could not delete the entry.")
    }

    func savePerson(_ body: [String: JSONValue]) async throws -> ProjectPerson {
        try await saveChild("/project-person", body, fallback: "Could not save this person.")
    }

    func deletePerson(id: String) async throws {
        try await deleteChild("/project-person", id: id, fallback: "Could not remove this person.")
    }

    private func saveChild<Row: Decodable & Sendable>(
        _ path: String, _ body: [String: JSONValue], fallback: String
    ) async throws -> Row {
        let response = try await post(path, body, as: ChildRowResponse<Row>.self)
        try Self.check(response.success, response.error, fallback)
        guard let row = response.row else { throw APIError.server(status: 200, message: fallback) }
        return row
    }

    private func deleteChild(_ path: String, id: String, fallback: String) async throws {
        let response = try await delete(path, ["id": id], as: WriteEnvelope.self)
        try Self.check(response.success, response.error, fallback)
    }

    // MARK: - The court case

    /// The key is always sent — `null` unlinks — because the route refuses a body without it.
    func linkCase(projectID: String, caseID: String?) async throws -> Project {
        let caseValue: JSONValue = caseID.map(JSONValue.string) ?? .null
        let response: ProjectWriteResponse
        do {
            response = try await post(
                "/project-link-case", ["projectId": .string(projectID), "caseId": caseValue],
                as: ProjectWriteResponse.self)
        } catch APIError.server(403, _) where caseID != nil {
            throw APIError.server(status: 403, message: Self.notOnTheTeam)
        }
        try Self.check(response.success, response.error,
                       caseID == nil ? "Could not unlink the case." : "Could not link the case.")
        guard let project = response.project else {
            throw APIError.server(status: 200, message: "Could not link the case.")
        }
        return project
    }

    static let notOnTheTeam = "You are not on the team that tracks this case, so it cannot be linked."

    func projectFromCase(caseID: String, name: String?, banner: String?, color: String?) async throws
        -> (project: Project, existed: Bool) {
        var body: [String: JSONValue] = ["caseId": .string(caseID)]
        if let name, !JSCompat.trim(name).isEmpty { body["name"] = .string(name) }
        if let banner { body["banner"] = .string(banner) }
        // The web always sends the colour key, `null` for none.
        body["color"] = color.map(JSONValue.string) ?? .null
        let response = try await post("/project-from-case", body, as: ProjectWriteResponse.self)
        try Self.check(response.success, response.error, "The matter could not be created.")
        guard let project = response.project else {
            throw APIError.server(status: 200, message: "The matter could not be created.")
        }
        return (project, response.existed ?? false)
    }

    /// Asks the court to re-read the linked case. The answer is read here rather than by
    /// `APIClient.send`, so a 429's `retryAfter` and a 502's sentence are kept.
    func refreshCase(projectID: String) async throws -> RefreshOutcome {
        guard let credentials = await client.currentCredentials() else { throw APIError.notAuthenticated }
        var request = try await client.makeRequest(
            "POST", "/project-case-refresh",
            body: ["userId": JSONValue.string(credentials.userIDString), "projectId": .string(projectID)])
        request.timeoutInterval = Self.refreshTimeout
        let (data, response) = try await client.perform(request)
        return try Self.readRefresh(data: data, status: response.statusCode)
    }

    static func readRefresh(data: Data, status: Int) throws -> RefreshOutcome {
        let decoded = try? JSONDecoder().decode(RefreshResponse.self, from: data)
        switch status {
        case 200..<300:
            guard decoded?.success == true else {
                return .courtFailed(message: decoded?.error ?? "Could not refresh from the court.")
            }
            return .done(lastSyncedAt: decoded?.lastSyncedAt, counts: decoded?.counts ?? RefreshCounts())
        case 429:
            return .tooSoon(
                retryAfter: RefreshOutcome.retrySeconds(decoded?.retryAfter),
                message: decoded?.error ?? "This case was refreshed a moment ago — try again in a few minutes.")
        case 502:
            return .courtFailed(message: decoded?.error ?? "The court refresh failed")
        case 503:
            if let notice = try? JSONDecoder().decode(MaintenanceBody.self, from: data), notice.maintenance == true {
                let text = [notice.message, notice.error].compactMap { $0 }.first { !$0.isEmpty }
                throw APIError.maintenance(
                    message: text ?? "Emperor is down for maintenance. Please try again shortly.")
            }
            throw APIError.classify(status: status, body: data)
        default:
            throw APIError.classify(status: status, body: data)
        }
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

    private func delete<T: Decodable & Sendable>(_ path: String, _ query: [String: String], as type: T.Type) async throws -> T {
        var request = try await client.makeRequest("DELETE", path, query: query)
        request.url = Self.strictQuery(request.url)
        return try await client.send(request, as: type)
    }

    /// The query re-encoded so every value arrives as typed.
    ///
    /// `URLComponents` leaves `+` as it is in a query, and the server reads a `+` as a space — so a
    /// matter named "A+B" could never be deleted, its typed name never matching. Every character
    /// outside the unreserved set is percent-encoded instead (`+` as `%2B`, `&` as `%26`).
    static func strictQuery(_ url: URL?) -> URL? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, !items.isEmpty else { return url }
        var allowed = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
        allowed.insert(charactersIn: "-._~")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        components.percentEncodedQuery = items
            .sorted { $0.name < $1.name }
            .map { "\(enc($0.name))=\(enc($0.value ?? ""))" }
            .joined(separator: "&")
        return components.url ?? url
    }

    /// A 200 that does not say `success` is a refusal, worded as the server worded it.
    static func check(_ success: Bool?, _ error: String?, _ fallback: String) throws {
        guard success != true else { return }
        throw APIError.server(status: 200, message: (error?.isEmpty == false ? error : nil) ?? fallback)
    }
}
