import Foundation

protocol CloudDriveProviding: Sendable {
    /// Each provider's state: set up on this server, connected, and as whom.
    func connections() async throws -> [CloudProvider: CloudConnection]
    /// The provider's own sign-in page, to open in Safari.
    func connectURL(_ provider: CloudProvider) async throws -> URL
    func disconnect(_ provider: CloudProvider) async throws
    /// The files the import sheet offers.
    func list(_ provider: CloudProvider) async throws -> [CloudFile]
    /// Copies one file from the drive into `folder` (`nil` for the top level).
    func importFile(_ provider: CloudProvider, file: CloudFile, into folder: String?) async throws -> CloudImportResult
    /// Saves one stored document to the drive. `folder` is `nil` for the top level.
    func export(_ provider: CloudProvider, name: String, folder: String?) async throws -> CloudExportResult
}

/// Google Drive and OneDrive, through the platform's `/cloud/*` routes. Stateless.
///
/// The server holds the drive's tokens; the phone only ever sends its own bearer token. Reads
/// retry on a transient failure; writes never do — an import repeated is a second copy.
struct CloudDriveService: CloudDriveProviding {
    let client: APIClient

    /// The only hosts a sign-in page may be on: the providers' own.
    static let signInHosts: Set<String> = ["accounts.google.com", "login.microsoftonline.com"]

    func connections() async throws -> [CloudProvider: CloudConnection] {
        let response = try await Self.rewording {
            try await withRetry {
                let request = try await client.makeRequest("GET", "/cloud/connections")
                return try await client.send(request, as: CloudConnectionsResponse.self)
            }
        }
        try Self.check(response.success, response.error, "Could not load your connected services.")
        var out: [CloudProvider: CloudConnection] = [:]
        for (key, value) in response.providers ?? [:] {
            if let provider = CloudProvider(rawValue: key) { out[provider] = value }
        }
        return out
    }

    func connectURL(_ provider: CloudProvider) async throws -> URL {
        let response = try await Self.rewording {
            try await withRetry {
                let request = try await client.makeRequest(
                    "GET", "/cloud/connect", query: ["provider": provider.rawValue])
                return try await client.send(request, as: CloudConnectResponse.self)
            }
        }
        try Self.check(response.success, response.error, "Could not start the connection")
        guard let url = Self.signInURL(response.url) else {
            throw APIError.server(
                status: 200, message: "The sign-in page for \(provider.label) could not be opened.")
        }
        return url
    }

    /// The page to open, only when it is an `https` page on a provider's own sign-in host.
    static func signInURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              signInHosts.contains(host)
        else { return nil }
        return url
    }

    private struct ProviderBody: Encodable {
        let userId: String
        let provider: String
    }

    func disconnect(_ provider: CloudProvider) async throws {
        let userID = try await userIDString()
        let response = try await Self.rewording {
            let request = try await client.makeRequest(
                "POST", "/cloud/disconnect",
                body: ProviderBody(userId: userID, provider: provider.rawValue))
            return try await client.send(request, as: CloudSuccessResponse.self)
        }
        try Self.check(response.success, response.error, "Could not disconnect \(provider.label).")
    }

    func list(_ provider: CloudProvider) async throws -> [CloudFile] {
        let response = try await Self.rewording {
            try await withRetry {
                let request = try await client.makeRequest(
                    "GET", "/cloud/list", query: ["provider": provider.rawValue])
                return try await client.send(request, as: CloudListResponse.self)
            }
        }
        try Self.check(response.success, response.error, "Could not list your cloud files")
        return response.files ?? []
    }

    private struct ImportBody: Encodable {
        let userId: String
        let provider: String
        let fileId: String
        let fileName: String
        let folderName: String
    }

    func importFile(
        _ provider: CloudProvider, file: CloudFile, into folder: String?
    ) async throws -> CloudImportResult {
        let userID = try await userIDString()
        let body = ImportBody(
            userId: userID, provider: provider.rawValue, fileId: file.id, fileName: file.name,
            folderName: Self.folderName(folder))
        let response = try await Self.rewording {
            let request = try await client.makeRequest("POST", "/cloud/import", body: body)
            return try await client.send(request, as: CloudImportResult.self)
        }
        try Self.check(response.success, response.error, "Import failed")
        return response
    }

    private struct ExportBody: Encodable {
        let userId: String
        let provider: String
        let folderName: String
        let fileName: String
    }

    func export(_ provider: CloudProvider, name: String, folder: String?) async throws -> CloudExportResult {
        let userID = try await userIDString()
        let body = ExportBody(
            userId: userID, provider: provider.rawValue, folderName: Self.folderName(folder),
            fileName: name)
        let response = try await Self.rewording {
            let request = try await client.makeRequest("POST", "/cloud/export", body: body)
            return try await client.send(request, as: CloudExportResult.self)
        }
        try Self.check(response.success, response.error, "Export failed")
        return response
    }

    // MARK: - Helpers

    /// The storage root is `"."` on the wire, as the web sends it.
    static func folderName(_ folder: String?) -> String {
        guard let folder, !folder.isEmpty else { return "." }
        return folder
    }

    private func userIDString() async throws -> String {
        guard let credentials = await client.currentCredentials() else {
            throw APIError.notAuthenticated
        }
        return credentials.userIDString
    }

    /// A 200 that does not say `success` is a refusal, in the server's words for the app.
    private static func check(_ success: Bool?, _ error: String?, _ fallback: String) throws {
        guard success != true else { return }
        throw APIError.server(status: 200, message: CloudCopy.forApp(error ?? fallback))
    }

    /// The server's sentences point at the web's Settings; on the phone they point at Account.
    private static func rewording<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let APIError.server(status, message) {
            throw APIError.server(status: status, message: CloudCopy.forApp(message))
        }
    }
}
