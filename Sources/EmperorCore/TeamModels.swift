import Foundation

/// A team: the people who share tracked court cases.
///
/// Every account has a personal team of its own ("My Firm", role `owner`) from the first time
/// `/teams` or `/cases` is read (`sync-server.js:5636-5646`). Everyone in a team sees every case
/// the team tracks (`sync-server.js:14503-14526`).
///
/// Decoded leniently: `owner_user_id` is stored as text but may arrive as a number, and
/// `member_count` as an integer, a fraction or text. A row with no `id` or `name` is not a team
/// the app can show, and `TeamsResponse` leaves it out rather than failing the list.
struct Team: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let ownerUserID: String?
    /// `owner`, `admin` or `member`; absent on a row an older server wrote.
    let role: String?
    let memberCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, role
        case ownerUserID = "owner_user_id"
        case memberCount = "member_count"
    }

    init(id: String, name: String, ownerUserID: String? = nil, role: String? = nil, memberCount: Int = 1) {
        self.id = id
        self.name = name
        self.ownerUserID = ownerUserID
        self.role = role
        self.memberCount = memberCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = Self.text(container, .id),
              let name = try? container.decode(String.self, forKey: .name)
        else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "A team needs an id and a name."))
        }
        self.id = id
        self.name = name
        ownerUserID = Self.text(container, .ownerUserID)
        role = try? container.decodeIfPresent(String.self, forKey: .role)
        memberCount = Self.count(container, .memberCount) ?? 1
    }

    private static func text(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return String(value) }
        return nil
    }

    private static func count(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key), value.isFinite {
            return Int(value)
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key),
           let parsed = Double(value.trimmingCharacters(in: .whitespaces)), parsed.isFinite {
            return Int(parsed)
        }
        return nil
    }

    /// Whether this account may add people: the owner and admins, and a row with no role at all
    /// (`TeamModal.jsx:39`).
    var canInvite: Bool { role == nil || role == "owner" || role == "admin" }

    /// More than one person: the team's cases are shared.
    var isShared: Bool { memberCount > 1 }

    /// The invite picker's label: `Chambers · 4 members` once shared, the bare name otherwise
    /// (`TeamModal.jsx:45-48`).
    var pickerLabel: String { isShared ? "\(name) · \(memberCount) members" : name }

    var roleLabel: String {
        switch role {
        case "owner": return "Owner"
        case "admin": return "Admin"
        default: return "Member"
        }
    }

    /// "Owner · 3 members", as a row's detail line.
    var rowDetail: String {
        "\(roleLabel) · \(memberCount) \(memberCount == 1 ? "member" : "members")"
    }
}

/// `GET /teams`, decoding the rows one at a time.
struct TeamsResponse: Decodable, Sendable {
    var success: Bool?
    var error: String?
    var teams: [Team] = []

    enum CodingKeys: String, CodingKey { case success, error, teams }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try? container.decodeIfPresent(Bool.self, forKey: .success)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
        guard var rows = try? container.nestedUnkeyedContainer(forKey: .teams) else { return }
        while !rows.isAtEnd {
            if let team = try? rows.decode(Team.self) {
                teams.append(team)
            } else if (try? rows.decode(JSONValue.self)) == nil {
                break
            }
        }
    }
}

/// `POST /teams` and `POST /team-invite` answers.
struct TeamWriteResponse: Decodable, Sendable {
    var success: Bool?
    var id: String?
    var error: String?
}

enum TeamDirectory {
    /// The team a tracked case is "Shared with", or `nil` when it is not shared.
    ///
    /// The web names a team only when it has more than one member — every account's own cases
    /// sit in a team of one, and saying so on each card would be noise
    /// (`src/components/matters/trackedCases.js:77-79`). The team's own name wins; the case's
    /// `team_name` is the fallback when that is empty.
    static func sharedWith(teamID: String?, teams: [Team], fallbackName: String?) -> String? {
        guard let teamID, let team = teams.first(where: { $0.id == teamID }), team.isShared else {
            return nil
        }
        if !team.name.isEmpty { return team.name }
        if let fallbackName, !fallbackName.isEmpty { return fallbackName }
        return nil
    }
}
