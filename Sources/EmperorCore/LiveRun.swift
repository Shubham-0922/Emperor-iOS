import Foundation

/// Following a run that this screen did not start.
///
/// A chat run goes on after the app that began it has gone — backgrounded, relaunched, or the
/// conversation opened from History or another device. Such a screen has no stream of its own, so
/// it asks `/stream-status` and decides what to show: follow the run, offer Retry, or nothing.
/// These are the rules for that decision, kept pure so they can be tested without a server. They
/// mirror the web client's own (`src/lib/liveRun.js`), and `LiveRunTests` holds them to it.
///
/// Branch on `running`; `active` is the older, laxer signal that also honours a stored typing flag.
enum LiveRun {
    /// First wait between two reads of the status, and the longest it ever grows to.
    static let pollMinMs = 2000
    static let pollMaxMs = 10000
    /// How long a followed run is watched before giving up: the server's own ceiling on a run
    /// (30 minutes) plus slack.
    static let watchMaxMs = 35 * 60 * 1000
    /// Consecutive unreadable status answers (offline, server restarting) before giving up.
    static let maxPollFailures = 8

    /// What a screen that has just opened a chat should do.
    enum Decision: String, Equatable, Sendable {
        /// A run is live: show it and wait for its answer.
        case follow
        /// No run is live, but the chat ends on an unanswered question or on an unfinished
        /// checkpoint: say so and offer Retry.
        case failed
        /// Nothing to do, or the server could not be asked. A failure is never guessed.
        case idle
    }

    /// How a followed run ended, judged from the chat as the server saved it.
    enum Outcome: Equatable, Sendable {
        case finished
        /// The server marked the answer interrupted; the text says so itself.
        case incomplete
        /// The user stopped it, here or elsewhere. Needs no Retry.
        case stopped
        /// The run ended and nothing was saved after the question.
        case noAnswer
    }

    /// The server's recent statuses drawn as a work log: one group of real tool calls.
    struct LogGroup: Equatable, Sendable {
        struct Step: Equatable, Sendable {
            var label: String
            var completed: Bool
        }
        var steps: [Step]
    }

    /// A work-log step is a real tool call, not any status line.
    private static let stepRegex = try! NSRegularExpression(
        pattern: "^(?:Reading (?:page|pages) \\d|Mapping the structure of |Searching the record(?: for:)?)",
        options: [.caseInsensitive])

    private static let interruptedRegex = try! NSRegularExpression(
        pattern: "This response was interrupted and is incomplete|No response was produced")

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(
            in: text, options: [],
            range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    /// Whether the run the server reports is still going. `running` wins; an older server only
    /// sends `active`.
    static func isRunLive(_ status: StreamStatus?) -> Bool {
        guard let status, status.error == nil else { return false }
        if let running = status.running { return running }
        return status.active
    }

    static func followDecision(messages: [ChatMessage], status: StreamStatus?) -> Decision {
        // "No messages" only means no assistant row exists yet — exactly a first turn that died.
        // Any other error means the server could not say, so nothing is guessed.
        guard let status else { return .idle }
        if let error = status.error, error != "No messages" { return .idle }
        if isRunLive(status) { return .follow }
        guard let last = messages.last else { return .idle }
        if last.role == .user { return .failed }
        // A checkpoint still flagged as typing although no run holds the chat: the run died
        // without finishing. Only trusted from a server that reports `running`.
        if last.role == .assistant, last.isTyping == true, status.running == false { return .failed }
        return .idle
    }

    /// Next wait: back to the minimum whenever something changed, otherwise ×1.5 up to the cap.
    static func nextPollDelay(previousMs: Int?, changed: Bool) -> Int {
        guard !changed, let previousMs, previousMs != 0 else { return pollMinMs }
        return min(pollMaxMs, Int((Double(previousMs) * 1.5).rounded(.toNearestOrAwayFromZero)))
    }

    /// "45s", "3m 12s", "1h 02m".
    static func formatElapsed(_ ms: Double) -> String {
        let seconds = ms.isFinite ? max(0, Int((ms / 1000).rounded(.down))) : 0
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m \(twoDigits(seconds % 60))s" }
        return "\(minutes / 60)h \(twoDigits(minutes % 60))m"
    }

    private static func twoDigits(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    /// The one-line status for a followed run. `friendly` is the caller's wording of the
    /// server's newest status line, if it has one.
    static func liveStatusText(_ status: StreamStatus?, friendly: String = "", now: Date = Date()) -> String {
        let phase = status?.phase ?? ""
        let base: String
        if status?.writing == true || phase == "compose" {
            base = "Writing your draft…"
        } else if phase == "wrapup" {
            base = "Pulling the research together…"
        } else if !friendly.isEmpty {
            base = friendly
        } else {
            base = "Working on your request…"
        }
        let elapsed: Double?
        if let ms = status?.elapsedMs {
            elapsed = ms
        } else if let started = status?.startedAt, started != 0 {
            elapsed = now.timeIntervalSince1970 * 1000 - started
        } else {
            elapsed = nil
        }
        guard let elapsed else { return base }
        return "\(base) · \(formatElapsed(elapsed))"
    }

    /// The server's recent statuses as one group of the real tool calls, all done except the
    /// newest, which is still running. Empty when none of them is a tool call.
    static func logFromStatusLines(_ lines: [String]?) -> [LogGroup] {
        let steps = (lines ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { matches(stepRegex, $0) }
        guard !steps.isEmpty else { return [] }
        return [LogGroup(steps: steps.enumerated().map { index, label in
            LogGroup.Step(label: label, completed: index != steps.count - 1)
        })]
    }

    /// Which live text, if any, to show from a status answer. Until the run has written a
    /// visible character, the newest saved answer is the **previous turn's** and must not be
    /// shown as if it were being written. A server that says `fromLiveRun` is believed; an
    /// older one falls back to "not an answer already on screen".
    static func liveContent(_ status: StreamStatus?, knownAnswers: Set<String>? = nil) -> String {
        let content = status?.content ?? ""
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let fromLive = status?.fromLiveRun { return fromLive ? content : "" }
        return knownAnswers?.contains(trimmed) == true ? "" : content
    }

    /// How a followed run ended, from the chat as the server saved it.
    static func runOutcome(_ saved: [ChatMessage]) -> Outcome {
        guard let last = saved.last, last.role == .assistant,
              !last.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .noAnswer }
        // Stopped on purpose, here or elsewhere: it says so itself.
        if last.extra["stoppedBy"]?.stringValue == "user" { return .stopped }
        if last.incomplete == true || matches(interruptedRegex, last.content) { return .incomplete }
        return .finished
    }

    /// The sentence shown with Retry when a run could not be followed to an answer.
    static func failureText(_ reason: String?) -> String {
        switch reason {
        case "lost":
            return "Lost touch with the server while your request was running. It may still finish — reload in a minute, or retry now."
        case "timeout":
            return "This request ran past the time limit without an answer."
        default:
            return "This request stopped before an answer was saved."
        }
    }
}
