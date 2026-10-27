import Foundation
#if canImport(Darwin)
import Observation
#endif

/// What an import did: how many arrived, what did not, and the refusal that stopped it.
struct CloudImportSummary: Equatable, Sendable {
    var imported = 0
    var failures: [String] = []
    /// A plan refusal (402/413) ends the run: every later file would be refused the same way.
    var refusal: Refusal?

    /// The web's toast, once anything arrived.
    var toast: String? {
        guard imported > 0 else { return nil }
        let noun = imported == 1 ? "file" : "files"
        return "Imported \(imported) \(noun) — making them searchable now"
    }

    /// The first thing that went wrong, as the web shows only the first.
    var firstFailure: String? { failures.first }
}

/// My Files → Add → From Google Drive / From OneDrive: the drive's files, picked and copied in.
///
/// Rules and words follow the web's import dialog (`src/pages/MyFilesPage.jsx`): which drive is
/// shown first, the folder they go into (the top level is `"."`), one file at a time. Unlike the
/// web, a plan refusal stops the run. See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class CloudImportModel {

    private let service: CloudDriveProviding

    private(set) var connections: [CloudProvider: CloudConnection] = [:]
    private(set) var provider: CloudProvider = .google
    private(set) var state: LoadState = .idle
    private(set) var files: [CloudFile] = []
    /// Why nothing can be listed — no drive on this server, or this one not connected. Shown with
    /// the way to Connected services rather than a retry.
    private(set) var blocker: String?
    private(set) var isImporting = false
    var selection: Set<String> = []
    /// The folder the files go into; `nil` for the top level.
    var destination: String?
    var query = ""

    init(service: CloudDriveProviding, destination: String? = nil) {
        self.service = service
        self.destination = (destination?.isEmpty ?? true) ? nil : destination
    }

    // MARK: - Derived

    var title: String { "Import from \(provider.label)" }

    var connectedProviders: [CloudProvider] {
        CloudProvider.allCases.filter { connections[$0]?.isConnected == true }
    }

    /// A choice of drive only when both are connected.
    var showsProviderPicker: Bool { connectedProviders.count > 1 }

    var visibleFiles: [CloudFile] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return files }
        return files.filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    var canImport: Bool { !selection.isEmpty && !isImporting }

    var importTitle: String { selection.isEmpty ? "Import" : "Import \(selection.count)" }

    /// The web's pick: Google Drive when connected, else OneDrive when connected, else Google Drive.
    nonisolated static func defaultProvider(_ connections: [CloudProvider: CloudConnection]) -> CloudProvider {
        if connections[.google]?.isConnected == true { return .google }
        if connections[.microsoft]?.isConnected == true { return .microsoft }
        return .google
    }

    // MARK: - Intents

    func load() async {
        state = .loading
        blocker = nil
        files = []
        selection = []
        do {
            connections = try await service.connections()
        } catch {
            state = .failed(LoadFailure(error))
            return
        }
        let anyConfigured = CloudProvider.allCases.contains { connections[$0]?.isConfigured == true }
        guard anyConfigured else {
            blocker = CloudCopy.soon
            state = .loaded
            return
        }
        provider = Self.defaultProvider(connections)
        await list()
    }

    func choose(_ provider: CloudProvider) async {
        guard provider != self.provider else { return }
        self.provider = provider
        selection = []
        await list()
    }

    func toggle(_ file: CloudFile) {
        if selection.contains(file.id) {
            selection.remove(file.id)
        } else {
            selection.insert(file.id)
        }
    }

    func list() async {
        state = .loading
        blocker = nil
        files = []
        guard connections[provider]?.isConnected == true else {
            blocker = CloudCopy.notConnectedMessage(provider)
            state = .loaded
            return
        }
        do {
            files = try await service.list(provider)
            state = .loaded
        } catch {
            if case .server(let status, let message)? = error as? APIError, status == 409 {
                // Not connected, expired, or access not granted: the sentence says what to do.
                blocker = message
                state = .loaded
            } else {
                state = .failed(LoadFailure(error))
            }
        }
    }

    /// Imports the chosen files one after another, in the order listed.
    func run() async -> CloudImportSummary {
        var summary = CloudImportSummary()
        guard canImport else { return summary }
        isImporting = true
        defer { isImporting = false }
        let chosen = files.filter { selection.contains($0.id) }
        for file in chosen {
            do {
                _ = try await service.importFile(provider, file: file, into: destination)
                summary.imported += 1
                selection.remove(file.id)
            } catch {
                let message = DisplayText.message(for: error)
                if let refusal = (error as? APIError)?.refusal {
                    summary.failures.append(message)
                    summary.refusal = refusal
                    break
                }
                summary.failures.append("\(file.name): \(message)")
            }
        }
        return summary
    }
}
