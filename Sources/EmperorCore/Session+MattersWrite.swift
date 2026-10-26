import Foundation

extension Session {
    /// The matter writes, on the same authenticated client as the reads.
    var projectWrites: ProjectWriteService { ProjectWriteService(client: client) }

    /// Picked cases as tracked cases, preferring a copy in a team the user owns.
    var caseTracking: CaseTracking {
        let teams = self.teams
        let client = self.client
        return CaseTracking(cases: cases, search: courtSearch, ownedTeamIDs: {
            guard let me = await client.currentCredentials()?.userIDString,
                  let list = try? await teams.teams() else { return [] }
            return Set(list.filter { $0.ownerUserID == me }.map(\.id))
        })
    }
}
