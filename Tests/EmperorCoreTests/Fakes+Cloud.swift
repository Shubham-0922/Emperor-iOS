import Foundation
@testable import EmperorCore

/// A cloud drive in memory: connections that can flip on the Nth read, a list, and a record of
/// every import and export.
final class FakeCloudDrive: CloudDriveProviding, @unchecked Sendable {
    var connectionsValue: [CloudProvider: CloudConnection]
    var connectionsError: Error?
    /// After this many reads of the connections, `connectedAfter` reads as connected.
    var connectOnRead: Int?
    var connectedAfter: CloudProvider = .google
    var connectURLValue = URL(string: "https://accounts.google.com/o/oauth2/v2/auth?x=1")!
    var connectError: Error?
    var disconnectError: Error?
    var filesValue: [CloudFile] = []
    var listError: Error?
    /// Answered for the file of this id instead of importing it.
    var importErrors: [String: Error] = [:]
    var exportResult = CloudExportResult(
        success: true, id: "x", name: "a.pdf", url: "https://drive.google.com/file/d/x/view", error: nil)
    var exportError: Error?

    private(set) var connectionReads = 0
    private(set) var listed: [CloudProvider] = []
    private(set) var disconnected: [CloudProvider] = []
    private(set) var imported: [(provider: CloudProvider, id: String, folder: String?)] = []
    private(set) var exported: [(provider: CloudProvider, name: String, folder: String?)] = []

    init(_ connections: [CloudProvider: CloudConnection] = [:]) {
        connectionsValue = connections
    }

    func connections() async throws -> [CloudProvider: CloudConnection] {
        connectionReads += 1
        if let connectionsError { throw connectionsError }
        if let connectOnRead, connectionReads >= connectOnRead {
            connectionsValue[connectedAfter] = CloudConnection(
                label: connectedAfter.label, configured: true, connected: true, email: "a@example.com")
        }
        return connectionsValue
    }

    func connectURL(_ provider: CloudProvider) async throws -> URL {
        if let connectError { throw connectError }
        return connectURLValue
    }

    func disconnect(_ provider: CloudProvider) async throws {
        if let disconnectError { throw disconnectError }
        disconnected.append(provider)
        connectionsValue[provider] = CloudConnection(
            label: provider.label, configured: true, connected: false, email: nil)
    }

    func list(_ provider: CloudProvider) async throws -> [CloudFile] {
        listed.append(provider)
        if let listError { throw listError }
        return filesValue
    }

    func importFile(
        _ provider: CloudProvider, file: CloudFile, into folder: String?
    ) async throws -> CloudImportResult {
        if let error = importErrors[file.id] { throw error }
        imported.append((provider, file.id, folder))
        return CloudImportResult(
            success: true, fileName: file.name, folderName: folder ?? ".", size: file.size,
            error: nil, code: nil)
    }

    func export(_ provider: CloudProvider, name: String, folder: String?) async throws -> CloudExportResult {
        if let exportError { throw exportError }
        exported.append((provider, name, folder))
        return exportResult
    }
}

extension CloudConnection {
    static let off = CloudConnection(configured: false, connected: false)
    static let ready = CloudConnection(configured: true, connected: false)
    static func on(_ email: String? = "a@example.com") -> CloudConnection {
        CloudConnection(configured: true, connected: true, email: email)
    }
}
