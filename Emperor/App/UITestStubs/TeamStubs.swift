#if DEBUG
import Foundation

/// The UI tests' canned answers for teams: `GET /teams`, `POST /teams`, `POST /team-invite`.
/// Stateful for the life of the launch, so a created team and an added member show on the next
/// read. Owned by package 11-T; `-UITestEmpty` leaves only the personal team, which the server
/// always has.
enum TeamStubs {

    private struct Row {
        var id: String
        var name: String
        var owner: String
        var role: String
        var count: Int

        var json: String {
            let escaped = name.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return #"{"id":"\#(id)","name":"\#(escaped)","owner_user_id":"\#(owner)","role":"\#(role)","member_count":\#(count)}"#
        }
    }

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var rows: [Row]
        private var created = 0

        init() {
            var initial = [Row(id: "team_1", name: "My Firm", owner: "1", role: "owner", count: 1)]
            if !UITestSupport.isEmpty {
                initial.append(
                    Row(id: "team_2", name: "Chambers of R. Mehta", owner: "9", role: "member", count: 4))
            }
            rows = initial
        }

        func listJSON() -> String {
            lock.lock(); defer { lock.unlock() }
            return #"{"success":true,"teams":[\#(rows.map(\.json).joined(separator: ","))]}"#
        }

        func create(name: String) -> String {
            lock.lock(); defer { lock.unlock() }
            created += 1
            let id = "team_new_\(created)"
            rows.append(Row(id: id, name: name, owner: "1", role: "owner", count: 1))
            return id
        }

        func addMember(teamID: String) {
            lock.lock(); defer { lock.unlock() }
            if let i = rows.firstIndex(where: { $0.id == teamID }) { rows[i].count += 1 }
        }
    }

    private static let store = Store()

    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        switch (request.httpMethod ?? "GET", path) {
        case ("GET", "/teams"):
            return .json(store.listJSON())
        case ("POST", "/teams"):
            let name = (UITestSupport.Fixtures.jsonBody(of: request)?["name"] as? String) ?? ""
            guard !name.isEmpty else {
                return .json(#"{"error":"Missing userId or name"}"#, status: 500)
            }
            return .json(#"{"success":true,"id":"\#(store.create(name: name))"}"#)
        case ("POST", "/team-invite"):
            let body = UITestSupport.Fixtures.jsonBody(of: request) ?? [:]
            let teamID = body["teamId"] as? String ?? ""
            let email = (body["email"] as? String ?? "").lowercased()
            if teamID == "team_2" {
                return .json(
                    #"{"success":false,"error":"Only team owners/admins can invite"}"#, status: 403)
            }
            if email == "nobody@example.com" {
                return .json(#"{"success":false,"error":"No user with that email"}"#, status: 404)
            }
            store.addMember(teamID: teamID)
            return .json(#"{"success":true}"#)
        default:
            return nil
        }
    }
}
#endif
