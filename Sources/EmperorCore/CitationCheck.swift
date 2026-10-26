import Foundation
#if canImport(Darwin)
import Observation
#endif

/// What became of checking one cited document against its source (the web's `CitationMeta`,
/// `src/tools/ReadingCard.jsx`).
enum CitationOutcome: Equatable, Sendable {
    /// The quoted words are on a page of the document.
    case verified
    /// The document is there, but the quote is too short for the server to judge.
    case unchecked
    /// The server looked and did not find the words.
    case unverified
    /// No such document among the reader's — or this matter's — documents.
    case missing
    /// The check itself could not be run.
    case unknown

    /// The web's classification of a `/resolve-file` answer for a reference quoting `quote`.
    static func classify(_ resolved: ResolvedFile, quote: String) -> CitationOutcome {
        guard resolved.found else { return .missing }
        // Under 12 characters the server will not judge a quote; decided here as well, so a server
        // that does not say so never has a short quote read as missing.
        if quote.isEmpty || CitedSource.jsTrim(quote).utf16.count < 12 || resolved.quoteStatus == .tooShort {
            return .unchecked
        }
        return (resolved.page ?? 0) != 0 ? .verified : .unverified
    }
}

/// The checks already asked for, shared by every answer on screen: an answer redrawn, or the same
/// document cited in two answers, asks the server once.
///
/// A check that could not be run is let go once it finishes, so the next look asks again — a
/// phone loses its connection far more often than a browser.
final class CitationCheckCache: @unchecked Sendable {
    static let shared = CitationCheckCache()

    private let lock = NSLock()
    private var tasks: [String: Task<CitationOutcome, Never>] = [:]

    init() {}

    func outcome(
        for key: String, _ run: @escaping @Sendable () async -> CitationOutcome
    ) async -> CitationOutcome {
        let task: Task<CitationOutcome, Never> = lock.withLock {
            if let existing = tasks[key] { return existing }
            let created = Task { await run() }
            tasks[key] = created
            return created
        }
        let outcome = await task.value
        if outcome == .unknown {
            lock.withLock { if tasks[key] == task { tasks[key] = nil } }
        }
        return outcome
    }

    /// Forgets every check — on signing out, so another account never reads this one's.
    func clear() {
        lock.withLock { tasks = [:] }
    }
}

/// The line under a finished answer that says whether its cited documents hold what it quotes:
/// "2 citations · checked against source". One per answer.
///
/// See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class CitationCheck {
    enum Tone: Equatable, Sendable { case ok, warn, plain }

    enum State: Equatable, Sendable {
        case checking
        case done(label: String, tone: Tone)
    }

    private(set) var state: State = .checking

    /// The answer's document references, one per reference line.
    let documents: [DocumentReference]

    private let resolver: (any CitedSourceResolving)?
    private let projectID: String?
    private let account: String
    private let cache: CitationCheckCache

    /// - Parameters:
    ///   - content: the answer's text.
    ///   - projectID: the matter the conversation belongs to, if any — its documents are looked
    ///     for there.
    ///   - account: whose documents these are, so one account's checks are never another's.
    init(
        content: String, resolver: (any CitedSourceResolving)?, projectID: String?,
        account: String = "", cache: CitationCheckCache = .shared
    ) {
        documents = CitedSource.citedDocs(content).map(\.ref)
        self.resolver = resolver
        self.projectID = projectID
        self.account = account
        self.cache = cache
    }

    /// Whether there is anything to say: an answer citing none of the reader's documents shows
    /// no line.
    var isVisible: Bool { !documents.isEmpty }

    private var countLabel: String {
        "\(documents.count) citation\(documents.count == 1 ? "" : "s")"
    }

    var label: String {
        switch state {
        case .checking: return "\(countLabel) · checking against source…"
        case .done(let label, _): return label
        }
    }

    var tone: Tone {
        if case .done(_, let tone) = state { return tone }
        return .plain
    }

    func run() async {
        guard isVisible else { return }
        guard let resolver else {
            state = .done(label: countLabel, tone: .plain)
            return
        }
        let projectID = self.projectID
        let account = self.account
        let cache = self.cache
        let documents = self.documents
        // All at once, as the web asks them, and read back in the answer's order.
        let outcomes = await withTaskGroup(of: (Int, CitationOutcome).self) { group in
            for (index, ref) in documents.enumerated() {
                group.addTask {
                    let key = "\(account)|\(projectID ?? "")|\(ref.file)|\(ref.quote)"
                    let outcome = await cache.outcome(for: key) {
                        do {
                            let resolved = try await resolver.resolve(
                                name: ref.file, quote: ref.quote.isEmpty ? nil : ref.quote,
                                projectID: projectID)
                            return CitationOutcome.classify(resolved, quote: ref.quote)
                        } catch {
                            return .unknown
                        }
                    }
                    return (index, outcome)
                }
            }
            var ordered = [CitationOutcome](repeating: .unknown, count: documents.count)
            for await (index, outcome) in group { ordered[index] = outcome }
            return ordered
        }
        state = Self.summary(outcomes)
    }

    /// The web's wording for a set of outcomes.
    nonisolated static func summary(_ outcomes: [CitationOutcome]) -> State {
        let n = outcomes.count
        let label = "\(n) citation\(n == 1 ? "" : "s")"
        let bad = outcomes.filter { $0 == .missing || $0 == .unverified }.count
        let ok = outcomes.filter { $0 == .verified }.count
        if bad > 0 {
            let tail: String
            if bad == n {
                tail = n == 1 ? "not found in its source" : "none found in their sources"
            } else {
                tail = "\(bad) not found in \(bad == 1 ? "its source" : "their sources")"
            }
            return .done(label: "\(label) · \(tail)", tone: .warn)
        }
        if ok == n { return .done(label: "\(label) · checked against source", tone: .ok) }
        if ok > 0 { return .done(label: "\(label) · \(ok) checked against source", tone: .ok) }
        return .done(label: label, tone: .plain)
    }
}
