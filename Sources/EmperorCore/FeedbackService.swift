import Foundation

/// Why an answer is being reported.
///
/// A fixed list rather than free text alone, because a reviewer triaging a queue needs to sort
/// it, and because naming the categories tells a user what this channel is for. `wire` is what
/// goes into the route's `categories` array — lowercase and stable, so a label can be reworded
/// without orphaning every report already in the table.
enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case wrongLaw = "wrong-law"
    case fabricatedCitation = "fabricated-citation"
    case harmful
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wrongLaw: return "The law is wrong"
        case .fabricatedCitation: return "A citation does not exist"
        case .harmful: return "Harmful or offensive"
        case .other: return "Something else"
        }
    }
}

/// The seam the report sheet is built against.
protocol FeedbackProviding: Sendable {
    func reportAnswer(chatID: String?, reason: ReportReason, comment: String) async throws
}

/// `POST /draft-feedback`, used as the in-app report channel.
///
/// ## Why this route rather than a new one
///
/// Both stores require a way to report AI-generated content, and this app had none. The route
/// already exists, already writes to a table an admin screen already reads, and — unusually for
/// this server — already resolves identity properly, preferring the verified token over the
/// client-supplied id. A parallel endpoint would mean a second queue nobody reads.
///
/// ## The answer's text is deliberately not sent
///
/// The route accepts `docHtml` up to 500 KB and it is left empty. The reported answer is already
/// stored server-side against `chatID`; sending it again would copy client material — which on
/// this platform means privileged legal content — into a second table for no reviewer benefit.
/// The chat id is what lets a reviewer find it.
struct FeedbackService: FeedbackProviding {
    /// The server truncates rather than rejects, so an uncapped field loses its tail silently.
    /// Capped here, where the sheet can say so before the tap.
    static let commentLimit = 5_000

    let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    private struct Payload: Encodable {
        let userId: String?
        let chatId: String?
        let documentTitle: String
        /// `up` or `down` only — anything else is coerced to null server-side, and a null
        /// rating with an empty comment is a 400.
        let rating: String
        let categories: [String]
        let comment: String
    }

    private struct Body: Decodable {
        var ok: Bool?
        var id: Int?
        var error: String?
    }

    func reportAnswer(chatID: String?, reason: ReportReason, comment: String) async throws {
        let trimmed = String(
            comment.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(Self.commentLimit))
        // Sent alongside the bearer token, not instead of it. This route already prefers the
        // verified identity; the id is here so the client keeps working unchanged once the rest
        // of the server is hardened the same way.
        let request = try await client.makeRequest(
            "POST", "/draft-feedback",
            body: Payload(
                userId: await client.currentCredentials()?.userIDString,
                chatId: chatID,
                documentTitle: "Reported from iOS",
                rating: "down",
                categories: [reason.rawValue],
                comment: trimmed))

        // - Important: this route answers **200 with `ok: false`** when it rejects, rather than
        //   a 4xx. Trusting the status code would report every rejection as a success and the
        //   user would believe a report had been filed that was not.
        let (data, response) = try await client.perform(request)
        let body = try? JSONDecoder().decode(Body.self, from: data)
        guard (200..<300).contains(response.statusCode), body?.ok == true else {
            throw APIError.server(
                status: response.statusCode,
                message: body?.error ?? "The report could not be sent.")
        }
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
