import Foundation
#if canImport(Darwin)
import Observation
#endif

/// A finished run on screen: what it produced, what it read, and where it came from.
struct AnalysisOutcome: Equatable, Sendable {
    var result: AnalysisResult
    var fileNames: [String]
    var reference: String
    var madeOn: Date
    /// The stored run it was opened from, or `nil` for a run just made.
    var fromHistory: AnalysisRunSummary?
}

/// Why a run did not finish, and what may be offered about it.
struct AnalysisFailure: Equatable, Sendable {
    var message: String
    /// The plan or the account said no. Shown as a refusal, never with "Try again".
    var refusal: Refusal?
    var canRetry: Bool
    /// The stored run that could not be read, when it was one — "Try again" opens it again.
    var fromHistory: AnalysisRunSummary?

    init(message: String, refusal: Refusal? = nil, fromHistory: AnalysisRunSummary? = nil) {
        self.message = message
        self.refusal = refusal
        self.canRetry = refusal?.concernsThePlan != true
        self.fromHistory = fromHistory
    }
}

/// One analysis tool's screen: the documents and note, the run itself, and what it produced
/// (`useAnalysis.js`, `src/lib/analysisApi.js` and the three pages' flow).
///
/// A run is started, then its job polled every two seconds until it is done or fails. Cancel stops
/// the polling only: the server finishes the job regardless, and it appears in History. A run that
/// takes over 25 minutes is given up on here, as on the web.
///
/// See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class AnalysisRunModel {

    enum Phase: Equatable, Sendable {
        case intake
        case running(stage: String, progress: Double, startedAt: Date)
        case done(AnalysisOutcome)
        case failed(AnalysisFailure)
    }

    static let firstStage = "Getting your documents ready…"
    static let tooLong = "This is taking too long. Try fewer or shorter documents."
    static let jobFailed = "The analysis failed. Try again."

    let kind: AnalysisToolKind
    let history: AnalysisHistoryModel
    private(set) var files: [ChatAttachment] = []
    /// Picked documents that cannot be used, with the reason for each.
    private(set) var refusedFiles: [AnalysisInput.Refused] = []
    var reference = ""
    private(set) var phase: Phase = .intake

    private let service: any AnalysisProviding
    private let pollInterval: Duration
    private let maxWait: TimeInterval
    private let now: () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private let makeChatID: () -> String
    private var pollTask: Task<Void, Never>?
    /// Bumped by every start, cancel and reset: only the current run may write the phase.
    private var token = 0

    init(
        kind: AnalysisToolKind,
        service: any AnalysisProviding,
        history: AnalysisHistoryModel,
        pollInterval: Duration = .seconds(2),
        maxWait: TimeInterval = 1500,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        makeChatID: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.kind = kind
        self.service = service
        self.history = history
        self.pollInterval = pollInterval
        self.maxWait = maxWait
        self.now = now
        self.sleep = sleep
        self.makeChatID = makeChatID
    }

    // MARK: - Intake

    /// What came back from the My Files picker: the usable documents, and the rest with reasons.
    func setFiles(_ picked: [ChatAttachment]) {
        let (accepted, refused) = AnalysisInput.usable(picked)
        files = accepted
        refusedFiles = refused
    }

    func remove(_ file: ChatAttachment) {
        files.removeAll { $0 == file }
    }

    /// The result on screen, when there is one.
    var outcome: AnalysisOutcome? {
        if case .done(let outcome) = phase { return outcome }
        return nil
    }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    var canRun: Bool {
        !files.isEmpty && !isRunning && !AnalysisInput.isReferenceTooLong(reference)
    }

    /// The line beside the button.
    var ctaNote: String {
        if AnalysisInput.isReferenceTooLong(reference) { return "The note is too long (2,000 characters at most)" }
        return files.isEmpty ? AnalysisToolKind.chooseFirstNote : kind.ctaNote
    }

    // MARK: - Running

    /// Starts a run on the chosen documents, and polls it until it ends. The returned task is
    /// the polling, for a caller that wants to wait on it.
    @discardableResult
    func run() -> Task<Void, Never>? {
        guard !files.isEmpty else { return nil }
        pollTask?.cancel()
        token += 1
        let mine = token
        let startedAt = now()
        let files = self.files
        let reference = self.reference
        phase = .running(stage: Self.firstStage, progress: 0, startedAt: startedAt)
        let chatID = makeChatID()
        let task = Task { [weak self] () -> Void in
            guard let self else { return }
            await self.execute(token: mine, files: files, reference: reference, chatID: chatID, startedAt: startedAt)
        }
        pollTask = task
        return task
    }

    private func execute(token mine: Int, files: [ChatAttachment], reference: String, chatID: String, startedAt: Date) async {
        do {
            let jobID = try await service.start(kind, files: files, reference: reference, chatID: chatID)
            while true {
                guard mine == token, !Task.isCancelled else { return }
                let job = try await service.job(id: jobID)
                guard mine == token, !Task.isCancelled else { return }
                switch job.phase {
                case .done:
                    await finish(job, files: files, reference: reference)
                    return
                case .failed:
                    let message = job.error.flatMap { $0.isEmpty ? nil : $0 } ?? Self.jobFailed
                    phase = .failed(AnalysisFailure(message: message))
                    return
                case .running:
                    if case .running(let stage, let progress, _) = phase {
                        phase = .running(
                            stage: job.stage.flatMap { $0.isEmpty ? nil : $0 } ?? stage,
                            progress: job.progress ?? progress, startedAt: startedAt)
                    }
                    if now().timeIntervalSince(startedAt) > maxWait {
                        phase = .failed(AnalysisFailure(message: Self.tooLong))
                        return
                    }
                    try await sleep(pollInterval)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard mine == token, !Task.isCancelled else { return }
            phase = .failed(AnalysisFailure(message: DisplayText.message(for: error), refusal: (error as? APIError)?.refusal))
        }
    }

    private func finish(_ job: AnalysisJob, files: [ChatAttachment], reference: String) async {
        if let result = AnalysisResult.normalise(job.result, as: kind) {
            phase = .done(AnalysisOutcome(
                result: result, fileNames: files.map(\.name), reference: reference, madeOn: now(), fromHistory: nil))
        } else {
            phase = .failed(AnalysisFailure(message: kind.unreadableMessage))
        }
        if job.runId != nil { await history.refresh(silent: true) }
    }

    /// Stops following the run and goes back to the intake, documents kept. The server still
    /// finishes and saves it.
    func cancel() {
        pollTask?.cancel()
        pollTask = nil
        token += 1
        phase = .intake
    }

    /// Back to the intake with the same documents — "Run again".
    func backToIntake() { cancel() }

    /// Back to an empty intake — "Start over", "Run again with new documents".
    func startOver() {
        cancel()
        files = []
        refusedFiles = []
        reference = ""
    }

    /// "Try again": the same run again, or the same stored run opened again.
    func retry() async {
        if case .failed(let failure) = phase, let stored = failure.fromHistory {
            if let run = await history.open(stored.id) { show(run: run) }
            return
        }
        run()
    }

    // MARK: - History

    /// Shows a stored run in place of whatever was on screen.
    func show(run: AnalysisRun) {
        pollTask?.cancel()
        pollTask = nil
        token += 1
        if let result = AnalysisResult.normalise(run.result, as: kind) {
            phase = .done(AnalysisOutcome(
                result: result, fileNames: run.fileNames, reference: run.reference,
                madeOn: run.createdDate ?? now(), fromHistory: run.summary))
        } else {
            phase = .failed(AnalysisFailure(message: kind.unreadableSavedMessage, fromHistory: run.summary))
        }
    }

    // MARK: - Words

    /// The failure panel's sentence: the reason, and for the report the reassurance after it.
    var failureMessage: String? {
        guard case .failed(let failure) = phase else { return nil }
        guard failure.refusal == nil, let tail = kind.failureReassurance else { return failure.message }
        return failure.message + tail
    }

    /// The running clock, "1:05".
    nonisolated static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let rest = s % 60
        return "\(s / 60):\(rest < 10 ? "0" : "")\(rest)"
    }
}
