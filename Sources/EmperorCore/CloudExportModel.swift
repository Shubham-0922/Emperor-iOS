import Foundation
#if canImport(Darwin)
import Observation
#endif

/// "Save to Google Drive" on a document: one export, its confirmation and the drive's link.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class CloudExportModel {

    struct Exported: Equatable, Identifiable, Sendable {
        let message: String
        let url: URL?
        var id: String { message + (url?.absoluteString ?? "") }
    }

    private let service: CloudDriveProviding

    private(set) var isExporting = false
    /// Set once the drive holds the file.
    var exported: Exported?
    var error: String?

    init(service: CloudDriveProviding) {
        self.service = service
    }

    /// The folder and the name the routes take, from a stored document's path.
    nonisolated static func location(ofPath path: String) -> (folder: String?, name: String) {
        guard let slash = path.lastIndex(of: "/") else { return (nil, path) }
        let folder = String(path[..<slash])
        let name = String(path[path.index(after: slash)...])
        return (folder.isEmpty ? nil : folder, name)
    }

    /// The drive's own page for the file, only as an `https` link.
    nonisolated static func driveLink(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    func export(path: String, to provider: CloudProvider) async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        let place = Self.location(ofPath: path)
        do {
            let result = try await service.export(provider, name: place.name, folder: place.folder)
            let url: URL? = Self.driveLink(result.url)
            exported = Exported(message: "\(place.name) saved to \(provider.label)", url: url)
        } catch {
            self.error = DisplayText.message(for: error)
        }
    }
}
