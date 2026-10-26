import Foundation
#if canImport(Darwin)
import Observation
#endif

/// The past runs of one analysis tool (`useAnalysisHistory.js`): the list, a search over it, and
/// opening or deleting one run.
///
/// See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class AnalysisHistoryModel {

    enum Status: Equatable, Sendable {
        case loading
        case ready
        case failed(String)
    }

    /// The list offers a search once it is longer than this.
    static let searchFrom = 8

    let kind: AnalysisToolKind
    private(set) var runs: [AnalysisRunSummary] = []
    private(set) var status: Status = .loading
    var query = ""
    /// The run being opened, while it is.
    private(set) var opening: String?
    /// Why the last open or delete failed.
    private(set) var openError: String?

    private let service: any AnalysisProviding
    /// Bumped by every list request: only the latest may write the list.
    private var ticket = 0

    init(kind: AnalysisToolKind, service: any AnalysisProviding) {
        self.kind = kind
        self.service = service
    }

    var offersSearch: Bool { runs.count > Self.searchFrom }

    /// The runs whose title or documents hold the search.
    var filtered: [AnalysisRunSummary] {
        let q = AnalysisJS.trim(query).lowercased()
        guard !q.isEmpty else { return runs }
        return runs.filter { run in
            "\(run.displayTitle) \((run.fileNames ?? []).joined(separator: " "))".lowercased().contains(q)
        }
    }

    /// "History, 3 past runs" for the bar button; plain "History" until there are any.
    var buttonLabel: String {
        guard status == .ready, !runs.isEmpty else { return "History" }
        return "History, \(runs.count) past \(runs.count == 1 ? "run" : "runs")"
    }

    /// The list again. A silent refresh leaves what is on screen while it asks, and keeps it if
    /// the asking fails.
    func refresh(silent: Bool = false) async {
        ticket += 1
        let mine = ticket
        if !silent { status = .loading }
        do {
            let list = try await service.history(kind)
            guard mine == ticket else { return }
            runs = list
            status = .ready
        } catch {
            guard mine == ticket else { return }
            if silent, status == .ready { return }
            status = .failed(DisplayText.message(for: error))
        }
    }

    /// One stored run with its result, or `nil` — with `openError` saying why — when it could not
    /// be fetched.
    func open(_ id: String) async -> AnalysisRun? {
        opening = id
        openError = nil
        defer { if opening == id { opening = nil } }
        do {
            return try await service.run(id: id)
        } catch {
            openError = DisplayText.message(for: error)
            return nil
        }
    }

    /// Deletes a run and takes it off the list; `false`, with `openError` set, when it failed.
    @discardableResult
    func remove(_ id: String) async -> Bool {
        do {
            try await service.deleteRun(id: id)
            runs.removeAll { $0.id == id }
            openError = nil
            return true
        } catch {
            openError = DisplayText.message(for: error)
            return false
        }
    }

    func clearOpenError() { openError = nil }
}
