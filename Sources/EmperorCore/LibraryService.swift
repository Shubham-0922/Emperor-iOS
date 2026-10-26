import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The reference library's catalogue: what the screens ask it.
protocol LibraryProviding: Sendable {
    func categories() async throws -> [LibraryCategory]
    func facets(_ category: String) async throws -> LibraryFacets
    func browse(_ filters: LibraryFilters) async throws -> LibraryPage
    /// Title, party and citation matches in every collection at once.
    func titleSearch(q: String, perCategory: Int) async throws -> LibraryGroupedResults
    /// Words inside documents (judgments), with a passage each.
    func searchBodies(_ filters: LibraryFilters) async throws -> LibraryPage
    func searchStatus() async throws -> LibrarySearchIndex
    func actIndex(_ query: LibraryActQuery) async throws -> LibraryActIndexPage
    func act(id: Int) async throws -> LibraryActBundle
    func judgment(id: Int) async throws -> LibraryJudgment
    func shelf(category: String, limit: Int) async throws -> LibraryShelf
    func seriesShelves(limit: Int, per: Int) async throws -> LibrarySeriesShelves
    func doc(id: Int) async throws -> LibraryDocDetail
    /// Whether a document's file is on this server, and how big it is, without fetching it.
    func fileHead(id: Int) async throws -> (status: Int, length: Int?)
    /// A document's bytes. `prefer` is `original` (the default), `html` or `text`.
    func file(id: Int, prefer: String?) async throws -> Data
    func cover(id: Int, width: Int, web: Bool, attempt: Int) async -> LibraryCoverResult
}

/// The catalogue routes, `/library/catalogue/*`.
///
/// Every route reads the caller from the token. Its error bodies carry a code (`not_found`,
/// `catalogue_unavailable`, …) that `LibraryError.from` turns into this client's words; a
/// signed-out answer stays `.invalidCredentials`, so the session ends the usual way.
///
/// The type name and `init(client:)` are what `Session` holds; keep them.
struct LibraryService: LibraryProviding {
    let client: APIClient
    /// How long a busy search waits before its one retry. The server says five seconds.
    var busyRetryDelay: TimeInterval = 5

    init(client: APIClient, busyRetryDelay: TimeInterval = 5) {
        self.client = client
        self.busyRetryDelay = busyRetryDelay
    }

    static let base = "/library/catalogue"

    private func get<T: Decodable & Sendable>(_ path: String, _ query: [String: String] = [:], as type: T.Type) async throws -> T {
        do {
            let request = try await client.makeRequest("GET", Self.base + path, query: query)
            return try await client.send(request, as: T.self)
        } catch {
            throw LibraryError.from(error)
        }
    }

    func categories() async throws -> [LibraryCategory] {
        try await get("/categories", as: LibraryCategoriesResponse.self).categories ?? []
    }

    func facets(_ category: String) async throws -> LibraryFacets {
        try await get("/facets", ["category": category], as: LibraryFacetsResponse.self).facets ?? LibraryFacets()
    }

    func browse(_ filters: LibraryFilters) async throws -> LibraryPage {
        try await get("/browse", filters.query, as: LibraryPage.self)
    }

    func titleSearch(q: String, perCategory: Int) async throws -> LibraryGroupedResults {
        let query = [
            "groupBy": "category", "q": q.trimmingCharacters(in: .whitespacesAndNewlines),
            "pageSize": String(min(max(perCategory, 1), 20)),
        ]
        return try await get("/browse", query, as: LibraryGroupedResults.self)
    }

    func searchBodies(_ filters: LibraryFilters) async throws -> LibraryPage {
        try await LibraryRetry.onceWhenBusy(after: busyRetryDelay) {
            try await get("/search", filters.query, as: LibraryPage.self)
        }
    }

    func searchStatus() async throws -> LibrarySearchIndex {
        try await get("/search-status", as: LibrarySearchStatusResponse.self).index ?? LibrarySearchIndex()
    }

    func actIndex(_ query: LibraryActQuery) async throws -> LibraryActIndexPage {
        try await get("/folders", query.query, as: LibraryActIndexPage.self)
    }

    func act(id: Int) async throws -> LibraryActBundle {
        try await get("/act", ["id": String(id)], as: LibraryActBundle.self)
    }

    func judgment(id: Int) async throws -> LibraryJudgment {
        try await get("/judgment", ["id": String(id)], as: LibraryJudgment.self)
    }

    func shelf(category: String, limit: Int) async throws -> LibraryShelf {
        try await get("/shelf", ["category": category, "limit": String(limit)], as: LibraryShelf.self)
    }

    func seriesShelves(limit: Int, per: Int) async throws -> LibrarySeriesShelves {
        try await get("/shelf", [
            "category": LibraryCategoryKey.books.rawValue, "by": "series",
            "limit": String(limit), "per": String(per),
        ], as: LibrarySeriesShelves.self)
    }

    func doc(id: Int) async throws -> LibraryDocDetail {
        try await get("/doc", ["id": String(id)], as: LibraryDocResponse.self).doc
    }

    func fileHead(id: Int) async throws -> (status: Int, length: Int?) {
        let request = try await client.makeRequest("HEAD", Self.base + "/file", query: ["id": String(id)])
        let (_, response) = try await client.perform(request)
        let header = response.value(forHTTPHeaderField: "Content-Length").flatMap { Int($0) }
        let expected = response.expectedContentLength > 0 ? Int(response.expectedContentLength) : nil
        return (response.statusCode, header ?? expected)
    }

    func file(id: Int, prefer: String?) async throws -> Data {
        var query = ["id": String(id)]
        if let prefer, !prefer.isEmpty { query["prefer"] = prefer }
        let request = try await client.makeRequest("GET", Self.base + "/file", query: query)
        let (data, response) = try await client.perform(request)
        guard (200..<300).contains(response.statusCode) else {
            throw LibraryError.from(APIError.classify(status: response.statusCode, body: data))
        }
        return data
    }

    func cover(id: Int, width: Int, web: Bool, attempt: Int) async -> LibraryCoverResult {
        let query = LibraryCovers.query(id: id, width: width, web: web, attempt: attempt)
        guard let request = try? await client.makeRequest("GET", Self.base + "/cover", query: query),
              let answer = try? await client.perform(request)
        else { return .none }
        return LibraryCovers.result(
            status: answer.1.statusCode, body: answer.0,
            retryAfter: answer.1.value(forHTTPHeaderField: "Retry-After"))
    }
}

/// The library's one retry: a body search the server was too busy for is asked again once.
enum LibraryRetry {
    static func onceWhenBusy<T>(after delay: TimeInterval, _ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch LibraryError.busy {
            try await Task.sleep(nanoseconds: UInt64(max(0, min(delay, 5)) * 1_000_000_000))
            return try await work()
        }
    }
}

/// How a cover is asked for and what its answer means (`Cover.jsx`).
enum LibraryCovers {
    /// The widths the server renders.
    static let widths = [160, 320, 640]

    /// The smallest width that covers `points` at `scale`.
    static func width(forPoints points: Double, scale: Double) -> Int {
        let need = points * scale
        return widths.first { Double($0) >= need } ?? widths[widths.count - 1]
    }

    /// Built from the id, never by adding to a row's `coverUrl`: that already carries a width,
    /// and the server reads the first one it is given.
    static func query(id: Int, width: Int, web: Bool, attempt: Int) -> [String: String] {
        var q = ["id": String(id), "w": String(width)]
        if web { q["src"] = "web" }
        if attempt > 0 { q["r"] = String(attempt) }
        return q
    }

    static func path(id: Int, width: Int, web: Bool, attempt: Int) -> String {
        let q = query(id: id, width: width, web: web, attempt: attempt)
        let order = ["id", "w", "src", "r"]
        let items = order.compactMap { k in q[k].map { "\(k)=\($0)" } }
        return LibraryService.base + "/cover?" + items.joined(separator: "&")
    }

    static func result(status: Int, body: Data, retryAfter: String?) -> LibraryCoverResult {
        if (200..<300).contains(status), status != 202, !body.isEmpty { return .image(body) }
        let code = (try? JSONDecoder().decode(APIErrorBody.self, from: body))?.error
        let wait = retryAfter.flatMap { TimeInterval($0) } ?? 1.5
        if code == "cover_pending" || status == 202 || status == 503 { return .pending(retryAfter: wait) }
        return .none
    }
}

/// Links to the web's Library, for "Open on the web" and a copied paragraph link.
enum LibraryLinks {
    private static func root(_ apiBaseURL: URL) -> URL {
        var root = apiBaseURL
        if root.lastPathComponent == "api" { root.deleteLastPathComponent() }
        return root
    }

    /// `<web>/library/doc/<id>`, with `#<anchor>` for a paragraph.
    static func doc(id: Int, anchor: String? = nil, apiBaseURL: URL) -> URL {
        let url = root(apiBaseURL).appendingPathComponent("library").appendingPathComponent("doc")
            .appendingPathComponent(String(id))
        guard let anchor, !anchor.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.fragment = anchor
        return components.url ?? url
    }

    /// `<web>/library/act/<id>`.
    static func act(id: Int, apiBaseURL: URL) -> URL {
        root(apiBaseURL).appendingPathComponent("library").appendingPathComponent("act").appendingPathComponent(String(id))
    }
}
