import Foundation

/// What the feedback is about — the web's six chips (`CATEGORIES` in
/// `src/components/feedback/DraftFeedbackButton.jsx`). The label is the wire value: the web sends
/// the words themselves in `categories`, so a reviewer's queue reads the same from either client.
enum DraftFeedbackCategory: String, CaseIterable, Identifiable, Sendable {
    case formatting = "Formatting"
    case accuracy = "Accuracy"
    case structure = "Structure"
    case citations = "Citations"
    case annexures = "Annexures"
    case other = "Other"

    var id: String { rawValue }
    var label: String { rawValue }
}

/// Thumbs up or down. The only two values the route keeps; anything else is stored as no rating.
enum DraftFeedbackRating: String, CaseIterable, Identifiable, Sendable {
    case up, down

    var id: String { rawValue }

    /// The web's button words.
    var label: String {
        switch self {
        case .up: return "Good"
        case .down: return "Needs work"
        }
    }

    var systemImage: String {
        switch self {
        case .up: return "hand.thumbsup"
        case .down: return "hand.thumbsdown"
        }
    }
}

/// One piece of feedback, as `POST /draft-feedback` takes it.
struct DraftFeedback: Equatable, Sendable {
    var chatID: String?
    /// The saved draft's id where this client knows it. It does not, today: a chat's drafts are
    /// saved server-side under ids this client never receives, so it is sent as null and the
    /// reviewer finds the draft by the conversation and the text sent with it.
    var documentID: String?
    var documentTitle: String
    var rating: DraftFeedbackRating?
    var categories: [DraftFeedbackCategory]
    var comment: String
    /// The drafted document's HTML, exactly as rated — or nil when there is no draft.
    var docHTML: String?

    /// The route's own rule: a rating or a comment. Categories alone are not enough.
    var canSubmit: Bool {
        rating != nil || !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The seam the feedback sheet is built against.
protocol FeedbackProviding: Sendable {
    /// Sends it. Returns the stored row's id when the server gives one.
    @discardableResult
    func send(_ feedback: DraftFeedback) async throws -> Int?
}

/// `POST /draft-feedback` — feedback on a drafted document, table or answer, as the web's
/// `DraftFeedbackButton` sends it.
///
/// ## The draft's text is sent
///
/// The web sends the draft's HTML with every piece of feedback — "a complaint always arrives with
/// the exact output it is about" — and this client now does the same whenever the feedback is
/// about a draft. A plain answer with no draft sends only the conversation id, as before. The
/// sheet says which, before the tap (`DraftFeedbackViewModel.privacyNote`).
///
/// The server keeps up to 5,000 characters of comment and 500 KB of HTML and trims the rest
/// rather than refusing it; both are capped here first, so nothing is uploaded only to be cut.
///
/// ## Contract (`sync-server.js`, the `/draft-feedback` POST)
///
/// Body `{userId, chatId, documentId, documentTitle, rating: 'up'|'down'|null, categories,
/// comment, docHtml}`. 200 `{ok: true, id}`; 400 `{ok: false, error: 'Pick a rating or write a
/// comment'}` when there is neither; 500 `{ok: false, error}`.
struct FeedbackService: FeedbackProviding {
    static let commentLimit = 5_000
    /// 500 KB, counted as the server counts it — in UTF-16 units of a JavaScript string.
    static let htmlLimit = 500 * 1024

    let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    /// Every key is always sent, null where there is nothing: the web's body has the same shape.
    private struct Payload: Encodable {
        let userId: String?
        let chatId: String?
        let documentId: String?
        let documentTitle: String
        let rating: String?
        let categories: [String]
        let comment: String
        let docHtml: String

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(userId, forKey: .userId)
            try c.encode(chatId, forKey: .chatId)
            try c.encode(documentId, forKey: .documentId)
            try c.encode(documentTitle, forKey: .documentTitle)
            try c.encode(rating, forKey: .rating)
            try c.encode(categories, forKey: .categories)
            try c.encode(comment, forKey: .comment)
            try c.encode(docHtml, forKey: .docHtml)
        }

        enum CodingKeys: String, CodingKey {
            case userId, chatId, documentId, documentTitle, rating, categories, comment, docHtml
        }
    }

    private struct Body: Decodable {
        var ok: Bool?
        var id: Int?
        var error: String?
    }

    /// The comment as sent: trimmed, then cut to the server's limit.
    static func cappedComment(_ comment: String) -> String {
        String(comment.trimmingCharacters(in: .whitespacesAndNewlines).prefix(commentLimit))
    }

    /// The HTML as sent: at most `htmlLimit` UTF-16 units, on a character boundary.
    static func cappedHTML(_ html: String?) -> String {
        guard let html, html.utf16.count > htmlLimit else { return html ?? "" }
        var end = html.utf16.index(html.utf16.startIndex, offsetBy: htmlLimit)
        while end > html.startIndex, String.Index(end, within: html) == nil {
            end = html.utf16.index(before: end)
        }
        return String(html[..<end])
    }

    @discardableResult
    func send(_ feedback: DraftFeedback) async throws -> Int? {
        // Sent alongside the bearer token, not instead of it; the route prefers the verified
        // identity.
        let request = try await client.makeRequest(
            "POST", "/draft-feedback",
            body: Payload(
                userId: await client.currentCredentials()?.userIDString,
                chatId: feedback.chatID,
                documentId: feedback.documentID,
                documentTitle: feedback.documentTitle,
                rating: feedback.rating?.rawValue,
                categories: feedback.categories.map(\.rawValue),
                comment: Self.cappedComment(feedback.comment),
                docHtml: Self.cappedHTML(feedback.docHTML)))

        // A refusal is a 400 carrying `ok: false` and the reason, which `send` surfaces. A 2xx
        // is still read for `ok`: "sent" is only ever what the server said it stored.
        let body = try await client.send(request, as: Body.self)
        guard body.ok == true else {
            throw APIError.server(status: 200, message: body.error ?? "Your feedback could not be sent.")
        }
        return body.id
    }
}

// MARK: - Support feedback and bug reports

/// What a support message is. Closed to these two: anything else is filed as feedback, so a
/// third value would land somewhere a reviewer does not look.
enum SupportFeedbackKind: String, CaseIterable, Identifiable, Sendable {
    case bug
    case feedback

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bug: return "Report a bug"
        case .feedback: return "Send feedback"
        }
    }
}

/// One already-compressed image attached to a support message.
struct SupportScreenshot: Equatable, Sendable {
    let data: Data
    let fileName: String
    let mimeType: String

    init(data: Data, fileName: String = "screenshot.jpg", mimeType: String = "image/jpeg") {
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
    }
}

enum SupportFeedbackLimits {
    /// The request body is refused above 60 MB. Screenshots are compressed far below that, so
    /// this count is what keeps a message comfortably inside it.
    static let maxScreenshots = 5
    static let screenshotTargetBytes = 500 * 1024
}

enum SupportFeedbackError: LocalizedError, Equatable {
    case emptyDescription
    case tooLarge
    case tooManyScreenshots

    var errorDescription: String? {
        switch self {
        case .emptyDescription:
            return "Please describe what happened before sending."
        case .tooLarge:
            return "The screenshots are too large to send. Remove some and try again."
        case .tooManyScreenshots:
            return "You can attach up to \(SupportFeedbackLimits.maxScreenshots) screenshots."
        }
    }
}

/// The seam the support form is built against.
protocol SupportFeedbackSubmitting: Sendable {
    func submitSupportFeedback(
        kind: SupportFeedbackKind, description: String, screenshots: [SupportScreenshot],
        pageURL: String
    ) async throws
}

extension SupportFeedbackSubmitting {
    func submitSupportFeedback(
        kind: SupportFeedbackKind, description: String, screenshots: [SupportScreenshot] = []
    ) async throws {
        try await submitSupportFeedback(
            kind: kind, description: description, screenshots: screenshots, pageURL: "ios:settings")
    }
}

/// `POST /support-feedback`: a multipart message with optional screenshots.
extension FeedbackService: SupportFeedbackSubmitting {

    /// Screenshots go in as `file_<i>` parts, each with a `filename` — a part without one is
    /// read as a plain text field and dropped.
    static func supportBody(
        kind: SupportFeedbackKind, description: String, userID: String?, pageURL: String,
        screenshots: [SupportScreenshot], boundary: String
    ) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        var fields: [(String, String)] = [("description", description)]
        if let userID { fields.append(("userId", userID)) }
        fields.append(("kind", kind.rawValue))
        fields.append(("pageUrl", pageURL))
        for (name, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        for (index, shot) in screenshots.enumerated() {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"file_\(index)\"; filename=\"\(shot.fileName)\"\r\n")
            append("Content-Type: \(shot.mimeType)\r\n\r\n")
            body.append(shot.data)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")
        return body
    }

    /// 413 is the size limit; otherwise the body's `error` string is what the user reads,
    /// because statuses on this API are not reliable on their own.
    static func supportError(status: Int, data: Data) -> Error {
        if status == 413 { return SupportFeedbackError.tooLarge }
        let message = (try? JSONDecoder().decode(Body.self, from: data))?.error
        if message == "Description is required" { return SupportFeedbackError.emptyDescription }
        return APIError.server(
            status: status, message: message ?? "Your message could not be sent.")
    }

    func submitSupportFeedback(
        kind: SupportFeedbackKind, description: String, screenshots: [SupportScreenshot],
        pageURL: String
    ) async throws {
        try await submitSupportFeedback(
            kind: kind, description: description, screenshots: screenshots, pageURL: pageURL,
            boundary: MultipartChunk.boundary())
    }

    func submitSupportFeedback(
        kind: SupportFeedbackKind, description: String, screenshots: [SupportScreenshot],
        pageURL: String, boundary: String
    ) async throws {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SupportFeedbackError.emptyDescription }
        guard screenshots.count <= SupportFeedbackLimits.maxScreenshots else {
            throw SupportFeedbackError.tooManyScreenshots
        }

        // A signed-out visitor may still report, so auth is optional; when signed in, the bearer
        // token names the sender and the id is sent alongside it.
        var request = try await client.makeRequest("POST", "/support-feedback", requiresAuth: false)
        request.setValue(
            MultipartChunk.contentType(boundary: boundary), forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.supportBody(
            kind: kind, description: trimmed,
            userID: await client.currentCredentials()?.userIDString,
            pageURL: pageURL, screenshots: screenshots, boundary: boundary)

        let (data, response) = try await client.perform(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Self.supportError(status: response.statusCode, data: data)
        }
    }
}
