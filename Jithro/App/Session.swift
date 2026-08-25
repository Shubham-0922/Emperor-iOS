import Foundation
import Observation

/// App-wide auth state and the single shared `APIClient`.
@Observable
@MainActor
final class Session {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(User)
    }

    private(set) var state: State = .loading
    var signInError: String?
    var isWorking = false

    let client: APIClient
    let auth: AuthService
    let chats: ChatService
    let uploads: UploadService
    let files: FileService

    private static let tokenKey = "auth.token"
    private static let userKey = "auth.user"

    init(config: APIConfig = .production) {
        let client = APIClient(config: config)
        self.client = client
        self.auth = AuthService(client: client)
        self.chats = ChatService(client: client)
        self.uploads = UploadService(client: client)
        self.files = FileService(client: client)
    }

    var currentUser: User? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    /// Restores a previous sign-in.
    ///
    /// The stored user is trusted without a server round-trip because there is no endpoint
    /// that validates a token — no `/me`, no refresh. An expired token surfaces as the first
    /// failing request instead.
    func restore() async {
        guard let token = Keychain.get(Self.tokenKey),
              let data = Keychain.get(Self.userKey)?.data(using: .utf8),
              let user = try? JSONDecoder().decode(User.self, from: data)
        else {
            state = .signedOut
            return
        }
        await client.setCredentials(Credentials(token: token, userID: user.id))
        state = .signedIn(user)
    }

    func signIn(email: String, password: String) async {
        isWorking = true
        signInError = nil
        defer { isWorking = false }
        do {
            let response = try await auth.login(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password)
            await adopt(response)
        } catch {
            signInError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func register(name: String, email: String, password: String) async {
        isWorking = true
        signInError = nil
        defer { isWorking = false }
        do {
            let response = try await auth.register(
                name: name,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password)
            await adopt(response)
        } catch {
            signInError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func adopt(_ response: AuthResponse) async {
        Keychain.set(response.token, for: Self.tokenKey)
        if let encoded = try? JSONEncoder().encode(response.user),
           let json = String(data: encoded, encoding: .utf8) {
            Keychain.set(json, for: Self.userKey)
        }
        await client.setCredentials(
            Credentials(token: response.token, userID: response.user.id))
        state = .signedIn(response.user)
    }

    /// Signing out is purely local: the server has no logout route and no revocation, so the
    /// discarded token stays valid for the remainder of its 30 days.
    func signOut() async {
        Keychain.remove(Self.tokenKey)
        Keychain.remove(Self.userKey)
        await auth.signOut()
        state = .signedOut
    }
}
