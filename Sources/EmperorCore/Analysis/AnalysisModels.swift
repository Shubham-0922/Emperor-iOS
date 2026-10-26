import Foundation

/// What a model run cost, as the job and the history report it. Shown nowhere yet; decoded so a
/// change in its shape cannot fail the rest of the answer.
struct AnalysisUsage: Decodable, Equatable, Sendable {
    var model: String?
    var inputTokens: Int?
    var outputTokens: Int?
    var costUsd: Double?

    enum CodingKeys: String, CodingKey {
        case model, inputTokens, outputTokens, costUsd
    }

    init(model: String? = nil, inputTokens: Int? = nil, outputTokens: Int? = nil, costUsd: Double? = nil) {
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUsd = costUsd
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try? c.decodeIfPresent(String.self, forKey: .model)
        inputTokens = (try? c.decodeIfPresent(Double.self, forKey: .inputTokens)).flatMap { $0.map { Int($0) } }
        outputTokens = (try? c.decodeIfPresent(Double.self, forKey: .outputTokens)).flatMap { $0.map { Int($0) } }
        costUsd = try? c.decodeIfPresent(Double.self, forKey: .costUsd)
    }
}

/// `POST /analysis/start`'s answer: `202 {success, jobId}`.
struct AnalysisStartReply: Decodable, Sendable {
    var success: Bool?
    var jobId: String?
    var error: String?

    enum CodingKeys: String, CodingKey { case success, jobId, error }
}

/// One poll of `GET /analysis/job`. A failed job is an HTTP 200 with `status: "error"`, so this
/// is read for its status, never for its status code.
struct AnalysisJob: Decodable, Equatable, Sendable {
    enum Phase: Equatable, Sendable { case running, done, failed }

    var success: Bool?
    var status: String
    var stage: String?
    var progress: Double?
    var result: JSONValue?
    var runId: String?
    var error: String?
    var usage: AnalysisUsage?

    enum CodingKeys: String, CodingKey {
        case success, status, stage, progress, result, runId, error, usage
    }

    init(
        status: String, stage: String? = nil, progress: Double? = nil, result: JSONValue? = nil,
        runId: String? = nil, error: String? = nil, usage: AnalysisUsage? = nil
    ) {
        self.success = true
        self.status = status
        self.stage = stage
        self.progress = progress
        self.result = result
        self.runId = runId
        self.error = error
        self.usage = usage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try? c.decodeIfPresent(Bool.self, forKey: .success)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? ""
        stage = try? c.decodeIfPresent(String.self, forKey: .stage)
        progress = try? c.decodeIfPresent(Double.self, forKey: .progress)
        result = try? c.decodeIfPresent(JSONValue.self, forKey: .result)
        if result == .null { result = nil }
        runId = try? c.decodeIfPresent(String.self, forKey: .runId)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
        usage = try? c.decodeIfPresent(AnalysisUsage.self, forKey: .usage)
    }

    /// `reading`, `thinking` and `writing` — and any status this client does not know — are a
    /// job still going.
    var phase: Phase {
        switch status {
        case "done": return .done
        case "error": return .failed
        default: return .running
        }
    }
}

/// A past run in History, without its result.
struct AnalysisRunSummary: Decodable, Equatable, Sendable, Identifiable {
    var id: String
    var tool: String?
    var title: String?
    /// ISO-8601 with milliseconds.
    var createdAt: String?
    var fileNames: [String]?
    var reference: String?
    var usage: AnalysisUsage?

    enum CodingKeys: String, CodingKey {
        case id, tool, title, createdAt, fileNames, reference, usage
    }

    init(
        id: String, tool: String? = nil, title: String? = nil, createdAt: String? = nil,
        fileNames: [String]? = nil, reference: String? = nil, usage: AnalysisUsage? = nil
    ) {
        self.id = id
        self.tool = tool
        self.title = title
        self.createdAt = createdAt
        self.fileNames = fileNames
        self.reference = reference
        self.usage = usage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? c.decode(String.self, forKey: .id) {
            id = text
        } else if let number = try? c.decode(Double.self, forKey: .id) {
            id = AnalysisJS.string(number)
        } else {
            id = ""
        }
        tool = try? c.decodeIfPresent(String.self, forKey: .tool)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        fileNames = (try? c.decodeIfPresent([JSONValue].self, forKey: .fileNames))
            .flatMap { $0?.compactMap(\.stringValue) }
        reference = try? c.decodeIfPresent(String.self, forKey: .reference)
        usage = try? c.decodeIfPresent(AnalysisUsage.self, forKey: .usage)
    }

    var createdDate: Date? { WireDate.parse(createdAt) }

    /// The row's name: the run's title, else its first document, else "Untitled run".
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let first = fileNames?.first, !first.isEmpty { return first }
        return "Untitled run"
    }
}

/// A stored run with its result, from `GET /analysis/run`.
struct AnalysisRun: Decodable, Equatable, Sendable {
    var summary: AnalysisRunSummary
    var result: JSONValue?

    enum CodingKeys: String, CodingKey { case result }

    init(summary: AnalysisRunSummary, result: JSONValue?) {
        self.summary = summary
        self.result = result
    }

    init(from decoder: Decoder) throws {
        summary = try AnalysisRunSummary(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        result = try? c.decodeIfPresent(JSONValue.self, forKey: .result)
        if result == .null { result = nil }
    }

    var id: String { summary.id }
    var fileNames: [String] { summary.fileNames ?? [] }
    var reference: String { summary.reference ?? "" }
    var createdDate: Date? { summary.createdDate }
}

struct AnalysisHistoryReply: Decodable, Sendable {
    var success: Bool?
    var runs: [AnalysisRunSummary]?
    var error: String?

    enum CodingKeys: String, CodingKey { case success, runs, error }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try? c.decodeIfPresent(Bool.self, forKey: .success)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
        // One malformed run must not hide the others.
        let items = (try? c.decodeIfPresent([JSONValue].self, forKey: .runs)) ?? nil
        runs = items.map { list in
            list.compactMap { item in
                guard case .object = item, let data = try? JSONEncoder().encode(item) else { return nil }
                return try? JSONDecoder().decode(AnalysisRunSummary.self, from: data)
            }
        }
    }
}

struct AnalysisRunReply: Decodable, Sendable {
    var success: Bool?
    var run: AnalysisRun?
    var error: String?

    enum CodingKeys: String, CodingKey { case success, run, error }
}

/// A plain `{success, error}` answer.
struct AnalysisAck: Decodable, Sendable {
    var success: Bool?
    var error: String?

    enum CodingKeys: String, CodingKey { case success, error }
}

/// What a finished run produced, drawn by its own tool's view.
enum AnalysisResult: Equatable, Sendable {
    case devilsAdvocate(DevilsAdvocateReport)
    case docIndex(DocIndex)
    case listOfDates(DateChart)

    /// The tool's own normaliser over a raw result, or `nil` when it cannot be drawn.
    static func normalise(_ raw: JSONValue?, as kind: AnalysisToolKind) -> AnalysisResult? {
        switch kind {
        case .devilsAdvocate: return DevilsAdvocateReport.normalise(raw).map(AnalysisResult.devilsAdvocate)
        case .docIndex: return DocIndex.normalise(raw).map(AnalysisResult.docIndex)
        case .listOfDates:
            // The web draws any answer here, an unusable one as "no dates were found".
            return .listOfDates(DateChart.normalise(raw))
        }
    }
}
