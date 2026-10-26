import Foundation

/// The analysis jobs: start one, poll it, and the per-tool history of finished runs.
protocol AnalysisProviding: Sendable {
    /// Starts a job on documents in My Files and answers its id.
    func start(_ kind: AnalysisToolKind, files: [ChatAttachment], reference: String, chatID: String) async throws -> String
    func job(id: String) async throws -> AnalysisJob
    /// The tool's past runs, newest first, without their results.
    func history(_ kind: AnalysisToolKind) async throws -> [AnalysisRunSummary]
    func run(id: String) async throws -> AnalysisRun
    func deleteRun(id: String) async throws
}

/// `/analysis/start`, `/analysis/job`, `/analysis/history` and `/analysis/run`.
///
/// Every route needs the bearer token; `userId` travels too, in the body of the start and the
/// query of the rest, as on every other route. A job is the server's to finish: once started it
/// runs and is saved to History whether or not anyone is still polling.
struct AnalysisService: AnalysisProviding {
    let client: APIClient

    private struct StartFile: Encodable {
        let name: String
        let folderName: String
    }

    private struct StartBody: Encodable {
        let userId: String
        let tool: String
        let chatId: String
        let files: [StartFile]
        let reference: String
    }

    func start(_ kind: AnalysisToolKind, files: [ChatAttachment], reference: String, chatID: String) async throws -> String {
        guard let credentials = await client.currentCredentials() else { throw APIError.notAuthenticated }
        let body = StartBody(
            userId: credentials.userIDString, tool: kind.rawValue, chatId: String(chatID.prefix(100)),
            files: files.map { StartFile(name: $0.name, folderName: $0.folderName ?? "") },
            reference: reference)
        let request = try await client.makeRequest("POST", "/analysis/start", body: body)
        let reply: AnalysisStartReply
        do {
            reply = try await client.send(request, as: AnalysisStartReply.self)
        } catch APIError.server(402, let message) {
            // The month's allowance, refused with a code (`LIMIT`) this client has no case for:
            // the same refusal as a spent chat allowance, and worded as one.
            let refusal = Refusal(code: .queryLimit, status: 402, serverMessage: message)
            await client.noteRefusal(refusal)
            throw APIError.refused(refusal)
        }
        try Self.check(reply.success, reply.error, "The analysis could not be started. Try again.")
        guard let id = reply.jobId, !id.isEmpty else {
            throw APIError.server(status: 200, message: "The analysis could not be started. Try again.")
        }
        return id
    }

    func job(id: String) async throws -> AnalysisJob {
        let request = try await client.makeRequest("GET", "/analysis/job", query: ["id": id])
        let job = try await client.send(request, as: AnalysisJob.self)
        try Self.check(job.success, job.error, "Lost track of the analysis. Try again.")
        return job
    }

    func history(_ kind: AnalysisToolKind) async throws -> [AnalysisRunSummary] {
        let request = try await client.makeRequest("GET", "/analysis/history", query: ["tool": kind.rawValue])
        let reply = try await client.send(request, as: AnalysisHistoryReply.self)
        try Self.check(reply.success, reply.error, "Could not load your history. Try again.")
        return reply.runs ?? []
    }

    func run(id: String) async throws -> AnalysisRun {
        let request = try await client.makeRequest("GET", "/analysis/run", query: ["id": id])
        let reply = try await client.send(request, as: AnalysisRunReply.self)
        try Self.check(reply.success, reply.error, "Could not open that run. Try again.")
        guard let run = reply.run else {
            throw APIError.server(status: 200, message: reply.error ?? "Could not open that run. Try again.")
        }
        return run
    }

    func deleteRun(id: String) async throws {
        let request = try await client.makeRequest("DELETE", "/analysis/run", query: ["id": id])
        do {
            let reply = try await client.send(request, as: AnalysisAck.self)
            try Self.check(reply.success, reply.error, "Could not delete that run. Try again.")
        } catch APIError.server(404, _) {
            // Already gone: the list without it is what was asked for.
        }
    }

    /// A 2xx that does not say `success` is a refusal, worded as the server worded it.
    private static func check(_ success: Bool?, _ error: String?, _ fallback: String) throws {
        guard success == false else { return }
        throw APIError.server(status: 200, message: error.flatMap { $0.isEmpty ? nil : $0 } ?? fallback)
    }
}
