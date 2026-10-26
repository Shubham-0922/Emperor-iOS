import Foundation
@testable import EmperorCore

/// A scripted analysis server: the start answer, the job's polls in order, and the history.
final class FakeAnalysis: AnalysisProviding, @unchecked Sendable {
    private let lock = NSLock()

    var startError: Error?
    var jobID = "job-1"
    /// Each poll takes the next; the last is repeated once the script runs out.
    var polls: [Result<AnalysisJob, Error>] = []
    /// Each history call takes the next; the last is repeated.
    var histories: [Result<[AnalysisRunSummary], Error>] = [.success([])]
    /// Held until released, per history call index, so a test can make an older reply land last.
    var historyGates: [Int: AsyncStream<Void>] = [:]
    var runs: [String: AnalysisRun] = [:]
    var deleteError: Error?

    private var _starts: [(kind: AnalysisToolKind, files: [ChatAttachment], reference: String, chatID: String)] = []
    private var _pollCount = 0
    private var _historyCalls = 0
    private var _deleted: [String] = []

    var starts: [(kind: AnalysisToolKind, files: [ChatAttachment], reference: String, chatID: String)] { lock.withLock { _starts } }
    var pollCount: Int { lock.withLock { _pollCount } }
    var historyCalls: Int { lock.withLock { _historyCalls } }
    var deleted: [String] { lock.withLock { _deleted } }

    func start(_ kind: AnalysisToolKind, files: [ChatAttachment], reference: String, chatID: String) async throws -> String {
        lock.withLock { _starts.append((kind, files, reference, chatID)) }
        if let startError { throw startError }
        return jobID
    }

    func job(id: String) async throws -> AnalysisJob {
        let next: Result<AnalysisJob, Error>? = lock.withLock {
            defer { _pollCount += 1 }
            guard !polls.isEmpty else { return nil }
            return polls[min(_pollCount, polls.count - 1)]
        }
        guard let next else { throw APIError.server(status: 404, message: "no job") }
        return try next.get()
    }

    func history(_ kind: AnalysisToolKind) async throws -> [AnalysisRunSummary] {
        let (index, reply): (Int, Result<[AnalysisRunSummary], Error>) = lock.withLock {
            defer { _historyCalls += 1 }
            return (_historyCalls, histories[min(_historyCalls, histories.count - 1)])
        }
        if let gate = historyGates[index] { for await _ in gate { break } }
        return try reply.get()
    }

    func run(id: String) async throws -> AnalysisRun {
        guard let run = runs[id] else { throw APIError.server(status: 404, message: "No such saved analysis.") }
        return run
    }

    func deleteRun(id: String) async throws {
        if let deleteError { throw deleteError }
        lock.withLock { _deleted.append(id) }
    }
}

/// A clock that moves only when the model sleeps.
final class AnalysisClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    private var _sleeps: [Duration] = []

    var sleeps: [Duration] { lock.withLock { _sleeps } }

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }

    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] d in
            lock.withLock {
                _sleeps.append(d)
                current = current.addingTimeInterval(Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18)
            }
            try Task.checkCancellation()
            await Task.yield()
        }
    }
}
