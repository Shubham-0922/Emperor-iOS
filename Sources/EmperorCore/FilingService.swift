import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol FilingProviding: Sendable {
    func drafts() async throws -> [FilingDraft]
    func annexures(draftID: String?, chatID: String?) async throws -> [FilingAnnexure]
    func addAnnexure(draftID: String, folderName: String, fileName: String) async throws -> FilingAnnexure
    func update(
        id: Int, title: String?, treatment: FilingTreatment?, verifyStatus: FilingVerify?
    ) async throws -> FilingAnnexure
    func delete(id: Int) async throws
    func reorder(draftID: String, orderedIDs: [Int]) async throws -> (Bool, [FilingAnnexure])
    func assemble(draftID: String, cover: FilingCover) async throws -> FilingAssemblyResult
    func bundles(draftID: String?) async throws -> [FilingBundle]
    func bundlePDF(id: Int) async throws -> Data
    func checklist(draftID: String, forum: String) async throws -> FilingChecklist
}

/// Filing assembly (`/filing/*`): drafts, their annexures, the assembler and its bundles.
///
/// Reads are retried; writes are not. Assembly above all is never retried: each run makes a new
/// bundle, and a run can take minutes. A Free account is refused on every route with a coded
/// 402, which `APIClient` turns into `.refused`.
struct FilingService: FilingProviding {
    let client: APIClient

    // MARK: - Reads

    func drafts() async throws -> [FilingDraft] {
        let response = try await withRetry {
            let request = try await client.makeRequest("GET", "/filing/drafts")
            return try await client.send(request, as: FilingDraftsResponse.self)
        }
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        return response.drafts ?? []
    }

    /// A draft's annexures. With the draft's own chat as well, annexures that chat cited are
    /// listed with the draft's, as the web lists them.
    func annexures(draftID: String?, chatID: String?) async throws -> [FilingAnnexure] {
        var query: [String: String] = [:]
        if let draftID, !draftID.isEmpty { query["draftId"] = draftID }
        if let chatID, !chatID.isEmpty { query["chatId"] = chatID }
        let response = try await withRetry { [query] in
            let request = try await client.makeRequest("GET", "/filing/annexures", query: query)
            return try await client.send(request, as: FilingAnnexuresResponse.self)
        }
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        return response.annexures ?? []
    }

    func bundles(draftID: String?) async throws -> [FilingBundle] {
        var query: [String: String] = [:]
        if let draftID, !draftID.isEmpty { query["draftId"] = draftID }
        let response = try await withRetry { [query] in
            let request = try await client.makeRequest("GET", "/filing/bundles", query: query)
            return try await client.send(request, as: FilingBundlesResponse.self)
        }
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        return response.bundles ?? []
    }

    func checklist(draftID: String, forum: String) async throws -> FilingChecklist {
        let response = try await withRetry {
            let request = try await client.makeRequest(
                "GET", "/filing/checklist", query: ["draftId": draftID, "forum": forum])
            return try await client.send(request, as: FilingChecklistResponse.self)
        }
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        guard let checklist = response.checklist else {
            throw APIError.server(status: 200, message: "The checklist could not be prepared.")
        }
        return checklist
    }

    /// A bundle's PDF. A bundle that is gone answers with JSON, not bytes; anything that is not
    /// a PDF is treated as gone.
    func bundlePDF(id: Int) async throws -> Data {
        let request = try await client.makeRequest(
            "GET", "/filing/bundle-download", query: ["bundleId": String(id)])
        let (data, response) = try await client.perform(request)
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.classify(status: response.statusCode, body: data)
        }
        guard data.starts(with: Data("%PDF".utf8)) else {
            throw APIError.server(status: 404, message: "That bundle is no longer available.")
        }
        return data
    }

    // MARK: - Writes

    private struct AddBody: Encodable {
        let userId: String
        let draftId: String
        let folderName: String
        let fileName: String
    }

    private struct UpdateBody: Encodable {
        let userId: String
        let id: Int
        let title: String?
        let treatment: String?
        let verify_status: String?
    }

    private struct IDBody: Encodable {
        let userId: String
        let id: Int
    }

    private struct ReorderBody: Encodable {
        let userId: String
        let draftId: String
        let orderedIds: [Int]
    }

    private struct AssembleBody: Encodable {
        struct Options: Encodable { let numbering: String }
        let userId: String
        let draftId: String
        let cover: FilingCover
        let options: Options
    }

    private func userID() async throws -> String {
        guard let credentials = await client.currentCredentials() else {
            throw APIError.notAuthenticated
        }
        return credentials.userIDString
    }

    /// Registers a file from My Files as the draft's next annexure. A file at the storage root
    /// is in the folder `"."`; the route refuses an empty folder.
    func addAnnexure(draftID: String, folderName: String, fileName: String) async throws -> FilingAnnexure {
        let body = AddBody(
            userId: try await userID(), draftId: draftID,
            folderName: folderName.isEmpty ? "." : folderName, fileName: fileName)
        let request = try await client.makeRequest("POST", "/filing/annexures", body: body)
        let response = try await client.send(request, as: FilingAnnexureResponse.self)
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        guard let annexure = response.annexure else {
            throw APIError.server(status: 200, message: "Could not add annexure")
        }
        return annexure
    }

    /// Changes an annexure's title, treatment or verification; only what is given is sent.
    func update(
        id: Int, title: String?, treatment: FilingTreatment?, verifyStatus: FilingVerify?
    ) async throws -> FilingAnnexure {
        let body = UpdateBody(
            userId: try await userID(), id: id, title: title, treatment: treatment?.rawValue,
            verify_status: verifyStatus?.rawValue)
        let request = try await client.makeRequest("POST", "/filing/annexures/update", body: body)
        let response = try await client.send(request, as: FilingAnnexureResponse.self)
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        guard let annexure = response.annexure else {
            throw APIError.server(status: 200, message: "Could not update the annexure")
        }
        return annexure
    }

    func delete(id: Int) async throws {
        let body = IDBody(userId: try await userID(), id: id)
        let request = try await client.makeRequest("POST", "/filing/annexures/delete", body: body)
        let response = try await client.send(request, as: FilingOKResponse.self)
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
    }

    /// Sets the binding order. Marks are never renumbered; the answer says whether the order
    /// still follows them.
    func reorder(draftID: String, orderedIDs: [Int]) async throws -> (Bool, [FilingAnnexure]) {
        let body = ReorderBody(userId: try await userID(), draftId: draftID, orderedIds: orderedIDs)
        let request = try await client.makeRequest("POST", "/filing/annexures/reorder", body: body)
        let response = try await client.send(request, as: FilingReorderResponse.self)
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        return (response.orderMatchesMarks ?? true, response.annexures ?? [])
    }

    /// Assembles the bundle. Once, never retried: every run makes a bundle of its own. A run
    /// the assembler refused comes back as a result with `success: false`, not as an error.
    func assemble(draftID: String, cover: FilingCover) async throws -> FilingAssemblyResult {
        let body = AssembleBody(
            userId: try await userID(), draftId: draftID, cover: cover,
            options: .init(numbering: "arabic"))
        let request = try await client.makeRequest("POST", "/filing/assemble", body: body)
        let (data, response) = try await client.perform(request)
        let status = response.statusCode
        // A rejected assembly is a 400 carrying every reason in `errors`; they are all shown,
        // so it is read as an answer, not thrown as the one-line `error`.
        if status == 400 {
            let rejected = try? JSONDecoder().decode(FilingAssemblyResult.self, from: data)
            if let rejected, !rejected.success { return rejected }
        }
        if !(200..<300).contains(status) {
            throw APIError.classify(status: status, body: data)
        }
        do {
            return try JSONDecoder().decode(FilingAssemblyResult.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}
