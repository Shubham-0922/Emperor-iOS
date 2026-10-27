import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A case read from its court, and whether the server answered from its few-minute copy.
struct LookupResult: Equatable, Sendable {
    var record: LookupRecord
    var cached: Bool
}

/// Reading a case's full record from its court without saving it — Fetch Orders.
///
/// A protocol so `FetchOrdersViewModel` can be driven with no server.
protocol FetchOrdersProviding: Sendable {
    /// - Throws: `LookupFailure` for every refusal and failure, `CancellationError` when the
    ///   wait is abandoned.
    func lookup(_ card: CourtSearchResult) async throws -> LookupResult
}

/// `POST /court/lookup` — the web's `fetchOrdersApi.js` `lookupCase`.
///
/// Nothing is written: the court is read and the record handed back. Adding the case to Matters
/// is a separate step (`MatterCreating`).
struct FetchOrdersService: FetchOrdersProviding {
    let client: APIClient

    /// The court's own portal sets the pace: a few seconds usually, most of a minute for the
    /// slowest High Court portals.
    static let timeout: TimeInterval = 90

    private struct Body: Encodable {
        let userId: String
        let card: [String: JSONValue]
    }

    private struct Response: Decodable {
        var success: Bool?
        var code: String?
        var error: String?
        var record: LookupRecord?
        var cached: Bool?
    }

    func lookup(_ card: CourtSearchResult) async throws -> LookupResult {
        guard let credentials = await client.currentCredentials() else {
            throw LookupFailure.auth("Please sign in again to fetch court records.")
        }
        var request = try await client.makeRequest(
            "POST", "/court/lookup", body: Body(userId: credentials.userIDString, card: card.lookupCard))
        request.timeoutInterval = Self.timeout

        // Never retried here: each fresh lookup counts against a per-minute allowance, and a
        // court that is down does not come back inside a backoff.
        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await client.perform(request)
        } catch {
            // A wait abandoned on purpose (the screen closed, "Search again") is not a failure.
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            if DisplayText.isOffline(error) { throw LookupFailure.other(DisplayText.offlineMessage) }
            throw LookupFailure.other(LookupFailure.networkMessage)
        }

        // The body first: it carries the class of a refusal whatever the status says.
        let decoded = try? JSONDecoder().decode(Response.self, from: data)
        let ok = (200..<300).contains(http.statusCode)
        if ok, decoded?.success == true, let record = decoded?.record {
            return LookupResult(record: record, cached: decoded?.cached == true)
        }
        if http.statusCode == 503,
           let notice = try? JSONDecoder().decode(MaintenanceBody.self, from: data),
           notice.maintenance == true {
            let words = [notice.message, notice.error].compactMap { $0 }.first { !$0.isEmpty }
            throw LookupFailure.other(words ?? "Emperor is down for maintenance. Please try again shortly.")
        }
        throw LookupFailure.from(code: decoded?.code, status: http.statusCode, message: decoded?.error)
    }
}
