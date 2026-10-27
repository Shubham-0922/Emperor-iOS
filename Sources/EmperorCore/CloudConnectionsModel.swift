import Foundation
#if canImport(Darwin)
import Observation
#endif

/// Account → Connected services: each drive's state, connecting one in Safari, disconnecting.
///
/// The provider's sign-in ends on the web app, not in this app, so the phone cannot be told when
/// it is done. Instead, while the sign-in page is up, the connections are read again every two
/// seconds; once the provider reads as connected, the page is closed. Done on the page reads them
/// once more. See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class CloudConnectionsModel {

    /// Milliseconds between two reads while the sign-in page is up.
    static let pollInterval = 2_000
    /// How long a sign-in page is waited on before the reads stop.
    static let pollLimit: TimeInterval = 600

    private let service: CloudDriveProviding
    private let timing: FollowTiming

    private(set) var state: LoadState = .idle
    private(set) var connections: [CloudProvider: CloudConnection] = [:]
    /// The provider a connect or disconnect is under way for.
    private(set) var busy: CloudProvider?
    /// The sign-in page on screen, if any. Cleared by the screen when the page is closed.
    var pendingURL: IdentifiedURL?
    /// A confirmation for a toast — "Google Drive connected".
    var notice: String?
    /// Why the last action did not work, for an alert.
    var error: String?
    /// Said under the rows after the sign-in page closed without connecting.
    private(set) var hint: String?

    init(service: CloudDriveProviding, timing: FollowTiming = .live) {
        self.service = service
        self.timing = timing
    }

    // MARK: - Derived

    var anyConfigured: Bool { CloudProvider.allCases.contains { connection($0).isConfigured } }

    var connectedProviders: [CloudProvider] {
        CloudProvider.allCases.filter { connection($0).isConnected }
    }

    func connection(_ provider: CloudProvider) -> CloudConnection {
        connections[provider] ?? CloudConnection()
    }

    func description(of provider: CloudProvider) -> String {
        Self.description(for: connection(provider), label: provider.label)
    }

    /// The web card's line under each drive (`src/pages/Settings.jsx`).
    nonisolated static func description(for connection: CloudConnection, label: String) -> String {
        if !connection.isConfigured { return CloudCopy.notConfigured }
        if connection.isConnected {
            if let email = connection.email, !email.isEmpty { return "Connected as \(email)" }
            return "Connected"
        }
        return CloudCopy.notConnected
    }

    // MARK: - Intents

    func load() async {
        if connections.isEmpty { state = .loading }
        do {
            connections = try await service.connections()
            state = .loaded
        } catch {
            if connections.isEmpty { state = .failed(LoadFailure(error)) }
        }
    }

    /// Asks for the sign-in page; the screen presents it once `pendingURL` is set.
    func connect(_ provider: CloudProvider) async {
        guard busy == nil else { return }
        busy = provider
        hint = nil
        defer { busy = nil }
        do {
            let url = try await service.connectURL(provider)
            pendingURL = IdentifiedURL(provider: provider, url: url)
        } catch {
            self.error = DisplayText.message(for: error)
        }
    }

    /// Reads the connections every two seconds while `provider`'s sign-in page is up, and closes
    /// the page once it reads as connected. Stops after ten minutes, or when the page goes.
    func pollWhileConnecting(_ provider: CloudProvider) async {
        let start = timing.now()
        while pendingURL?.provider == provider {
            if timing.now().timeIntervalSince(start) >= Self.pollLimit { return }
            await timing.sleep(Self.pollInterval)
            if Task.isCancelled { return }
            guard pendingURL?.provider == provider else { return }
            guard let read = try? await service.connections() else { continue }
            connections = read
            state = .loaded
            if read[provider]?.isConnected == true {
                pendingURL = nil
                hint = nil
                notice = "\(provider.label) connected"
                return
            }
        }
    }

    /// The sign-in page closed — by Done, or by the poll. One more read says where things stand.
    func browserClosed(_ provider: CloudProvider) async {
        pendingURL = nil
        let wasConnected = connection(provider).isConnected
        await load()
        let isConnected = connection(provider).isConnected
        if isConnected {
            hint = nil
            if !wasConnected { notice = "\(provider.label) connected" }
        } else {
            hint = CloudCopy.notConnectedYet
        }
    }

    func disconnect(_ provider: CloudProvider) async {
        guard busy == nil else { return }
        busy = provider
        hint = nil
        defer { busy = nil }
        do {
            try await service.disconnect(provider)
            notice = "\(provider.label) disconnected"
        } catch {
            self.error = DisplayText.message(for: error)
        }
        await load()
    }
}
