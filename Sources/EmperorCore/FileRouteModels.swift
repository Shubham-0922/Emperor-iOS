import Foundation

// Wire types for `/file-text` and `/maintenance`. See `FileRouteService`.

/// What `GET /file-text` answers: the text read out of a document when it was uploaded, one
/// entry per page as the extractor found it.
struct FileTextResponse: Decodable, Equatable, Sendable {
    let success: Bool?
    let fileName: String?
    /// `false` when the document itself is missing from storage.
    let fileExists: Bool?
    let totalPages: Int?
    /// `"name"` when the text was found by file name alone, so it may belong to another copy.
    let matchedBy: String?
    /// Only the first pages are here; the rest were left out for size.
    let truncated: Bool?
    let pages: [Page]?
    let error: String?

    struct Page: Decodable, Equatable, Sendable {
        /// The extractor's own page number — never an index into `pages`.
        let page: Int
        let content: String
    }
}

/// What `GET /maintenance` answers. Only `active` decides anything: it is `true` when the
/// platform is down for this caller.
struct MaintenanceState: Decodable, Equatable, Sendable {
    let enabled: Bool?
    let active: Bool?
    let bypass: Bool?
    /// What the operator wrote — usually when it will be back.
    let message: String?
    let since: String?

    init(
        enabled: Bool? = nil, active: Bool? = nil, bypass: Bool? = nil,
        message: String? = nil, since: String? = nil
    ) {
        self.enabled = enabled
        self.active = active
        self.bypass = bypass
        self.message = message
        self.since = since
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, active, bypass, message, since
    }

    /// Read leniently: a field of an unexpected type is left out rather than failing the read.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try? c.decodeIfPresent(Bool.self, forKey: .enabled)
        active = try? c.decodeIfPresent(Bool.self, forKey: .active)
        bypass = try? c.decodeIfPresent(Bool.self, forKey: .bypass)
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        since = try? c.decodeIfPresent(String.self, forKey: .since)
    }
}
