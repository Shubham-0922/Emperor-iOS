import Foundation
#if canImport(FoundationNetworking)
// URLSession lives in Foundation on Apple platforms but in FoundationNetworking on Linux,
// where the core package is compiled for tests.
import FoundationNetworking
#endif

struct AuthService {
    let client: APIClient

    private struct LoginBody: Encodable {
        let email: String
        let password: String
    }

    private struct RegisterBody: Encodable {
        let name: String
        let email: String
        let password: String
    }

    /// Signs in.
    ///
    /// Both wrong-password and unknown-email answer 401 `{"error":"Invalid credentials"}` —
    /// the server deliberately does not distinguish them, and neither should the UI.
    func login(email: String, password: String) async throws -> AuthResponse {
        let request = try await client.makeRequest(
            "POST", "/login",
            body: LoginBody(email: email, password: password),
            requiresAuth: false)
        return try await client.send(request, as: AuthResponse.self)
    }

    /// Registers a new account.
    ///
    /// The returned `user` is a hand-built object carrying only `id`, `name` and `email` —
    /// not the fuller row `/login` returns. Fetch the rest on next sign-in if needed.
    func register(name: String, email: String, password: String) async throws -> AuthResponse {
        let request = try await client.makeRequest(
            "POST", "/register",
            body: RegisterBody(name: name, email: email, password: password),
            requiresAuth: false)
        return try await client.send(request, as: AuthResponse.self)
    }

    /// There is no logout endpoint and no server-side revocation: signing out is discarding
    /// the token locally. A leaked token stays valid for its full 30-day life.
    func signOut() async {
        await client.setCredentials(nil)
    }
}
