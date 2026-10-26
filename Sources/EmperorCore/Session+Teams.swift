import Foundation

extension Session {
    var teams: TeamService { TeamService(client: client) }
}
