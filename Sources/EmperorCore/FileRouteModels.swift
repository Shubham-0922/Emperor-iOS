import Foundation

// Wire types for the small file routes: saving an edited draft, a folder as one archive, a
// document's extracted text, a server-rendered PDF, the account's starting model, and the
// maintenance notice. See `FileRouteService`.

/// The body of `POST /save-document`.
///
/// Sent with the row's own id, `type` and `chat_id`: the server replaces the row with that id
/// when it is the caller's, and writes the chat id and source it is sent — so leaving either out
/// would move the draft out of its conversation (`lib/canvasStore.js`).
struct SaveDocumentRequest: Encodable, Equatable, Sendable {
    let userId: String
    let id: String
    let title: String
    let content: String
    let type: String
    let source: String
    /// Left out when the row has none; the server then files it under the account's own drafts.
    let chatId: String?
}

/// What `POST /save-document` answers.
///
/// `id` is the row that now holds the content — the one sent, or another when the same content
/// was already saved in that conversation (`deduped`) or the id was not the caller's. Always
/// adopt it.
struct SaveDocumentResult: Decodable, Equatable, Sendable {
    let success: Bool?
    let id: String?
    let type: String?
    let deduped: Bool?
    let reclassified: Bool?
    let error: String?
}

/// One document in a `POST /download-files` archive. The storage root is spelled `"."`.
struct ZipEntry: Encodable, Equatable, Sendable {
    let folderName: String
    let fileName: String
}

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

/// The paper a server-rendered PDF is laid out on, in millimetres — the web's
/// `DEFAULT_PAGE_SETUP` (`src/lib/pageSetup.js`), held to it by a golden fixture.
struct PageSetup: Encodable, Equatable, Sendable {
    var size = "a4"
    var orientation = "portrait"
    var margins = Margins()

    struct Margins: Encodable, Equatable, Sendable {
        var top = 25.0
        var right = 20.0
        var bottom = 25.0
        var left = 25.0
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
