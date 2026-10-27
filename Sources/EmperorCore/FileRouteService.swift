import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol FileRouteProviding: Sendable {
    /// Saves an edited draft over its row; answers the row that now holds it.
    func saveDocument(
        id: String, title: String, content: String, type: String, chatId: String?
    ) async throws -> SaveDocumentResult
    /// The documents named, as one zip archive.
    func zip(_ entries: [ZipEntry]) async throws -> Data
    /// The text read out of a document when it was uploaded.
    func fileText(name: String, folderName: String?) async throws -> FileTextResponse
    /// A document rendered to PDF by the server, with its page-numbered footer.
    func printPDF(html: String, title: String, pageSetup: PageSetup) async throws -> Data
    /// Makes `model` the account's starting model, on the web as here.
    func setPreferredModel(_ model: ChatModel) async throws
    /// Whether the platform is down for maintenance.
    func maintenance() async throws -> MaintenanceState
}

/// The small file routes: `/save-document`, `/download-files`, `/file-text`, `/print-pdf`,
/// `/set-preferred-model` and `/maintenance`. Stateless.
///
/// The two that answer bytes are read with `perform` and classified here, because their success
/// is not JSON; each checks the bytes are what they claim to be before handing them on. No POST
/// is retried: a save or a render sent twice is not the same as one.
struct FileRouteService: FileRouteProviding {
    let client: APIClient

    /// A server-rendered PDF starts a browser on the server and can take a while on a cold one.
    static let printTimeout: TimeInterval = 90

    func saveDocument(
        id: String, title: String, content: String, type: String, chatId: String?
    ) async throws -> SaveDocumentResult {
        guard let credentials = await client.currentCredentials() else {
            throw APIError.notAuthenticated
        }
        let body = SaveDocumentRequest(
            userId: credentials.userIDString, id: id, title: title, content: content,
            type: type, source: "draft", chatId: chatId)
        let request = try await client.makeRequest("POST", "/save-document", body: body)
        let result = try await client.send(request, as: SaveDocumentResult.self)
        guard result.success == true else {
            throw APIError.server(status: 200, message: result.error ?? "The draft could not be saved.")
        }
        return result
    }

    private struct ZipBody: Encodable {
        let userId: String
        let files: [ZipEntry]
    }

    func zip(_ entries: [ZipEntry]) async throws -> Data {
        guard let credentials = await client.currentCredentials() else {
            throw APIError.notAuthenticated
        }
        let request = try await client.makeRequest(
            "POST", "/download-files",
            body: ZipBody(userId: credentials.userIDString, files: entries))
        let data = try await bytes(for: request)
        guard Self.isZip(data) else {
            throw APIError.server(status: 200, message: "The archive arrived damaged. Please try again.")
        }
        return data
    }

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

    private struct PrintBody: Encodable {
        let html: String
        let title: String
        let pageSetup: PageSetup
    }

    func printPDF(html: String, title: String, pageSetup: PageSetup) async throws -> Data {
        var request = try await client.makeRequest(
            "POST", "/print-pdf", body: PrintBody(html: html, title: title, pageSetup: pageSetup))
        request.timeoutInterval = Self.printTimeout
        let data = try await bytes(for: request)
        guard Self.isPDF(data) else {
            throw APIError.server(status: 200, message: "The PDF arrived damaged. Please try again.")
        }
        return data
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

    /// The body of a 2xx answer; anything else is classified as every other route's error is.
    private func bytes(for request: URLRequest) async throws -> Data {
        let (data, response) = try await client.perform(request)
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.classify(status: response.statusCode, body: data)
        }
        return data
    }

    /// `nil`, `""` and `"."` all mean the storage root, which the route takes as `"."`.
    static func folderParameter(_ folderName: String?) -> String {
        let trimmed = (folderName ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "." : trimmed
    }

    static func isPDF(_ data: Data) -> Bool {
        data.starts(with: Array("%PDF".utf8))
    }

    static func isZip(_ data: Data) -> Bool {
        data.starts(with: [0x50, 0x4B, 0x03, 0x04])
    }
}
