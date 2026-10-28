import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol FileRouteProviding: Sendable {
    /// The text read out of a document when it was uploaded.
    func fileText(name: String, folderName: String?) async throws -> FileTextResponse
    /// Makes `model` the account's starting model, on the web as here.
    func setPreferredModel(_ model: ChatModel) async throws
    /// Whether the platform is down for maintenance.
    func maintenance() async throws -> MaintenanceState
}

/// Three small routes no other service calls: `/file-text` (a document's extracted text, shown
/// when the document itself cannot be), `/set-preferred-model` and `/maintenance`. Stateless.
/// The write is never retried: a save sent twice is not the same as one.
struct FileRouteService: FileRouteProviding {
    let client: APIClient

    func fileText(name: String, folderName: String?) async throws -> FileTextResponse {
        let folder = Self.folderParameter(folderName)
        let response = try await withRetry {
            let request = try await client.makeRequest(
                "GET", "/file-text", query: ["fileName": name, "folderName": folder])
            return try await client.send(request, as: FileTextResponse.self)
        }
        guard response.success != false else {
            throw APIError.server(
                status: 200, message: response.error ?? "The text of this document could not be read.")
        }
        return response
    }

    private struct ModelBody: Encodable {
        let userId: String
        let model: String
    }

    private struct SuccessResponse: Decodable {
        let success: Bool?
        let error: String?
    }

    func setPreferredModel(_ model: ChatModel) async throws {
        guard let credentials = await client.currentCredentials() else {
            throw APIError.notAuthenticated
        }
        let request = try await client.makeRequest(
            "POST", "/set-preferred-model",
            body: ModelBody(userId: credentials.userIDString, model: model.rawValue))
        let response = try await client.send(request, as: SuccessResponse.self)
        guard response.success == true else {
            throw APIError.server(
                status: 200, message: response.error ?? "The answer mode could not be saved.")
        }
    }

    func maintenance() async throws -> MaintenanceState {
        let request = try await client.makeRequest("GET", "/maintenance")
        return try await client.send(request, as: MaintenanceState.self)
    }

    // MARK: - Helpers

    /// `nil`, `""` and `"."` all mean the storage root, which the route takes as `"."`.
    static func folderParameter(_ folderName: String?) -> String {
        let trimmed = (folderName ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "." : trimmed
    }
}
