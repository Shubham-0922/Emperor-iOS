import Foundation
#if canImport(FoundationNetworking)
// URLSession lives in Foundation on Apple platforms but in FoundationNetworking on Linux,
// where the core package is compiled for tests.
import FoundationNetworking
#endif

struct APIConfig: Sendable {
    /// Public host. The app must use the `/api` prefix: a set of routes is registered only in
    /// bare form on port 3001, and the Vite proxy strips `/api` before forwarding, so the
    /// prefixed form is the only one that reaches every route.
    var baseURL: URL
    /// The server allows 600s for a chat run and 900s for uploads. A default 60s timeout
    /// would abort long drafts mid-answer.
    var requestTimeout: TimeInterval = 600

    static let production = APIConfig(
        baseURL: URL(string: "https://dev.emperorailabs.com/api")!)
}

/// Who we are, as far as this API is concerned.
///
/// Both fields are sent on every request, deliberately. The bearer token is currently only
/// enforced on `/filing/*` and upload placement; everything else selects data from a
/// client-supplied `userId`. Sending both means the client keeps working unchanged once the
/// backend is hardened to derive the user from the token.
struct Credentials: Equatable, Sendable {
    var token: String
    var userID: Int

    var userIDString: String { String(userID) }
}

enum APIError: LocalizedError, Equatable {
    case notAuthenticated
    case invalidCredentials
    case server(status: Int, message: String)
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You are signed out. Please sign in again."
        case .invalidCredentials: return "That email and password did not match."
        case .server(_, let message): return message
        case .transport(let message): return message
        case .decoding(let message): return "Unexpected response from the server. \(message)"
        }
    }
}

/// Thin HTTP layer over the Juristar backend.
///
/// Deliberately not generic over "REST" — this API is a hand-rolled `if/else` chain with
/// per-route conventions (errors as 500s, errors as 200s, a route that returns 200 before
/// the work it describes has started), so each call site states its own expectations.
actor APIClient {
    private let config: APIConfig
    private var credentials: Credentials?
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(config: APIConfig = .production, session: URLSession? = nil) {
        self.config = config
        if let session {
            self.session = session
        } else {
            let c = URLSessionConfiguration.default
            c.timeoutIntervalForRequest = config.requestTimeout
            c.timeoutIntervalForResource = config.requestTimeout
            #if canImport(Darwin)
            // Prefer waiting over failing when the advocate walks out of court signal.
            // Read-only on Linux, where this package is only compiled for tests.
            c.waitsForConnectivity = true
            #endif
            self.session = URLSession(configuration: c)
        }
    }

    func setCredentials(_ credentials: Credentials?) {
        self.credentials = credentials
    }

    func currentCredentials() -> Credentials? { credentials }

    // MARK: - Request building

    /// Builds a request with auth applied both ways: bearer header and `userId` parameter.
    func makeRequest(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) throws -> URLRequest {
        var query = query
        if requiresAuth {
            guard let credentials else { throw APIError.notAuthenticated }
            // GET/DELETE carry the caller identity in the query string; POST bodies carry it
            // as a field, added by the caller when it builds the payload.
            if method == "GET" || method == "DELETE" {
                query["userId"] = credentials.userIDString
            }
        }

        var components = URLComponents(
            url: config.baseURL.appendingPathComponent(String(path.trimmingPrefix("/"))),
            resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else {
            throw APIError.transport("Could not build a URL for \(path).")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = config.requestTimeout
        if let credentials {
            request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
            request.setValue(credentials.token, forHTTPHeaderField: "X-Auth-Token")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        return request
    }

    // MARK: - Calls

    func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await perform(request)
        try throwIfError(data: data, response: response)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport("Malformed response.")
            }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    /// Maps this API's error conventions onto `APIError`.
    ///
    /// Note the status codes are not meaningful on their own: a missing parameter yields 500
    /// on most routes, and `/stream-status` returns 200 for every error. The `error` key in
    /// the body is the reliable signal.
    private func throwIfError(data: Data, response: HTTPURLResponse) throws {
        guard !(200..<300).contains(response.statusCode) else { return }
        let body = try? decoder.decode(APIErrorBody.self, from: data)
        let message = body?.error ?? "The server returned status \(response.statusCode)."
        if response.statusCode == 401 {
            throw APIError.invalidCredentials
        }
        throw APIError.server(status: response.statusCode, message: message)
    }
}

/// Lets `makeRequest` take an existential `Encodable` body.
private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void
    init(_ wrapped: Encodable) {
        encode = wrapped.encode(to:)
    }
    func encode(to encoder: Encoder) throws { try encode(encoder) }
}
