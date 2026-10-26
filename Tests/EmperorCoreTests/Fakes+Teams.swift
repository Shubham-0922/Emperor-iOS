import Foundation
@testable import EmperorCore

final class FakeTeams: TeamProviding, @unchecked Sendable {
    var teamList: [Team]
    var listError: Error?
    var createError: Error?
    var inviteError: Error?
    var createdID = "team_new_1"
    private(set) var created: [String] = []
    private(set) var invited: [(teamID: String, email: String)] = []
    private(set) var listCalls = 0
    /// Held back so a test can tap twice while the first call is in flight.
    var inviteDelay: Duration?

    init(_ teams: [Team] = []) { teamList = teams }

    func teams() async throws -> [Team] {
        listCalls += 1
        if let listError { throw listError }
        return teamList
    }

    func createTeam(name: String) async throws -> String {
        if let createError { throw createError }
        created.append(name)
        teamList.append(Team(id: createdID, name: name, ownerUserID: "1", role: "owner", memberCount: 1))
        return createdID
    }

    func invite(teamID: String, email: String) async throws {
        if let inviteDelay { try await Task.sleep(for: inviteDelay) }
        if let inviteError { throw inviteError }
        invited.append((teamID, email))
        if let i = teamList.firstIndex(where: { $0.id == teamID }) {
            let t = teamList[i]
            teamList[i] = Team(id: t.id, name: t.name, ownerUserID: t.ownerUserID, role: t.role, memberCount: t.memberCount + 1)
        }
    }
}
