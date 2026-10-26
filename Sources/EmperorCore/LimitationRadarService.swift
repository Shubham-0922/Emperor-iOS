import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol LimitationRadarProviding: Sendable {
    func audit(_ request: LimitationAuditRequest) async throws -> LimitationAudit
}

/// `POST /limitation-radar`: the platform's deterministic limitation audit.
///
/// Stateless. Its refusals are `{success:false, error:{code, message}}` with `error` an
/// **object**, whereas `APIClient.send` reads `error` as a string and would lose the sentence the
/// person needs ("The filing date is earlier than the cause of action"). So this calls
/// `client.perform` and reads the answer itself.
struct LimitationRadarService: LimitationRadarProviding {
    let client: APIClient

    func audit(_ request: LimitationAuditRequest) async throws -> LimitationAudit {
        var body = request
        if body.userId == nil {
            body.userId = await client.currentCredentials()?.userIDString
        }
        let urlRequest = try await client.makeRequest("POST", "/limitation-radar", body: body)
        let (data, response) = try await client.perform(urlRequest)
        return try Self.read(data: data, status: response.statusCode)
    }

    /// The audit in an answer, or the error it carries.
    static func read(data: Data, status: Int) throws -> LimitationAudit {
        let decoder = JSONDecoder()
        if (200..<300).contains(status),
           let audit = try? decoder.decode(LimitationAudit.self, from: data),
           (try? decoder.decode(LimitationRadarEnvelope.self, from: data))?.success != false {
            return audit
        }
        if status == 503, let notice = try? decoder.decode(MaintenanceBody.self, from: data),
           notice.maintenance == true {
            let text = [notice.message, notice.error].compactMap { $0 }.first { !$0.isEmpty }
            throw APIError.maintenance(
                message: text ?? "Emperor is down for maintenance. Please try again shortly.")
        }
        let message = (try? decoder.decode(LimitationRadarEnvelope.self, from: data))?
            .error?.message
        throw APIError.server(
            status: status,
            message: (message?.isEmpty == false ? message : nil)
                ?? "The audit service responded with HTTP \(status).")
    }
}
