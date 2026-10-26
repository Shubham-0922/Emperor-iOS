import Foundation

protocol TeamProviding: Sendable {
    func teams() async throws -> [Team]
    /// Creates a team with the caller as its owner; answers its id.
    func createTeam(name: String) async throws -> String
    /// Adds an existing account to a team, at once and without its acceptance.
    func invite(teamID: String, email: String) async throws
}

/// Teams: list, create, invite (`sync-server.js:13497-13567`). Stateless.
///
/// The server answers a missing field with a 500 and a refusal with a 403 or 404 carrying its own
/// sentence, which `APIError` passes through for the screen to show.
struct TeamService: TeamProviding {
    let client: APIClient

    func teams() async throws -> [Team] {
        let request = try await client.makeRequest("GET", "/teams")
        let response = try await client.send(request, as: TeamsResponse.self)
        try Self.check(response.success, response.error, "Could not load your teams.")
        return response.teams
    }

    private struct CreateBody: Encodable {
        let userId: String
        let name: String
    }

    private struct InviteBody: Encodable {
        let userId: String
        let teamId: String
        let email: String
    }

    func createTeam(name: String) async throws -> String {
        guard let credentials = await client.currentCredentials() else {
            throw APIError.notAuthenticated
        }
        let request = try await client.makeRequest(
            "POST", "/teams", body: CreateBody(userId: credentials.userIDString, name: name))
        let response = try await client.send(request, as: TeamWriteResponse.self)
        try Self.check(response.success, response.error, "Could not create team.")
        guard let id = response.id else {
            throw APIError.server(status: 200, message: "Could not create team.")
        }
        return id
    }

    func invite(teamID: String, email: String) async throws {
        guard let credentials = await client.currentCredentials() else {
            throw APIError.notAuthenticated
        }
        let request = try await client.makeRequest(
            "POST", "/team-invite",
            body: InviteBody(userId: credentials.userIDString, teamId: teamID, email: email))
        let response = try await client.send(request, as: TeamWriteResponse.self)
        try Self.check(response.success, response.error, "Could not add member.")
    }

    /// A 200 that does not say `success` is a refusal, worded as the server worded it.
    private static func check(_ success: Bool?, _ error: String?, _ fallback: String) throws {
        guard success != true else { return }
        throw APIError.server(status: 200, message: error ?? fallback)
    }
}
