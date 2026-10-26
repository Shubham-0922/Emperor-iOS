import Foundation

// Request bodies and answers for the matter writes (`ProjectWriteService`), shaped exactly as the
// web's `src/lib/projectsApi.js` sends them and `lib/projects/routes.js` answers.
//
// Every body is a plain `[String: JSONValue]` rather than a synthesized `Encodable` struct, because
// on these routes **absent and null are different requests**: an absent key leaves the column as it
// is, a `null` runs the server's normaliser (which clears it, or resets it to its default). A
// synthesized encoder drops a nil, so "clear the court status" would silently become "leave it".

/// One value of a matter field as it goes on the wire: text, or an explicit `null`.
enum FieldValue: Encodable, Equatable, Sendable {
    case text(String)
    case null

    var json: JSONValue {
        switch self {
        case .text(let s): return .string(s)
        case .null: return .null
        }
    }

    /// Text, or `null` for nil.
    static func of(_ value: String?) -> FieldValue { value.map(FieldValue.text) ?? .null }

    func encode(to encoder: Encoder) throws { try json.encode(to: encoder) }
}

/// The `fields` of `POST /project-patch`: only the keys present change. The route is strict — a key
/// it does not know is refused — so the typed helpers are the way in.
struct ProjectFields: Encodable, Equatable, Sendable {
    var values: [String: FieldValue]

    init(_ values: [String: FieldValue] = [:]) { self.values = values }

    /// The keys `POST /project-patch` accepts (`PROJECT_FIELDS` in the platform's rules).
    static let knownKeys: Set<String> = [
        "name", "client", "description", "forumType", "forumName", "caseNumber", "caseYear", "caseType",
        "cnr", "stage", "status", "priority", "nextHearingDate", "filingDate", "color", "banner",
        "practiceArea", "ourSide", "oppositeParty", "courtStatus",
    ]

    static func status(_ status: MatterVocabulary.ProjectStatus) -> ProjectFields {
        ProjectFields(["status": .text(status.rawValue)])
    }

    /// A side from the vocabulary, the user's own words, or nil to clear it.
    static func ourSide(_ side: String?) -> ProjectFields { ProjectFields(["ourSide": .of(side)]) }

    static func practiceArea(_ area: String?) -> ProjectFields { ProjectFields(["practiceArea": .of(area)]) }

    /// `not_filed`, or nil — the user taking back "not filed yet".
    static func courtStatus(_ status: String?) -> ProjectFields { ProjectFields(["courtStatus": .of(status)]) }

    static func banner(_ banner: String?) -> ProjectFields { ProjectFields(["banner": .of(banner)]) }

    var json: [String: JSONValue] { values.mapValues(\.json) }

    func encode(to encoder: Encoder) throws { try json.encode(to: encoder) }
}

/// The body of `POST /project` (without `userId`, which the service adds). `id == nil` creates.
struct ProjectBody: Equatable, Sendable {
    var id: String?
    /// Every other key, as it goes on the wire.
    var fields: [String: JSONValue]

    var json: [String: JSONValue] {
        var out = fields
        if let id { out["id"] = .string(id) }
        return out
    }

    /// New matter's create (`NewMatterDialog.jsx`): a name, a banner, a folder colour and, for "Not
    /// filed yet", the court status — nothing else, so the server fills its defaults.
    static func newMatter(name: String, banner: String, color: String?, notFiled: Bool) -> ProjectBody {
        var fields: [String: JSONValue] = [
            "name": .string(name), "banner": .string(banner), "color": color.map(JSONValue.string) ?? .null,
        ]
        if notFiled { fields["courtStatus"] = .string("not_filed") }
        return ProjectBody(id: nil, fields: fields)
    }
}

// MARK: - Answers

/// `{success, error}` — what every write answers, at least.
struct WriteEnvelope: Decodable, Sendable {
    var success: Bool?
    var error: String?

    enum CodingKeys: String, CodingKey { case success, error }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try? c.decodeIfPresent(Bool.self, forKey: .success)
        error = c.wireString(.error)
    }
}

/// `{success, project}` — `POST /project`, `/project-patch`, `/project-link-case`.
struct ProjectWriteResponse: Decodable, Sendable {
    var success: Bool?
    var error: String?
    var project: Project?
    /// `/project-from-case` only.
    var existed: Bool?

    enum CodingKeys: String, CodingKey { case success, error, project, existed }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try? c.decodeIfPresent(Bool.self, forKey: .success)
        error = c.wireString(.error)
        project = (try? c.decodeIfPresent(Project.self, forKey: .project)) ?? nil
        existed = (try? c.decodeIfPresent(Bool.self, forKey: .existed)) ?? nil
    }
}

/// What `DELETE /project` reports it removed.
struct DeleteSummary: Decodable, Equatable, Sendable {
    var chats: Int?
    var drafts: Int?
    var tasks: Int?
    var ledger: Int?
    var people: Int?
    var updates: Int?
    var fileLinks: Int?
    var chatLinks: Int?
    /// Whether the matter's own storage folder went too.
    var storage: Bool?

    init(chats: Int? = nil, drafts: Int? = nil, tasks: Int? = nil, ledger: Int? = nil, people: Int? = nil,
         updates: Int? = nil, fileLinks: Int? = nil, chatLinks: Int? = nil, storage: Bool? = nil) {
        self.chats = chats
        self.drafts = drafts
        self.tasks = tasks
        self.ledger = ledger
        self.people = people
        self.updates = updates
        self.fileLinks = fileLinks
        self.chatLinks = chatLinks
        self.storage = storage
    }

    enum CodingKeys: String, CodingKey { case chats, drafts, tasks, ledger, people, updates, fileLinks, chatLinks, storage }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            chats: c.wireInt(.chats), drafts: c.wireInt(.drafts), tasks: c.wireInt(.tasks), ledger: c.wireInt(.ledger),
            people: c.wireInt(.people), updates: c.wireInt(.updates), fileLinks: c.wireInt(.fileLinks),
            chatLinks: c.wireInt(.chatLinks), storage: (try? c.decodeIfPresent(Bool.self, forKey: .storage)) ?? nil)
    }
}

struct DeleteProjectResponse: Decodable, Sendable {
    var success: Bool?
    var error: String?
    var deleted: DeleteSummary?

    enum CodingKeys: String, CodingKey { case success, error, deleted }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try? c.decodeIfPresent(Bool.self, forKey: .success)
        error = c.wireString(.error)
        deleted = (try? c.decodeIfPresent(DeleteSummary.self, forKey: .deleted)) ?? nil
    }
}

/// `POST /project-update`'s answer: the entry, and the matter's next hearing as it now stands — a
/// hearing added, moved or removed can change it.
struct SavedUpdate: Equatable, Sendable {
    var id: String
    var update: ProjectUpdate?
    var nextHearingDate: String?
}

struct SavedUpdateResponse: Decodable, Sendable {
    var success: Bool?
    var error: String?
    var id: String?
    var update: ProjectUpdate?
    var nextHearingDate: String?

    enum CodingKeys: String, CodingKey { case success, error, id, update, nextHearingDate }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try? c.decodeIfPresent(Bool.self, forKey: .success)
        error = c.wireString(.error)
        id = c.wireString(.id)
        update = (try? c.decodeIfPresent(ProjectUpdate.self, forKey: .update)) ?? nil
        nextHearingDate = c.wireString(.nextHearingDate)
    }
}

/// `{success, task | entry | person}` — the row under a key named for its kind.
struct ChildRowResponse<Row: Decodable & Sendable>: Decodable, Sendable {
    var success: Bool?
    var error: String?
    var row: Row?

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Which key carries the row; set per route before decoding.
    static var rowKey: String {
        switch Row.self {
        case is ProjectTask.Type: return "task"
        case is LedgerEntry.Type: return "entry"
        case is ProjectPerson.Type: return "person"
        default: return "row"
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        success = try? c.decodeIfPresent(Bool.self, forKey: Key(stringValue: "success"))
        error = c.wireString(Key(stringValue: "error"))
        row = (try? c.decodeIfPresent(Row.self, forKey: Key(stringValue: Self.rowKey))) ?? nil
    }
}

/// The court record's counts after a refresh — how many hearings and orders it now holds.
struct RefreshCounts: Equatable, Sendable {
    var hearings: Int?
    var orders: Int?

    /// `refreshedText`: "Court record refreshed — 3 hearings, 1 order".
    var text: String {
        let parts = [(hearings, "hearing"), (orders, "order")].compactMap { n, word -> String? in
            guard let n else { return nil }
            return "\(n) \(word)\(n == 1 ? "" : "s")"
        }
        return parts.isEmpty ? "Court record refreshed" : "Court record refreshed — \(parts.joined(separator: ", "))"
    }
}

/// What asking the court to re-read the linked case came to.
enum RefreshOutcome: Equatable, Sendable {
    /// Done; `lastSyncedAt` as the case now stands.
    case done(lastSyncedAt: String?, counts: RefreshCounts)
    /// Asked again too soon: wait `retryAfter` seconds. The server's own sentence is kept.
    case tooSoon(retryAfter: Int, message: String)
    /// The court's site failed or did not answer in time — the court's fault, not the request's.
    case courtFailed(message: String)

    /// `retrySeconds`: the server's seconds, read defensively — nothing usable is five minutes,
    /// and a figure over an hour is milliseconds.
    static func retrySeconds(_ raw: Double?) -> Int {
        guard let n = raw, n.isFinite, n > 0 else { return 300 }
        return Int((n > 3600 ? n / 1000 : n).rounded(.up))
    }

    /// "4:00" — minutes and seconds.
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):\(s % 60 < 10 ? "0" : "")\(s % 60)"
    }
}

struct RefreshResponse: Decodable, Sendable {
    var success: Bool?
    var error: String?
    var lastSyncedAt: String?
    var retryAfter: Double?
    var counts: RefreshCounts?

    enum CodingKeys: String, CodingKey { case success, error, lastSyncedAt, retryAfter, counts }
    enum CountKeys: String, CodingKey { case hearings, orders }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try? c.decodeIfPresent(Bool.self, forKey: .success)
        error = c.wireString(.error)
        lastSyncedAt = c.wireString(.lastSyncedAt)
        retryAfter = c.wireDouble(.retryAfter)
        if let counts = try? c.nestedContainer(keyedBy: CountKeys.self, forKey: .counts) {
            self.counts = RefreshCounts(hearings: counts.wireInt(.hearings), orders: counts.wireInt(.orders))
        }
    }
}
