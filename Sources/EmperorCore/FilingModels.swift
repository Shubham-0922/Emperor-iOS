import Foundation

// The wire shapes of filing assembly (`/filing/*`): saved drafts, the annexures registered
// against one, the cover page, the assembler's answer, and the bundles it has made.

/// A saved draft that can be assembled into a filing (`GET /filing/drafts`).
///
/// Its own type rather than `DraftedItem`: this route names the chat `chat_id` and carries no
/// chat title. `created_at` is an ISO timestamp or SQLite's zoneless one.
struct FilingDraft: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var title: String?
    /// `"doc"` or `"table"`.
    var type: String?
    var createdAtRaw: String?
    /// The chat the draft was written in. Sent back with every annexure read, so annexures the
    /// chat cited are listed with the draft's own.
    var chatID: String?

    enum CodingKeys: String, CodingKey {
        case id, title, type
        case createdAtRaw = "created_at"
        case chatID = "chat_id"
    }

    var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Untitled draft" : trimmed
    }

    var createdAt: Date? { WireDate.parseAny(createdAtRaw) }
}

/// How an annexure goes into the bundle: its own pages, or a typed true copy made from its text.
enum FilingTreatment: String, Codable, CaseIterable, Sendable {
    case append
    case typed

    var title: String {
        switch self {
        case .append: return "Original"
        case .typed: return "Typed copy"
        }
    }
}

/// Whether a person has checked a typed copy against its original.
enum FilingVerify: String, Codable, Sendable {
    case notApplicable = "n/a"
    case pending
    case verified
}

/// One annexure registered against a draft or a chat (a row of the server's annexure table).
///
/// Its mark (`P-1`, `R-2`) is the server's and sticky: deleting or reordering never renumbers.
struct FilingAnnexure: Codable, Identifiable, Equatable, Sendable {
    var id: Int
    var draftID: String?
    var chatID: String?
    var mark: String
    var title: String
    /// Where the source lives on the server. Only its last component is ever shown.
    var sourceFilePath: String
    /// `"append"` or `"typed"`.
    var treatment: String
    var sortOrder: Int?
    /// `"n/a"`, `"pending"` or `"verified"`.
    var verifyStatus: String
    /// The pages this annexure occupies in the last bundle, once one has been assembled.
    var pageFrom: Int?
    var pageTo: Int?
    /// Epoch milliseconds.
    var createdAt: Int?
    /// The earlier mark citing the same file and pages, when there is one.
    var duplicateOf: String?

    enum CodingKeys: String, CodingKey {
        case id, mark, title, treatment
        case draftID = "draft_id"
        case chatID = "chat_id"
        case sourceFilePath = "source_file_path"
        case sortOrder = "sort_order"
        case verifyStatus = "verify_status"
        case pageFrom = "page_from"
        case pageTo = "page_to"
        case createdAt = "created_at"
        case duplicateOf = "duplicate_of"
    }

    init(
        id: Int, draftID: String? = nil, chatID: String? = nil, mark: String, title: String,
        sourceFilePath: String = "", treatment: String = FilingTreatment.append.rawValue,
        sortOrder: Int? = nil, verifyStatus: String = FilingVerify.notApplicable.rawValue,
        pageFrom: Int? = nil, pageTo: Int? = nil, createdAt: Int? = nil, duplicateOf: String? = nil
    ) {
        self.id = id
        self.draftID = draftID
        self.chatID = chatID
        self.mark = mark
        self.title = title
        self.sourceFilePath = sourceFilePath
        self.treatment = treatment
        self.sortOrder = sortOrder
        self.verifyStatus = verifyStatus
        self.pageFrom = pageFrom
        self.pageTo = pageTo
        self.createdAt = createdAt
        self.duplicateOf = duplicateOf
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        draftID = try c.decodeIfPresent(String.self, forKey: .draftID)
        chatID = try c.decodeIfPresent(String.self, forKey: .chatID)
        mark = try c.decodeIfPresent(String.self, forKey: .mark) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        sourceFilePath = try c.decodeIfPresent(String.self, forKey: .sourceFilePath) ?? ""
        treatment = try c.decodeIfPresent(String.self, forKey: .treatment)
            ?? FilingTreatment.append.rawValue
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder)
        verifyStatus = try c.decodeIfPresent(String.self, forKey: .verifyStatus)
            ?? FilingVerify.notApplicable.rawValue
        pageFrom = try c.decodeIfPresent(Int.self, forKey: .pageFrom)
        pageTo = try c.decodeIfPresent(Int.self, forKey: .pageTo)
        createdAt = try c.decodeIfPresent(Int.self, forKey: .createdAt)
        duplicateOf = try c.decodeIfPresent(String.self, forKey: .duplicateOf)
    }

    /// The source's file name, without the server's path.
    var fileName: String {
        sourceFilePath.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init)
            ?? sourceFilePath
    }

    /// "pp. 3–7" once assembly has placed it, else `nil`.
    var pageRangeLabel: String? {
        guard let pageFrom, let pageTo else { return nil }
        return "pp. \(pageFrom)–\(pageTo)"
    }

    var isTyped: Bool { treatment == FilingTreatment.typed.rawValue }
    var isVerified: Bool { verifyStatus == FilingVerify.verified.rawValue }
    /// A typed copy nobody has checked yet.
    var isPendingVerification: Bool { isTyped && verifyStatus == FilingVerify.pending.rawValue }

    /// The caption under the title: the file, and the pages once placed.
    var caption: String {
        [fileName, pageRangeLabel].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The cover page's details, as the assembler reads them.
struct FilingCover: Codable, Equatable, Sendable {
    var forum = ""
    var caseType = ""
    var caseNumber = ""
    var parties = ""
    var filingType = ""

    init(
        forum: String = "", caseType: String = "", caseNumber: String = "", parties: String = "",
        filingType: String = ""
    ) {
        self.forum = forum
        self.caseType = caseType
        self.caseNumber = caseNumber
        self.parties = parties
        self.filingType = filingType
    }
}

/// What must be in a filing before it is filed, for one forum.
struct FilingChecklist: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Identifiable, Sendable {
        var id: String
        var label: String
        /// `"ai"`, `"assembled"` or `"human"`.
        var kind: String
        /// `"ok"`, `"missing"`, `"attention"`, `"auto"` or `"manual"`.
        var status: String
        var note: String?
    }

    var forum: String
    var items: [Item]
    var blockers: [String]
    var attention: [String]

    init(forum: String, items: [Item], blockers: [String] = [], attention: [String] = []) {
        self.forum = forum
        self.items = items
        self.blockers = blockers
        self.attention = attention
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        forum = try c.decodeIfPresent(String.self, forKey: .forum) ?? ""
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        blockers = try c.decodeIfPresent([String].self, forKey: .blockers) ?? []
        attention = try c.decodeIfPresent([String].self, forKey: .attention) ?? []
    }

    /// The items under the page's three headings, in its order, leaving out an empty heading.
    /// An item of a kind the page does not know goes under "Assembled by system", as there.
    var groups: [Group] {
        FilingChecklistTone.kinds.compactMap { kind in
            let members = items.filter {
                (FilingChecklistTone.kinds.contains($0.kind) ? $0.kind : "assembled") == kind
            }
            return members.isEmpty
                ? nil
                : Group(kind: kind, title: FilingChecklistTone.groupTitle(kind: kind), items: members)
        }
    }

    /// One of the page's headings and the items under it.
    struct Group: Identifiable, Equatable, Sendable {
        var kind: String
        var title: String
        var items: [Item]
        var id: String { kind }
    }
}

/// The assembler's answer (`POST /filing/assemble`). Failure arrives as a 200 too, with
/// `success: false` and every problem listed — decoded, never thrown.
struct FilingAssemblyResult: Decodable, Equatable, Sendable {
    struct IndexRow: Codable, Equatable, Sendable {
        var label: String
        var folio: Int
    }

    struct Range: Codable, Equatable, Sendable {
        var mark: String
        var from: Int
        var to: Int
    }

    struct Verify: Codable, Equatable, Sendable {
        var ok: Bool
        var entriesChecked: Int
        var mismatches: [JSONValue]

        init(ok: Bool, entriesChecked: Int, mismatches: [JSONValue] = []) {
            self.ok = ok
            self.entriesChecked = entriesChecked
            self.mismatches = mismatches
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
            entriesChecked = try c.decodeIfPresent(Int.self, forKey: .entriesChecked) ?? 0
            mismatches = try c.decodeIfPresent([JSONValue].self, forKey: .mismatches) ?? []
        }
    }

    var success: Bool
    var bundleId: Int?
    var pageCount: Int?
    var index: [IndexRow]?
    var annexures: [Range]?
    var checklist: FilingChecklist?
    var warnings: [String]?
    var verify: Verify?
    /// Every problem, as the server worded it — strings, or objects carrying a message.
    var errors: [JSONValue]?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case success, bundleId, pageCount, index, annexures, checklist, warnings, verify, errors, error
    }

    init(
        success: Bool, bundleId: Int? = nil, pageCount: Int? = nil, index: [IndexRow]? = nil,
        annexures: [Range]? = nil, checklist: FilingChecklist? = nil, warnings: [String]? = nil,
        verify: Verify? = nil, errors: [JSONValue]? = nil, error: String? = nil
    ) {
        self.success = success
        self.bundleId = bundleId
        self.pageCount = pageCount
        self.index = index
        self.annexures = annexures
        self.checklist = checklist
        self.warnings = warnings
        self.verify = verify
        self.errors = errors
        self.error = error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        bundleId = try c.decodeIfPresent(Int.self, forKey: .bundleId)
        pageCount = try c.decodeIfPresent(Int.self, forKey: .pageCount)
        index = try c.decodeIfPresent([IndexRow].self, forKey: .index)
        annexures = try c.decodeIfPresent([Range].self, forKey: .annexures)
        checklist = try? c.decodeIfPresent(FilingChecklist.self, forKey: .checklist)
        // A warning is a sentence; anything else is shown as the page would show it.
        warnings = (try c.decodeIfPresent([JSONValue].self, forKey: .warnings))?
            .map { $0.stringValue ?? Self.text(of: $0) }
        verify = try? c.decodeIfPresent(Verify.self, forKey: .verify)
        // `errors` may be one value rather than a list, and `error` an object; both are read as
        // the page reads them (`errorList`).
        let rawErrors = try c.decodeIfPresent(JSONValue.self, forKey: .errors)
        let rawError = try c.decodeIfPresent(JSONValue.self, forKey: .error)
        error = rawError?.stringValue
        switch rawErrors {
        case .array(let list): errors = list
        case .none, .some(.null): errors = nil
        case .some(let one): errors = [one]
        }
        if errors == nil, let rawError, rawError != .null, rawError.stringValue == nil {
            errors = [rawError]
        }
    }

    static let unknownError = "Unknown assembly error"

    /// Every problem as a line of text, as the page's `errorList` flattens them: a string as it
    /// is, an object by its `message` or `error`, anything else as JSON; empty lines dropped.
    var errorList: [String] {
        let raw: [JSONValue]
        if let errors { raw = errors } else if let error { raw = [.string(error)] } else { raw = [] }
        return raw.map(Self.line(for:)).filter { !$0.isEmpty }
    }

    /// `errorList`, or the page's one line when the server gave none.
    var errorLines: [String] {
        let lines = errorList
        return lines.isEmpty ? [Self.unknownError] : lines
    }

    /// "Bundle assembled — 42 pages".
    var successTitle: String { "Bundle assembled — \(pageCount ?? 0) pages" }

    /// "Verified: 12 index entries checked against the final PDF", or `nil` with no check.
    var verifyLine: String? {
        guard let verify else { return nil }
        return "Verified: \(verify.entriesChecked) index entries checked against the final PDF"
            + (verify.ok ? "" : " — with mismatches")
    }

    private static func line(for value: JSONValue) -> String {
        if case .string(let s) = value { return s }
        if case .object = value {
            if let message = value["message"], isTruthy(message) { return text(ofTruthy: message) }
            if let error = value["error"], isTruthy(error) { return text(ofTruthy: error) }
        }
        return text(of: value)
    }

    private static func isTruthy(_ value: JSONValue) -> Bool {
        switch value {
        case .null: return false
        case .bool(let b): return b
        case .number(let n): return n != 0 && !n.isNaN
        case .string(let s): return !s.isEmpty
        case .array, .object: return true
        }
    }

    private static func text(ofTruthy value: JSONValue) -> String {
        value.stringValue ?? text(of: value)
    }

    /// The value as `JSON.stringify` would write it.
    static func text(of value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if case .number(let n) = value, n == n.rounded(), abs(n) < 1e15 {
            return String(Int64(n))
        }
        guard let data = try? encoder.encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// One assembled bundle (`GET /filing/bundles`).
struct FilingBundle: Codable, Identifiable, Equatable, Sendable {
    var id: Int
    /// The draft's id, or `chat:<id>` for a bundle assembled from a chat.
    var draftID: String
    var pageCount: Int?
    /// `"ok"` or `"failed"`.
    var status: String
    /// Epoch milliseconds.
    var createdAt: Int?

    enum CodingKeys: String, CodingKey {
        case id, status
        case draftID = "draft_id"
        case pageCount = "page_count"
        case createdAt = "created_at"
    }

    init(id: Int, draftID: String, pageCount: Int? = nil, status: String, createdAt: Int? = nil) {
        self.id = id
        self.draftID = draftID
        self.pageCount = pageCount
        self.status = status
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        draftID = try c.decodeIfPresent(String.self, forKey: .draftID) ?? ""
        pageCount = try c.decodeIfPresent(Int.self, forKey: .pageCount)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        createdAt = try c.decodeIfPresent(Int.self, forKey: .createdAt)
    }

    var isReady: Bool { status == "ok" }

    var createdDate: Date? { createdAt.map { Date(timeIntervalSince1970: Double($0) / 1000) } }

    /// "Bundle #7 · 42 pages".
    var title: String {
        ["Bundle #\(id)", pageCount.map { "\($0) pages" }].compactMap { $0 }.joined(separator: " · ")
    }
}

/// What assembling a filing from a chat's draft needs: the chat, the live draft and the files the
/// chat carries. Used where a draft is assembled from its chat rather than picked from the list.
struct FilingChatContext: Equatable, Sendable {
    var chatID: String
    var draftTitle: String
    var draftHTML: String
    var attachments: [ChatAttachment]
}

// MARK: - Envelopes

struct FilingDraftsResponse: Decodable, Sendable {
    var success: Bool?
    var error: String?
    var drafts: [FilingDraft]?
}

struct FilingAnnexuresResponse: Decodable, Sendable {
    var success: Bool?
    var error: String?
    var annexures: [FilingAnnexure]?
}

struct FilingAnnexureResponse: Decodable, Sendable {
    var success: Bool?
    var error: String?
    var annexure: FilingAnnexure?
}

struct FilingReorderResponse: Decodable, Sendable {
    var success: Bool?
    var error: String?
    var orderMatchesMarks: Bool?
    var annexures: [FilingAnnexure]?
}

struct FilingBundlesResponse: Decodable, Sendable {
    var success: Bool?
    var error: String?
    var bundles: [FilingBundle]?
}

struct FilingChecklistResponse: Decodable, Sendable {
    var success: Bool?
    var error: String?
    var checklist: FilingChecklist?
}

struct FilingOKResponse: Decodable, Sendable {
    var success: Bool?
    var error: String?
}
