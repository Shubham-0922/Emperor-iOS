import Foundation

// Wire models for matters — the web's "projects": hand-made files, one per matter, as opposed to
// the court-scraped `LegalCase`.
//
// The two are the same mental object seen two ways, but they are different tables with different
// owners. A case belongs to a team and is filled in by the court scrapers; a project belongs to one
// user and is typed in by hand. `linked_case_id` is the bridge when the user has joined one to the
// other, and the workspace then carries the case's own record (`courtHistory`, `linkedCase`).
//
// Every field but a row's id is optional and every list is decoded one element at a time
// (`LossyList`): a matter typed in half-finished is the normal case, and one odd row must cost only
// itself, never the whole screen. That is the lesson of `courtHistory[].data` — it arrives as a
// parsed JSON object, and the earlier model read it as text, so every matter linked to a case with
// scraped data failed to open at all.

/// A matter, as `GET /projects` and `GET /project` return it (`projects.*`).
struct Project: Codable, Equatable, Identifiable, Sendable {
    let id: String
    /// `NOT NULL` in the schema but optional here: an older row can hold an empty string.
    /// `displayName` is what screens read.
    var name: String?
    var client: String?
    /// The wire key is `description`; renamed so it does not shadow `String(describing:)`.
    var notes: String?
    /// `district`, `high_court`, … — `MatterVocabulary.Forum`. `other` is the server's default.
    var forumType: String?
    /// Free text — "NCLT New Delhi Bench-III".
    var forumName: String?
    /// TEXT columns, so `String?` — a number typed in round-trips out as text.
    var caseNumber: String?
    var caseYear: String?
    var caseType: String?
    var cnr: String?
    var stage: String?
    /// `active` by default; `on_hold`, `disposed`, `archived` (`MatterVocabulary.ProjectStatus`).
    var status: String?
    var priority: String?
    var nextHearingDateRaw: String?
    var filingDateRaw: String?
    var linkedCaseID: String?
    /// A folder colour key (`MatterVocabulary.ProjectColor`), never a CSS value.
    var color: String?
    var updatedAtRaw: String?
    var createdAtRaw: String?
    var archivedAtRaw: String?
    /// A banner preset key, or `image` for an uploaded picture (`GET /project-banner`).
    var banner: String?
    var practiceArea: String?
    /// Which side the user acts for; a vocabulary key or free text.
    var ourSide: String?
    /// `not_filed` when the user has said there is no case to find yet.
    var courtStatus: String?
    var oppositeParty: String?

    // MARK: - List-only, computed by the query

    // Present on `GET /projects` only. Optional rather than zero: on the detail route the honest
    // answer is "not stated", and a card reading "0 files" on one screen and nothing on another
    // reads as data loss.

    var fileCount: Int?
    var chatCount: Int?
    var updateCount: Int?
    /// The newest update's `COALESCE(event_date, created_at)` — a day on some rows, a timestamp on others.
    var lastActivityRaw: String?
    var openTasks: Int?
    /// The earliest open task's due day.
    var nextTaskDueRaw: String?
    /// Rupees, as floats.
    var billed: Double?
    var received: Double?

    init(
        id: String, name: String? = nil, client: String? = nil, notes: String? = nil,
        forumType: String? = nil, forumName: String? = nil, caseNumber: String? = nil,
        caseYear: String? = nil, caseType: String? = nil, cnr: String? = nil, stage: String? = nil,
        status: String? = nil, priority: String? = nil, nextHearingDateRaw: String? = nil,
        filingDateRaw: String? = nil, linkedCaseID: String? = nil, color: String? = nil,
        updatedAtRaw: String? = nil, createdAtRaw: String? = nil, archivedAtRaw: String? = nil,
        banner: String? = nil, practiceArea: String? = nil, ourSide: String? = nil,
        courtStatus: String? = nil, oppositeParty: String? = nil, fileCount: Int? = nil,
        chatCount: Int? = nil, updateCount: Int? = nil, lastActivityRaw: String? = nil,
        openTasks: Int? = nil, nextTaskDueRaw: String? = nil, billed: Double? = nil,
        received: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.client = client
        self.notes = notes
        self.forumType = forumType
        self.forumName = forumName
        self.caseNumber = caseNumber
        self.caseYear = caseYear
        self.caseType = caseType
        self.cnr = cnr
        self.stage = stage
        self.status = status
        self.priority = priority
        self.nextHearingDateRaw = nextHearingDateRaw
        self.filingDateRaw = filingDateRaw
        self.linkedCaseID = linkedCaseID
        self.color = color
        self.updatedAtRaw = updatedAtRaw
        self.createdAtRaw = createdAtRaw
        self.archivedAtRaw = archivedAtRaw
        self.banner = banner
        self.practiceArea = practiceArea
        self.ourSide = ourSide
        self.courtStatus = courtStatus
        self.oppositeParty = oppositeParty
        self.fileCount = fileCount
        self.chatCount = chatCount
        self.updateCount = updateCount
        self.lastActivityRaw = lastActivityRaw
        self.openTasks = openTasks
        self.nextTaskDueRaw = nextTaskDueRaw
        self.billed = billed
        self.received = received
    }

    enum CodingKeys: String, CodingKey {
        case id, name, client, cnr, stage, status, priority, color, banner, billed, received
        case notes = "description"
        case forumType = "forum_type"
        case forumName = "forum_name"
        case caseNumber = "case_number"
        case caseYear = "case_year"
        case caseType = "case_type"
        case nextHearingDateRaw = "next_hearing_date"
        case filingDateRaw = "filing_date"
        case linkedCaseID = "linked_case_id"
        case updatedAtRaw = "updated_at"
        case createdAtRaw = "created_at"
        case archivedAtRaw = "archived_at"
        case practiceArea = "practice_area"
        case ourSide = "our_side"
        case courtStatus = "court_status"
        case oppositeParty = "opposite_party"
        case fileCount = "file_count"
        case chatCount = "chat_count"
        case updateCount = "update_count"
        case lastActivityRaw = "last_activity"
        case openTasks = "open_tasks"
        case nextTaskDueRaw = "next_task_due"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.wireString(.id), !id.isEmpty else {
            throw DecodingError.keyNotFound(
                CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "A matter without an id"))
        }
        self.init(
            id: id, name: c.wireString(.name), client: c.wireString(.client),
            notes: c.wireString(.notes), forumType: c.wireString(.forumType),
            forumName: c.wireString(.forumName), caseNumber: c.wireString(.caseNumber),
            caseYear: c.wireString(.caseYear), caseType: c.wireString(.caseType),
            cnr: c.wireString(.cnr), stage: c.wireString(.stage), status: c.wireString(.status),
            priority: c.wireString(.priority), nextHearingDateRaw: c.wireString(.nextHearingDateRaw),
            filingDateRaw: c.wireString(.filingDateRaw), linkedCaseID: c.wireString(.linkedCaseID),
            color: c.wireString(.color), updatedAtRaw: c.wireString(.updatedAtRaw),
            createdAtRaw: c.wireString(.createdAtRaw), archivedAtRaw: c.wireString(.archivedAtRaw),
            banner: c.wireString(.banner), practiceArea: c.wireString(.practiceArea),
            ourSide: c.wireString(.ourSide), courtStatus: c.wireString(.courtStatus),
            oppositeParty: c.wireString(.oppositeParty), fileCount: c.wireInt(.fileCount),
            chatCount: c.wireInt(.chatCount), updateCount: c.wireInt(.updateCount),
            lastActivityRaw: c.wireString(.lastActivityRaw), openTasks: c.wireInt(.openTasks),
            nextTaskDueRaw: c.wireString(.nextTaskDueRaw), billed: c.wireDouble(.billed),
            received: c.wireDouble(.received))
    }

    // MARK: - Derived

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Untitled matter" : trimmed
    }

    /// `caseRefOf`: "W.P.(C) 4412/2025", the CNR without a number; "" for neither.
    var caseRef: String {
        MatterMeta.caseRef(caseNumber: caseNumber, caseType: caseType, caseYear: caseYear, cnr: cnr)
    }

    /// The status this matter files under; a value outside the vocabulary counts as active, as
    /// the web's counts do.
    var statusKey: MatterVocabulary.ProjectStatus {
        status.flatMap(MatterVocabulary.ProjectStatus.init(rawValue:)) ?? .active
    }

    var isHighPriority: Bool { priority == "high" }

    var isArchived: Bool { statusKey == .archived }

    /// The user's own word that there is no case yet — and no case linked.
    var isNotFiled: Bool {
        (linkedCaseID ?? "").isEmpty && courtStatus == "not_filed"
    }

    /// `courtOf` (the card): the court's name, else the forum's kind — but not `other`, the
    /// server's default for "nobody said".
    var courtName: String {
        if let forumName, !forumName.isEmpty { return forumName }
        guard let forumType, !forumType.isEmpty, forumType != "other" else { return "" }
        return MatterVocabulary.Forum.of(forumType).shortLabel
    }

    /// `clientOf` (the card): "Ankit Bhalla (Petitioner)", or "For the petitioner".
    var clientLine: String {
        let side = MatterMeta.sideLabel(ourSide)
        if let client, !client.isEmpty { return side.isEmpty ? client : "\(client) (\(side))" }
        return side.isEmpty ? "" : "For the \(side.lowercased())"
    }

    var bannerPreset: MatterVocabulary.BannerPreset {
        MatterMeta.bannerPreset(banner: banner, color: color)
    }

    var hasBannerImage: Bool { banner == "image" }

    var nextHearingDate: Date? { WireDate.parseDay(nextHearingDateRaw) }
    var updatedAt: Date? { WireDate.parseAny(updatedAtRaw) }
}

/// One entry on a matter's own record — a row of `project_updates`.
struct ProjectUpdate: Codable, Equatable, Identifiable, Sendable {
    let id: String
    /// `note`, `hearing`, `order`, `filing`, `task`, `milestone`, `event`.
    var kind: String?
    var title: String?
    var body: String?
    var eventDateRaw: String?
    var status: String?
    var createdAtRaw: String?
    /// `manual`, `ai` or `court` — who put it on the record.
    var source: String?
    var sourceRef: String?
    /// The stored JSON payload, as text.
    var payloadRaw: String?

    init(
        id: String, kind: String? = nil, title: String? = nil, body: String? = nil,
        eventDateRaw: String? = nil, status: String? = nil, createdAtRaw: String? = nil,
        source: String? = nil, sourceRef: String? = nil, payloadRaw: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.eventDateRaw = eventDateRaw
        self.status = status
        self.createdAtRaw = createdAtRaw
        self.source = source
        self.sourceRef = sourceRef
        self.payloadRaw = payloadRaw
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, body, status, source
        case eventDateRaw = "event_date"
        case createdAtRaw = "created_at"
        case sourceRef = "source_ref"
        case payloadRaw = "payload"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.wireID(.id), kind: c.wireString(.kind), title: c.wireString(.title),
            body: c.wireString(.body), eventDateRaw: c.wireString(.eventDateRaw),
            status: c.wireString(.status), createdAtRaw: c.wireString(.createdAtRaw),
            source: c.wireString(.source), sourceRef: c.wireString(.sourceRef),
            payloadRaw: c.wireJSONText(.payloadRaw))
    }

    /// When this entry belongs on the timeline.
    var day: Date? { WireDate.parseAny(eventDateRaw) ?? WireDate.parseAny(createdAtRaw) }

    /// Whether there is anything to draw: a row with neither a title nor a body is a bare date.
    /// `ProjectService` drops such rows, so a count and the rows under it cannot disagree.
    var isRenderable: Bool {
        title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// The row, as the chronology port reads it.
    var recordUpdate: MatterRecord.Update {
        MatterRecord.Update(
            id: id, kind: kind, title: title, body: body, eventDate: eventDateRaw,
            createdAt: createdAtRaw, source: source, sourceRef: sourceRef)
    }
}

/// A conversation filed under the matter.
struct ProjectChat: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var title: String?
    /// Zoneless SQLite time.
    var updatedAtRaw: String?
    var linkedAtRaw: String?

    init(id: String, title: String? = nil, updatedAtRaw: String? = nil, linkedAtRaw: String? = nil) {
        self.id = id
        self.title = title
        self.updatedAtRaw = updatedAtRaw
        self.linkedAtRaw = linkedAtRaw
    }

    enum CodingKeys: String, CodingKey {
        case id, title
        case updatedAtRaw = "updated_at"
        case linkedAtRaw = "linked_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.wireID(.id), title: c.wireString(.title),
            updatedAtRaw: c.wireString(.updatedAtRaw), linkedAtRaw: c.wireString(.linkedAtRaw))
    }
}

/// One row of the linked case's court record: a hearing, an order, an application, a party, a
/// court fee, a connected matter.
///
/// - Important: `data` is a **parsed JSON object** on the wire (or `null`). Older servers sent the
///   column as JSON text, so both are read; anything else is empty and costs only this row.
struct CourtHistoryItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    /// `hearings`, `orders`, `applications`, `parties`, `courtfees`, `connected`.
    var section: String
    var title: String?
    var subtitle: String?
    var itemDateRaw: String?
    var status: String?
    var data: [String: JSONValue]
    var source: String?

    init(
        id: String, section: String, title: String? = nil, subtitle: String? = nil,
        itemDateRaw: String? = nil, status: String? = nil, data: [String: JSONValue] = [:],
        source: String? = nil
    ) {
        self.id = id
        self.section = section
        self.title = title
        self.subtitle = subtitle
        self.itemDateRaw = itemDateRaw
        self.status = status
        self.data = data
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case id, section, title, subtitle, status, data, source
        case itemDateRaw = "item_date"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decodeIfPresent(JSONValue.self, forKey: .data)) ?? nil
        self.init(
            id: try c.wireID(.id), section: c.wireString(.section) ?? "",
            title: c.wireString(.title), subtitle: c.wireString(.subtitle),
            itemDateRaw: c.wireString(.itemDateRaw), status: c.wireString(.status),
            data: MatterRecord.CourtItem.data(fromWire: raw), source: c.wireString(.source))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(section, forKey: .section)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encodeIfPresent(itemDateRaw, forKey: .itemDateRaw)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encode(data, forKey: .data)
        try c.encodeIfPresent(source, forKey: .source)
    }

    /// One of the data's values as text: a string as written, a whole number without ".0".
    func text(_ key: String) -> String {
        switch data[key] {
        case .string(let s)?: return s
        case .number(let n)?:
            return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .bool(let b)?: return b ? "true" : "false"
        default: return ""
        }
    }

    /// Whether there is anything to draw — a title, a subtitle or scraped data.
    var isRenderable: Bool {
        title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || subtitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || !data.isEmpty
    }

    /// The row, as the chronology port reads it.
    var recordItem: MatterRecord.CourtItem {
        MatterRecord.CourtItem(
            id: id, section: section, title: title, subtitle: subtitle, itemDate: itemDateRaw, data: data)
    }
}

/// The linked case, in summary — sent only to a member of the team that tracks it.
struct LinkedCase: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var title: String?
    var courtName: String?
    var courtType: String?
    var caseType: String?
    var caseNumber: String?
    var caseYear: String?
    var cnr: String?
    var nextHearingDateRaw: String?
    var stage: String?
    var status: String?
    var lastSyncedAtRaw: String?

    init(
        id: String, title: String? = nil, courtName: String? = nil, courtType: String? = nil,
        caseType: String? = nil, caseNumber: String? = nil, caseYear: String? = nil,
        cnr: String? = nil, nextHearingDateRaw: String? = nil, stage: String? = nil,
        status: String? = nil, lastSyncedAtRaw: String? = nil
    ) {
        self.id = id
        self.title = title
        self.courtName = courtName
        self.courtType = courtType
        self.caseType = caseType
        self.caseNumber = caseNumber
        self.caseYear = caseYear
        self.cnr = cnr
        self.nextHearingDateRaw = nextHearingDateRaw
        self.stage = stage
        self.status = status
        self.lastSyncedAtRaw = lastSyncedAtRaw
    }

    enum CodingKeys: String, CodingKey {
        case id, title, cnr, stage, status
        case courtName = "court_name"
        case courtType = "court_type"
        case caseType = "case_type"
        case caseNumber = "case_number"
        case caseYear = "case_year"
        case nextHearingDateRaw = "next_hearing_date"
        case lastSyncedAtRaw = "last_synced_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.wireID(.id), title: c.wireString(.title),
            courtName: c.wireString(.courtName), courtType: c.wireString(.courtType),
            caseType: c.wireString(.caseType), caseNumber: c.wireString(.caseNumber),
            caseYear: c.wireString(.caseYear), cnr: c.wireString(.cnr),
            nextHearingDateRaw: c.wireString(.nextHearingDateRaw), stage: c.wireString(.stage),
            status: c.wireString(.status), lastSyncedAtRaw: c.wireString(.lastSyncedAtRaw))
    }
}

/// A task or deadline on the matter.
struct ProjectTask: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var title: String?
    var notes: String?
    /// A calendar day (`YYYY-MM-DD`, India).
    var dueDateRaw: String?
    /// `MatterVocabulary.TaskKind`.
    var kind: String?
    var priority: String?
    /// `open` or `done`.
    var status: String?
    var completedAtRaw: String?
    var createdAtRaw: String?
    var updatedAtRaw: String?

    init(
        id: String, title: String? = nil, notes: String? = nil, dueDateRaw: String? = nil,
        kind: String? = nil, priority: String? = nil, status: String? = nil,
        completedAtRaw: String? = nil, createdAtRaw: String? = nil, updatedAtRaw: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDateRaw = dueDateRaw
        self.kind = kind
        self.priority = priority
        self.status = status
        self.completedAtRaw = completedAtRaw
        self.createdAtRaw = createdAtRaw
        self.updatedAtRaw = updatedAtRaw
    }

    enum CodingKeys: String, CodingKey {
        case id, title, notes, kind, priority, status
        case dueDateRaw = "due_date"
        case completedAtRaw = "completed_at"
        case createdAtRaw = "created_at"
        case updatedAtRaw = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.wireID(.id), title: c.wireString(.title), notes: c.wireString(.notes),
            dueDateRaw: c.wireString(.dueDateRaw), kind: c.wireString(.kind),
            priority: c.wireString(.priority), status: c.wireString(.status),
            completedAtRaw: c.wireString(.completedAtRaw), createdAtRaw: c.wireString(.createdAtRaw),
            updatedAtRaw: c.wireString(.updatedAtRaw))
    }

    var isDone: Bool { status == "done" }

    /// The task, as the grouping port sorts it.
    var taskKey: MatterDates.TaskSortKey {
        MatterDates.TaskSortKey(
            status: status, kind: kind, dueDate: dueDateRaw, priority: priority,
            createdAt: createdAtRaw, completedAt: completedAtRaw, updatedAt: updatedAtRaw)
    }
}

/// One line of the matter's money: a fee billed, a payment received, an expense.
struct LedgerEntry: Codable, Equatable, Identifiable, Sendable {
    let id: String
    /// `fee`, `payment`, `expense`.
    var kind: String?
    var title: String?
    /// Whole paise — the stored figure.
    var amountPaise: Int?
    /// Rupees, derived by the server from the paise.
    var amount: Double?
    var entryDateRaw: String?
    var mode: String?
    var reference: String?
    var category: String?
    var receiptFile: String?
    var notes: String?
    var createdAtRaw: String?

    init(
        id: String, kind: String? = nil, title: String? = nil, amountPaise: Int? = nil,
        amount: Double? = nil, entryDateRaw: String? = nil, mode: String? = nil,
        reference: String? = nil, category: String? = nil, receiptFile: String? = nil,
        notes: String? = nil, createdAtRaw: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.amountPaise = amountPaise
        self.amount = amount
        self.entryDateRaw = entryDateRaw
        self.mode = mode
        self.reference = reference
        self.category = category
        self.receiptFile = receiptFile
        self.notes = notes
        self.createdAtRaw = createdAtRaw
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, amount, mode, reference, category, notes
        case amountPaise = "amount_paise"
        case entryDateRaw = "entry_date"
        case receiptFile = "receipt_file"
        case createdAtRaw = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.wireID(.id), kind: c.wireString(.kind), title: c.wireString(.title),
            amountPaise: c.wireInt(.amountPaise), amount: c.wireDouble(.amount),
            entryDateRaw: c.wireString(.entryDateRaw), mode: c.wireString(.mode),
            reference: c.wireString(.reference), category: c.wireString(.category),
            receiptFile: c.wireString(.receiptFile), notes: c.wireString(.notes),
            createdAtRaw: c.wireString(.createdAtRaw))
    }

    /// The entry, as the ledger port reads it.
    var ledgerEntry: Ledger.Entry {
        Ledger.Entry(
            id: id, kind: kind ?? "", title: title, amountPaise: amountPaise, amount: amount,
            entryDate: entryDateRaw, createdAt: createdAtRaw, mode: mode, reference: reference,
            category: category, receiptFile: receiptFile, notes: notes)
    }

    /// The figure in paise: the stored paise, else the rupees converted (`paiseOf`).
    var paise: Int { Ledger.paise(of: ledgerEntry) }
}

/// A person on the matter: the client, the other side, counsel, the bench, a witness.
struct ProjectPerson: Codable, Equatable, Identifiable, Sendable {
    let id: String
    /// `MatterVocabulary.PeopleRole`.
    var role: String?
    var name: String?
    var phone: String?
    var email: String?
    var address: String?
    var notes: String?
    var createdAtRaw: String?

    init(
        id: String, role: String? = nil, name: String? = nil, phone: String? = nil,
        email: String? = nil, address: String? = nil, notes: String? = nil, createdAtRaw: String? = nil
    ) {
        self.id = id
        self.role = role
        self.name = name
        self.phone = phone
        self.email = email
        self.address = address
        self.notes = notes
        self.createdAtRaw = createdAtRaw
    }

    enum CodingKeys: String, CodingKey {
        case id, role, name, phone, email, address, notes
        case createdAtRaw = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.wireID(.id), role: c.wireString(.role), name: c.wireString(.name),
            phone: c.wireString(.phone), email: c.wireString(.email),
            address: c.wireString(.address), notes: c.wireString(.notes),
            createdAtRaw: c.wireString(.createdAtRaw))
    }
}

/// The ledger's sums, in rupees, as the server totals them. Any field may be missing.
struct ProjectTotals: Codable, Equatable, Sendable {
    var billed: Double?
    var received: Double?
    var outstanding: Double?
    var expenses: Double?

    init(billed: Double? = nil, received: Double? = nil, outstanding: Double? = nil, expenses: Double? = nil) {
        self.billed = billed
        self.received = received
        self.outstanding = outstanding
        self.expenses = expenses
    }

    enum CodingKeys: String, CodingKey { case billed, received, outstanding, expenses }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            billed: c.wireDouble(.billed), received: c.wireDouble(.received),
            outstanding: c.wireDouble(.outstanding), expenses: c.wireDouble(.expenses))
    }

    /// These totals over a fallback summed from the ledger: the server's figure wins wherever it
    /// sent one, as the web's Fees section merges them.
    func over(_ fallback: MatterRules.LedgerTotals) -> MatterRules.LedgerTotals {
        MatterRules.LedgerTotals(
            billed: billed ?? fallback.billed, received: received ?? fallback.received,
            outstanding: outstanding ?? fallback.outstanding, expenses: expenses ?? fallback.expenses)
    }
}

// MARK: - Envelopes

struct ProjectListResponse: Decodable, Sendable {
    var success: Bool?
    var projects: [Project]?
    var error: String?

    enum CodingKeys: String, CodingKey { case success, projects, error }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try? c.decodeIfPresent(Bool.self, forKey: .success)
        projects = (try? c.decodeIfPresent(LossyList<Project>.self, forKey: .projects))?.flatMap(\.elements)
        error = c.wireString(.error)
    }
}

/// `GET /project`: the matter and everything hanging off it.
///
/// - Important: `courtHistory` and `linkedCase` are camelCase on the wire — built in JavaScript,
///   not selected from a column — while every row inside them is snake_case.
struct ProjectDetailResponse: Decodable, Sendable {
    var success: Bool?
    var project: Project?
    var updates: [ProjectUpdate]?
    var chats: [ProjectChat]?
    var courtHistory: [CourtHistoryItem]?
    var linkedCase: LinkedCase?
    var tasks: [ProjectTask]?
    var ledger: [LedgerEntry]?
    var people: [ProjectPerson]?
    var totals: ProjectTotals?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case success, project, updates, chats, courtHistory, linkedCase, tasks, ledger, people, totals, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try? c.decodeIfPresent(Bool.self, forKey: .success)
        // The matter itself is the one thing that must decode — a broken row is a broken answer.
        project = try c.decodeIfPresent(Project.self, forKey: .project)
        updates = c.wireList(.updates)
        chats = c.wireList(.chats)
        courtHistory = c.wireList(.courtHistory)
        linkedCase = (try? c.decodeIfPresent(LinkedCase.self, forKey: .linkedCase)) ?? nil
        tasks = c.wireList(.tasks)
        ledger = c.wireList(.ledger)
        people = c.wireList(.people)
        totals = (try? c.decodeIfPresent(ProjectTotals.self, forKey: .totals)) ?? nil
        error = c.wireString(.error)
    }
}

// MARK: - Tolerant decoding

/// A list decoded one element at a time: an element that does not decode is dropped, and the
/// rest stand.
struct LossyList<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var out: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                out.append(element)
            } else {
                // Step over the element whatever it is, or the loop would never advance.
                _ = try? container.decode(JSONValue.self)
            }
        }
        elements = out
    }
}

extension KeyedDecodingContainer {
    /// Text, a number as text, or nil — never a throw.
    func wireString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let n = try? decodeIfPresent(Double.self, forKey: key) {
            return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        }
        return nil
    }

    /// A whole number, a numeric string, or nil.
    func wireInt(_ key: Key) -> Int? {
        if let n = try? decodeIfPresent(Int.self, forKey: key) { return n }
        if let d = try? decodeIfPresent(Double.self, forKey: key), d.isFinite, abs(d) < 1e15 {
            return Int(d.rounded())
        }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            return Int(s.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// A number, a numeric string, or nil.
    func wireDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key), d.isFinite { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            return Double(s.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// A row's id, text or number; a missing one fails the row (and only the row).
    func wireID(_ key: Key) throws -> String {
        guard let id = wireString(key), !id.isEmpty else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "No id"))
        }
        return id
    }

    /// A JSON value kept as text: a string as written, anything else re-encoded.
    func wireJSONText(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        guard let value = (try? decodeIfPresent(JSONValue.self, forKey: key)) ?? nil, value != .null,
              let data = try? JSONEncoder().encode(value) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// A list, element by element; nil when the key is missing or not a list.
    func wireList<T: Decodable>(_ key: Key) -> [T]? {
        (try? decodeIfPresent(LossyList<T>.self, forKey: key))?.flatMap(\.elements)
    }
}
