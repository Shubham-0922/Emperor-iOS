import Foundation

/// The server's own check of a quote against the document it was found in.
enum QuoteStatus: String, Decodable, Sendable {
    case verified
    case mismatch
    case unlocated
    case tooShort = "too_short"
}

/// Which stored document a citation's file name means (`GET /resolve-file`), and on which page
/// its quoted words are.
struct ResolvedFile: Decodable, Equatable, Sendable {
    let found: Bool
    /// The folder, `/`-joined; `"."` is the storage root.
    var folderName: String?
    var fileName: String?
    /// Set only when the server found the quoted words on a page with confidence.
    var page: Int?
    /// The server's verdict as it sent it; `quoteStatus` reads it.
    var quoteStatusRaw: String?

    init(found: Bool, folderName: String? = nil, fileName: String? = nil, page: Int? = nil,
         quoteStatusRaw: String? = nil) {
        self.found = found
        self.folderName = folderName
        self.fileName = fileName
        self.page = page
        self.quoteStatusRaw = quoteStatusRaw
    }

    private enum CodingKeys: String, CodingKey {
        case found, folderName, fileName, page
        case quoteStatusRaw = "quoteStatus"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        found = (try? c.decodeIfPresent(Bool.self, forKey: .found)) ?? false
        folderName = try? c.decodeIfPresent(String.self, forKey: .folderName)
        fileName = try? c.decodeIfPresent(String.self, forKey: .fileName)
        page = try? c.decodeIfPresent(Int.self, forKey: .page)
        quoteStatusRaw = try? c.decodeIfPresent(String.self, forKey: .quoteStatusRaw)
    }

    /// `nil` for no verdict, and for one this client does not know.
    var quoteStatus: QuoteStatus? { quoteStatusRaw.flatMap(QuoteStatus.init(rawValue:)) }

    /// The document to open, when one was found. The folder is kept as the server spells it.
    var attachment: ChatAttachment? {
        guard found, let fileName, !fileName.isEmpty else { return nil }
        return ChatAttachment(name: fileName, folderName: folderName)
    }
}

/// The positioned words of one page of a scanned document (`GET /page-words`).
struct PageWords: Decodable, Sendable {
    enum Status: String, Sendable {
        /// The words are there — or, with none, the page has a text layer of its own.
        case ready
        /// A scanned document whose words are still being placed.
        case pending
        /// Nothing was read from images: the PDF's own text is all there is.
        case none
    }

    var status: Status
    var words: [(text: String, box: QuoteBox)]

    init(status: Status, words: [(text: String, box: QuoteBox)] = []) {
        self.status = status
        self.words = words
    }

    private enum CodingKeys: String, CodingKey { case status, page }
    private enum PageKeys: String, CodingKey { case words }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = Status(rawValue: (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "") ?? .none
        var words: [(text: String, box: QuoteBox)] = []
        if (try? c.decodeNil(forKey: .page)) == false,
           let page = try? c.nestedContainer(keyedBy: PageKeys.self, forKey: .page),
           let raw = try? page.decodeIfPresent([[JSONValue]].self, forKey: .words) {
            for entry in raw {
                // [x0, y0, x1, y1, "text", confidence]; anything else is skipped, not guessed at.
                guard entry.count >= 5, case .string(let text) = entry[4],
                      let x0 = entry[0].doubleValue, let y0 = entry[1].doubleValue,
                      let x1 = entry[2].doubleValue, let y1 = entry[3].doubleValue
                else { continue }
                words.append((text, QuoteBox(x0: x0, y0: y0, x1: x1, y1: y1)))
            }
        }
        self.words = words
    }
}

/// Opening the document a citation names.
protocol CitedSourceResolving: Sendable {
    /// Which stored document `name` means — in the matter `projectID`, when the conversation
    /// belongs to one — and the page `quote` is on.
    func resolve(name: String, quote: String?, projectID: String?) async throws -> ResolvedFile
    /// The placed words of one page of a scanned document.
    func pageWords(folderName: String, fileName: String, page: Int) async throws -> PageWords
}

/// `/resolve-file` and `/page-words`. Stateless. A refusal or a failure — a 4xx with the usual
/// envelope, a 500 carrying only `error` — comes back as `APIError`, worded as the server worded it.
struct CitedSourceService: CitedSourceResolving {
    let client: APIClient

    func resolve(name: String, quote: String?, projectID: String?) async throws -> ResolvedFile {
        var query = ["name": name]
        if let quote, !quote.isEmpty { query["quote"] = quote }
        // In a matter's conversation the cited file is one of that matter's: without its id the
        // server looks only outside every matter, and the file is never found.
        if let projectID, !projectID.isEmpty { query["projectId"] = projectID }
        let request = try await client.makeRequest("GET", "/resolve-file", query: query)
        return try await client.send(request, as: ResolvedFile.self)
    }

    func pageWords(folderName: String, fileName: String, page: Int) async throws -> PageWords {
        let request = try await client.makeRequest(
            "GET", "/page-words",
            query: [
                "folderName": folderName.isEmpty ? "." : folderName,
                "fileName": fileName,
                "page": String(page),
            ])
        return try await client.send(request, as: PageWords.self)
    }
}
