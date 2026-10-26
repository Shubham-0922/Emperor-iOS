import Foundation
@testable import EmperorCore

final class FakeRadar: LimitationRadarProviding, @unchecked Sendable {
    var answer: LimitationAudit?
    var error: Error?
    /// Held until `release()` when set, so a test can start a second run while one is in flight.
    var gate: AsyncStream<Void>?
    private let lock = NSLock()
    private var _requests: [LimitationAuditRequest] = []

    var requests: [LimitationAuditRequest] { lock.withLock { _requests } }

    func audit(_ request: LimitationAuditRequest) async throws -> LimitationAudit {
        lock.withLock { _requests.append(request) }
        if let gate { for await _ in gate { break } }
        if let error { throw error }
        guard let answer else { throw APIError.server(status: 500, message: "no answer") }
        return answer
    }
}
