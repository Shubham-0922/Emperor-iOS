import Foundation

/// A cloud drive the account can connect: the two the platform offers.
enum CloudProvider: String, CaseIterable, Codable, Sendable {
    case google
    case microsoft

    /// The web's own names for them (`src/pages/Settings.jsx`).
    var label: String { self == .google ? "Google Drive" : "OneDrive" }
}

/// One provider's entry in `GET /cloud/connections`.
struct CloudConnection: Decodable, Equatable, Sendable {
    let label: String?
    let configured: Bool?
    let connected: Bool?
    let email: String?

    init(label: String? = nil, configured: Bool? = nil, connected: Bool? = nil, email: String? = nil) {
        self.label = label
        self.configured = configured
        self.connected = connected
        self.email = email
    }

    var isConfigured: Bool { configured == true }
    var isConnected: Bool { connected == true }
}

struct CloudConnectionsResponse: Decodable, Sendable {
    let success: Bool?
    let providers: [String: CloudConnection]?
    let error: String?
}

struct CloudConnectResponse: Decodable, Sendable {
    let success: Bool?
    let url: String?
    let error: String?
}

struct CloudSuccessResponse: Decodable, Sendable {
    let success: Bool?
    let error: String?
}

struct CloudListResponse: Decodable, Sendable {
    let success: Bool?
    let files: [CloudFile]?
    let error: String?
}

/// A file in the drive, as `GET /cloud/list` lists it. OneDrive sends no type (`mime` is null).
struct CloudFile: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let mime: String?
    let size: Double?
    let modifiedRaw: String?

    enum CodingKeys: String, CodingKey {
        case id, name, mime, size
        case modifiedRaw = "modified"
    }

    init(id: String, name: String, mime: String? = nil, size: Double? = nil, modifiedRaw: String? = nil) {
        self.id = id
        self.name = name
        self.mime = mime
        self.size = size
        self.modifiedRaw = modifiedRaw
    }

    var modified: Date? { WireDate.parseAny(modifiedRaw) }

    /// "2.0 KB · 1 Oct 2026", or whichever half exists. The day is India's, as every date here.
    var detailLine: String? {
        var parts: [String] = []
        if let size, size > 0 {
            parts.append(FileSize.format(Int(size)))
        }
        if let modified {
            parts.append(Self.dayFormatter.string(from: modified))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    nonisolated(unsafe) private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = WireDate.india
        f.dateFormat = "d MMM yyyy"
        return f
    }()
}

/// `POST /cloud/import`: the bytes are on disk; reading them continues on the server.
struct CloudImportResult: Decodable, Sendable {
    let success: Bool?
    let fileName: String?
    let folderName: String?
    let size: Double?
    let error: String?
    let code: String?
}

/// `POST /cloud/export`: the file as the drive now holds it.
struct CloudExportResult: Decodable, Sendable {
    let success: Bool?
    let id: String?
    let name: String?
    let url: String?
    let error: String?
}

/// A sign-in page to show, for the provider it connects. Identifiable so a sheet can present it.
struct IdentifiedURL: Identifiable, Equatable, Sendable {
    let provider: CloudProvider
    let url: URL

    var id: String { provider.rawValue + "|" + url.absoluteString }
}

/// The words around the cloud drives that are the web's, adapted to where things are on a phone.
enum CloudCopy {
    /// The web's `CLOUD_SOON` (`src/pages/MyFilesPage.jsx`), for a server with no drive set up.
    static let soon =
        "Google Drive and OneDrive sync is coming soon. Until then, download files and upload them here."

    static let notConfigured = "Not configured on this server."
    static let notConnected = "Save files to it, and import documents from it."
    static let notAvailable = "Not available yet"

    /// The privacy note under the web's card.
    static let footer = """
        Files you export are uploaded to your own drive; files you import are copied into your \
        EmperorAI storage. Access is limited to what this app creates or opens — it cannot read \
        the rest of your Drive. Tokens are stored encrypted, and Disconnect stops access at any time.
        """

    static let emptyDrive =
        "No importable files in this drive — Google's own Docs and Sheets can't be downloaded as files, so they are left out."

    static let listCap = "The 50 most recently changed files are listed."

    static let notConnectedYet = "Not connected yet. Try again."

    static func disconnectQuestion(_ provider: CloudProvider) -> String {
        "Disconnect \(provider.label)?"
    }

    static let disconnectMessage = "Emperor will stop saving to it and importing from it."

    /// The server's sentences say where to fix things on the web — "Settings → Connected
    /// services". On the phone that card is under Account, so the sentence says so.
    static func forApp(_ message: String) -> String {
        message
            .replacingOccurrences(of: "Settings → Connected services", with: "Account → Connected services")
            .replacingOccurrences(of: "in Settings", with: "in Account → Connected services")
    }

    /// The sentence a provider's own server answers when it is not connected, worded for the app.
    static func notConnectedMessage(_ provider: CloudProvider) -> String {
        "\(provider.label) is not connected — connect it in Account → Connected services"
    }
}
