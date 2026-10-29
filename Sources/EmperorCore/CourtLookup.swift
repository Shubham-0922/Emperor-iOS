import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Fetch Orders (docs/fetch-orders.md): read any court case straight from the court's own records
// — orders with their PDFs, the hearing history, parties and advocates, applications — without
// adding it anywhere. `POST /court/lookup {userId, card}` runs the same adapter the tracker uses
// and writes nothing. The card is the search result as `/save-case` takes it.

// MARK: - The record

/// What `/court/lookup` returns under `record`. Every date is ISO (`YYYY-MM-DD`).
struct CourtRecord: Codable, Equatable, Sendable {
    var `case`: Facts
    var parties: Parties
    /// Newest first, as the server sorts them.
    var hearings: [Hearing]
    /// Newest first.
    var orders: [Order]
    var applications: [Application]
    var connected: [Connected]
    var courtFees: [CourtFee]
    var fetchedAt: String?

    struct Facts: Codable, Equatable, Sendable {
        var title: String?
        var courtType: String?
        var courtName: String?
        var caseType: String?
        var caseNumber: String?
        var caseYear: String?
        var cnr: String?
        var diaryNumber: String?
        var status: String?
        var stage: String?
        var bench: String?
        var filingDate: String?
        var category: String?
        /// The soonest hearing today or later, or null.
        var nextHearing: String?
    }

    struct Parties: Codable, Equatable, Sendable {
        var petitioners: [String]
        var respondents: [String]
        var petitionerAdvocates: [String]
        var respondentAdvocates: [String]

        init(petitioners: [String] = [], respondents: [String] = [],
             petitionerAdvocates: [String] = [], respondentAdvocates: [String] = []) {
            self.petitioners = petitioners
            self.respondents = respondents
            self.petitionerAdvocates = petitionerAdvocates
            self.respondentAdvocates = respondentAdvocates
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            petitioners = try c.decodeIfPresent([String].self, forKey: .petitioners) ?? []
            respondents = try c.decodeIfPresent([String].self, forKey: .respondents) ?? []
            petitionerAdvocates = try c.decodeIfPresent([String].self, forKey: .petitionerAdvocates) ?? []
            respondentAdvocates = try c.decodeIfPresent([String].self, forKey: .respondentAdvocates) ?? []
        }
    }

    struct Hearing: Codable, Equatable, Identifiable, Sendable {
        var date: String?
        var purpose: String?
        var bench: String?
        var stage: String?
        var remarks: String?
        var courtNo: String?
        var itemNo: String?
        var time: String?
        var ia: String?
        var listType: String?

        var id: String { [date, purpose, itemNo, courtNo].compactMap { $0 }.joined(separator: "|") }

        /// "Court 12 · item 34 · 10:30".
        var whereLine: String? {
            [courtNo.map { "Court \($0)" }, itemNo.map { "item \($0)" }, time]
                .compactMap { $0?.nilIfEmpty }.joined(separator: " · ").nilIfEmpty
        }
    }

    struct Order: Codable, Equatable, Identifiable, Sendable {
        var date: String?
        var title: String?
        /// The court's own PDF address, or null when the court serves orders only through a
        /// session — then "No copy online" until the case is tracked, where the order proxy can
        /// fetch it. Not always an address: a consumer forum's order arrives as a marker
        /// (`ejagriti-order:77`) that only the tracked case's order proxy understands.
        var url: String?

        var id: String { [date, title, url].compactMap { $0 }.joined(separator: "|") }

        /// The order's copy when a browser can open it — `http` or `https` with a host, nothing
        /// else. `URL(string:)` takes any scheme, so a forum's marker would otherwise become a
        /// "Read" link that opens nothing; without one the row says "No copy online".
        var pdfURL: URL? {
            let text = (url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let found = URL(string: text), let scheme = found.scheme?.lowercased(),
                  scheme == "http" || scheme == "https", found.host?.isEmpty == false
            else { return nil }
            return found
        }
        var displayTitle: String { title?.nilIfEmpty ?? "Order" }
    }

    struct Application: Codable, Equatable, Identifiable, Sendable {
        var number: String?
        var particular: String?
        var filedOn: String?
        var status: String?
        var remark: String?
        var id: String { [number, particular, filedOn].compactMap { $0 }.joined(separator: "|") }
    }

    struct Connected: Codable, Equatable, Identifiable, Sendable {
        var caseNo: String?
        var court: String?
        var orderDate: String?
        var cnr: String?
        var id: String { [caseNo, court, cnr].compactMap { $0 }.joined(separator: "|") }
    }

    struct CourtFee: Codable, Equatable, Identifiable, Sendable {
        var head: String?
        var amount: Double?
        var id: String { head ?? "" }
    }

    // MARK: Derived

    var displayTitle: String {
        if let title = `case`.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        let sides = [parties.petitioners.first, parties.respondents.first].compactMap { $0 }
        return sides.isEmpty ? "Untitled case" : sides.joined(separator: " v. ")
    }

    /// "ARB.P. 112/2025", "Diary 52650/2026", or the CNR.
    var reference: String? {
        if let number = `case`.caseNumber?.nilIfEmpty {
            let type = `case`.caseType?.nilIfEmpty.map { "\($0) " } ?? ""
            let year = `case`.caseYear?.nilIfEmpty.map { "/\($0)" } ?? ""
            return "\(type)\(number)\(year)"
        }
        if let diary = `case`.diaryNumber?.nilIfEmpty { return "Diary \(diary)" }
        return `case`.cnr?.nilIfEmpty
    }

    /// The order with the latest date — the one the Overview's tile names.
    var latestOrder: Order? {
        orders.max { ($0.date ?? "") < ($1.date ?? "") }
    }

    /// The hearing most recently held, by date.
    var lastHearing: Hearing? {
        hearings.compactMap { h in h.date.map { ($0, h) } }.max { $0.0 < $1.0 }?.1
    }

    /// Whether the court lists a hearing today or later.
    var nextHearingKey: String? { `case`.nextHearing?.nilIfEmpty }

    /// "5 hearings · 3 orders · 2 applications" — what the court holds on this case.
    var holdingsLine: String {
        func count(_ n: Int, _ noun: String) -> String? {
            n == 0 ? nil : "\(n) \(noun)\(n == 1 ? "" : "s")"
        }
        let parts = [
            count(hearings.count, "hearing"), count(orders.count, "order"),
            count(applications.count, "application"), count(connected.count, "connected case"),
        ].compactMap { $0 }
        return parts.isEmpty ? "Nothing on the record yet" : parts.joined(separator: " · ")
    }

    /// "Pending · Arguments" — status and stage, whichever the court gives.
    var standingLine: String? {
        [`case`.status, `case`.stage].compactMap { $0?.nilIfEmpty }.joined(separator: " · ").nilIfEmpty
    }
}

struct CourtLookupResponse: Codable, Sendable {
    var success: Bool?
    var record: CourtRecord?
    var cached: Bool?
    /// `COURT_DOWN`, `NOT_FOUND`, `RATE_LIMIT`, `BAD_REQUEST`, `AUTH`.
    var code: String?
    var error: String?
}

// MARK: - The card

extension CourtSearchResult {
    /// The search result as `/save-case` and `/court/lookup` both take it: every identifying
    /// field it has, and `scrapeRef` verbatim — that is what lets the server run the court's own
    /// adapter again; rebuilt from the visible fields it would look right and fetch nothing.
    var cardFields: [String: JSONValue] {
        var card: [String: JSONValue] = [:]
        func put(_ key: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            card[key] = .string(value)
        }
        put("cnr", cnr)
        put("diaryNumber", diaryNumber)
        put("courtType", courtType)
        put("courtCode", courtCode)
        put("courtName", courtName)
        put("caseType", caseType)
        put("caseNumber", caseNumber)
        put("caseYear", caseYear)
        put("title", title)
        put("parties", parties)
        put("status", status)
        if let scrapeRef { card["scrapeRef"] = scrapeRef }
        return card
    }

    /// The card as `/court/lookup` alone takes it: `cardFields`, plus what the search route said
    /// that the court's own record may not — `judge` and `stage`, which the record falls back to
    /// for its bench and stage (`lookup.js` `recordFromBundle`) and which are part of the
    /// server's cache key, and `nextHearingDate`, which the web's `casePayload` sends beside
    /// them (`lookup.js` does not read it). `/save-case` keeps `cardFields` as it is.
    var lookupCardFields: [String: JSONValue] {
        var card = cardFields
        let extras: [(String, String?)] = [("judge", judge), ("stage", stage), ("nextHearingDate", nextHearingDate)]
        for (key, value) in extras {
            guard let value, !value.isEmpty else { continue }
            card[key] = .string(value)
        }
        return card
    }
}

// MARK: - The service

protocol CourtLookupProviding: Sendable {
    func lookup(_ card: CourtSearchResult) async throws -> CourtRecord
}

/// `POST /court/lookup`: a live read of the court's record, saved nowhere.
///
/// The route is honest about its status codes — 429 for the per-minute cap, 404 when the court
/// returned nothing, 400 for a card it cannot read, 502 when the court did not answer — and
/// carries a `code` beside the sentence. The wording below is this client's, because the
/// server's "did not give us this case (…)" quotes the adapter's error at the reader.
struct CourtLookupService: CourtLookupProviding {
    let client: APIClient

    /// A fresh lookup runs the court's adapter, captcha and all, and the court's own portal sets
    /// the pace: a few seconds usually, 40–80 for Allahabad and the other dedicated High Court
    /// portals (gotcha 45). So it waits as long as a dedicated search does, not the 60 seconds of
    /// a save, which cut the slowest courts off just before they answered.
    static let timeout: TimeInterval = CourtSearchService.dedicatedTimeout

    func lookup(_ card: CourtSearchResult) async throws -> CourtRecord {
        guard let credentials = await client.currentCredentials() else {
            throw APIError.notAuthenticated
        }
        var body: [String: JSONValue] = ["userId": .string(credentials.userIDString)]
        body["card"] = .object(card.lookupCardFields)

        var request = try await client.makeRequest("POST", "/court/lookup", body: Payload(body: body))
        request.timeoutInterval = Self.timeout
        let (data, http) = try await client.perform(request)
        let decoded = try? JSONDecoder().decode(CourtLookupResponse.self, from: data)

        if (200..<300).contains(http.statusCode), decoded?.success == true, let record = decoded?.record {
            return record
        }
        throw Self.failure(status: http.statusCode, decoded: decoded, body: data)
    }

    /// `NOT_FOUND`: the court returned nothing under that number.
    static let nothingUnderThatNumber = APIError.server(
        status: 404, message: "The court returned no details for this case. Check the number and year, or try again later.")
    /// `BAD_REQUEST`: the card is not one the court can be asked about.
    static let unreadableCard = APIError.server(
        status: 400, message: "That case could not be read. Search for it again.")

    /// The two answers that are final for a card: asking again sends the same card and gets the
    /// same answer, so the way on is a new search, never "Try again" — the web's `LookupError`
    /// (`FetchOrders.jsx`: `retryable = code !== 'NOT_FOUND' && code !== 'BAD_REQUEST'`).
    enum FinalAnswer: Equatable, Sendable {
        case nothingUnderThatNumber
        case unreadableCard

        /// The failure's heading.
        var title: String {
            switch self {
            case .nothingUnderThatNumber: return "The court has nothing under that number."
            case .unreadableCard: return "We could not read this case."
            }
        }
    }

    /// Whether `error` is one of the final answers. Told apart by this client's own wording, not
    /// by the status alone: an uncoded 404 (a server without this route) is not the court saying
    /// it has nothing.
    static func finalAnswer(_ error: Error) -> FinalAnswer? {
        guard let apiError = error as? APIError else { return nil }
        if apiError == nothingUnderThatNumber { return .nothingUnderThatNumber }
        if apiError == unreadableCard { return .unreadableCard }
        return nil
    }

    /// The refusal, worded for the person reading it.
    static func failure(status: Int, decoded: CourtLookupResponse?, body: Data) -> APIError {
        switch decoded?.code {
        case "RATE_LIMIT":
            return .server(status: 429, message: "That is a lot of lookups at once. Wait a minute and try again.")
        case "NOT_FOUND":
            return nothingUnderThatNumber
        case "COURT_DOWN":
            return .server(status: 502, message: "The court's website did not answer. Try again in a few minutes.")
        case "BAD_REQUEST":
            return unreadableCard
        case "AUTH":
            return .invalidCredentials
        default:
            if let error = decoded?.error, !error.isEmpty { return .server(status: status, message: error) }
            return APIError.classify(status: status, body: body)
        }
    }

    private struct Payload: Encodable {
        let body: [String: JSONValue]
        func encode(to encoder: Encoder) throws { try body.encode(to: encoder) }
    }
}
