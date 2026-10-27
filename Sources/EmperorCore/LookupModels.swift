import Foundation

/// A case as the court's own records describe it, read for Fetch Orders and saved nowhere.
///
/// The platform's lookup runs the same adapter its case tracker uses and hands back the facts in
/// one plain object: the case, its parties, every hearing and order (newest first), applications,
/// connected matters and court fees. Days are `YYYY-MM-DD` or absent; every string may be absent.
/// A missing list decodes as empty, so a sparse court reads as "nothing on the record" rather
/// than as a failure.
struct LookupRecord: Decodable, Equatable, Sendable {

    struct Case: Decodable, Equatable, Sendable {
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
        var nextHearing: String?

        init(title: String? = nil, courtType: String? = nil, courtName: String? = nil, caseType: String? = nil,
             caseNumber: String? = nil, caseYear: String? = nil, cnr: String? = nil, diaryNumber: String? = nil,
             status: String? = nil, stage: String? = nil, bench: String? = nil, filingDate: String? = nil,
             category: String? = nil, nextHearing: String? = nil) {
            self.title = title
            self.courtType = courtType
            self.courtName = courtName
            self.caseType = caseType
            self.caseNumber = caseNumber
            self.caseYear = caseYear
            self.cnr = cnr
            self.diaryNumber = diaryNumber
            self.status = status
            self.stage = stage
            self.bench = bench
            self.filingDate = filingDate
            self.category = category
            self.nextHearing = nextHearing
        }
    }

    struct Parties: Decodable, Equatable, Sendable {
        var petitioners: [String] = []
        var respondents: [String] = []
        var petitionerAdvocates: [String] = []
        var respondentAdvocates: [String] = []

        init(petitioners: [String] = [], respondents: [String] = [],
             petitionerAdvocates: [String] = [], respondentAdvocates: [String] = []) {
            self.petitioners = petitioners
            self.respondents = respondents
            self.petitionerAdvocates = petitionerAdvocates
            self.respondentAdvocates = respondentAdvocates
        }

        private enum CodingKeys: String, CodingKey {
            case petitioners, respondents, petitionerAdvocates, respondentAdvocates
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            petitioners = Self.names(c, .petitioners)
            respondents = Self.names(c, .respondents)
            petitionerAdvocates = Self.names(c, .petitionerAdvocates)
            respondentAdvocates = Self.names(c, .respondentAdvocates)
        }

        /// The court's list of names; a null inside it, or a list that is not one, is dropped
        /// rather than failing the whole record.
        private static func names(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String] {
            let raw = (try? c.decodeIfPresent([String?].self, forKey: key)) ?? nil
            return (raw ?? []).compactMap { $0 }
        }
    }

    struct Hearing: Decodable, Equatable, Sendable {
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

        init(date: String? = nil, purpose: String? = nil, bench: String? = nil, stage: String? = nil,
             remarks: String? = nil, courtNo: String? = nil, itemNo: String? = nil, time: String? = nil,
             ia: String? = nil, listType: String? = nil) {
            self.date = date
            self.purpose = purpose
            self.bench = bench
            self.stage = stage
            self.remarks = remarks
            self.courtNo = courtNo
            self.itemNo = itemNo
            self.time = time
            self.ia = ia
            self.listType = listType
        }
    }

    struct Order: Decodable, Equatable, Sendable {
        var date: String?
        var title: String?
        /// The court's copy: an `http(s)` address, or a marker some portals use that is not an
        /// address at all. See `webURL`.
        var url: String?

        init(date: String? = nil, title: String? = nil, url: String? = nil) {
            self.date = date
            self.title = title
            self.url = url
        }

        /// The order's copy, when it is something a browser can open — `http` or `https` only.
        /// A consumer forum's order arrives as a marker rather than an address; it has no copy
        /// to open from here, and is shown as "No copy online".
        var webURL: URL? {
            let text = (url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let found = URL(string: text), let scheme = found.scheme?.lowercased(),
                  scheme == "http" || scheme == "https", found.host != nil
            else { return nil }
            return found
        }
    }

    struct Application: Decodable, Equatable, Sendable {
        var number: String?
        var particular: String?
        var filedOn: String?
        var status: String?
        var remark: String?
    }

    struct Connected: Decodable, Equatable, Sendable {
        var caseNo: String?
        var court: String?
        var orderDate: String?
        var cnr: String?
    }

    struct CourtFee: Decodable, Equatable, Sendable {
        var head: String?
        var amount: Double?
    }

    var `case`: Case
    var parties: Parties
    var hearings: [Hearing]
    var orders: [Order]
    var applications: [Application]
    var connected: [Connected]
    var courtFees: [CourtFee]
    /// When the court was read, as the server's ISO instant.
    var fetchedAt: String?

    init(case kase: Case = Case(), parties: Parties = Parties(), hearings: [Hearing] = [], orders: [Order] = [],
         applications: [Application] = [], connected: [Connected] = [], courtFees: [CourtFee] = [],
         fetchedAt: String? = nil) {
        self.case = kase
        self.parties = parties
        self.hearings = hearings
        self.orders = orders
        self.applications = applications
        self.connected = connected
        self.courtFees = courtFees
        self.fetchedAt = fetchedAt
    }

    private enum CodingKeys: String, CodingKey {
        case `case`, parties, hearings, orders, applications, connected, courtFees, fetchedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.case = try c.decodeIfPresent(Case.self, forKey: .case) ?? Case()
        parties = try c.decodeIfPresent(Parties.self, forKey: .parties) ?? Parties()
        hearings = try c.decodeIfPresent([Hearing].self, forKey: .hearings) ?? []
        orders = try c.decodeIfPresent([Order].self, forKey: .orders) ?? []
        applications = try c.decodeIfPresent([Application].self, forKey: .applications) ?? []
        connected = try c.decodeIfPresent([Connected].self, forKey: .connected) ?? []
        courtFees = try c.decodeIfPresent([CourtFee].self, forKey: .courtFees) ?? []
        fetchedAt = try c.decodeIfPresent(String.self, forKey: .fetchedAt)
    }
}

/// Why a case could not be read from its court, in the lookup's own classes.
///
/// The server tags each refusal with a `code`; the screen words its title from the class and
/// shows the server's sentence under it, as the web's error card does.
enum LookupFailure: Error, Equatable, Sendable {
    /// The court has nothing under that number.
    case notFound(String)
    /// The card could not be read — not a court, or too large.
    case badRequest(String)
    /// Too many lookups at once.
    case rateLimited(String)
    /// The court's own website did not answer.
    case courtDown(String)
    /// The sign-in has to be renewed.
    case auth(String)
    /// Anything else: the network, the server.
    case other(String)

    /// The server's (or this client's) sentence.
    var message: String {
        switch self {
        case .notFound(let m), .badRequest(let m), .rateLimited(let m), .courtDown(let m),
             .auth(let m), .other(let m):
            return m
        }
    }

    /// Whether "Try again" is offered. Not for a number the court does not have, or a card it
    /// cannot read: asking again gives the same answer.
    var retryable: Bool {
        switch self {
        case .notFound, .badRequest: return false
        case .rateLimited, .courtDown, .auth, .other: return true
        }
    }

    /// The error card's title (`FetchOrders.jsx` `LookupError`).
    var title: String {
        if case .notFound = self { return "The court has nothing under that number." }
        return "We could not read this case just now."
    }

    static let fallbackMessage = "The court did not answer. Try again in a few minutes."
    static let networkMessage = "Could not reach Emperor. Check your connection and try again."

    /// The class for a refusal: the server's `code` first, its status after.
    static func from(code: String?, status: Int, message: String?) -> LookupFailure {
        let said = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = said.isEmpty ? fallbackMessage : said
        switch code {
        case "NOT_FOUND": return .notFound(text)
        case "BAD_REQUEST": return .badRequest(text)
        case "RATE_LIMIT": return .rateLimited(text)
        case "COURT_DOWN": return .courtDown(text)
        case "AUTH": return .auth(text)
        default: break
        }
        switch status {
        case 401: return .auth(said.isEmpty ? "Please sign in again to fetch court records." : said)
        case 429: return .rateLimited(text)
        default: return .other(text)
        }
    }
}

extension CourtSearchResult {

    /// The card a lookup sends, in the keys the platform's `casePayload` gives it: the CNR, or for
    /// a court that issues none the diary number, in `cnr`; blanks as null; `scrapeRef` verbatim.
    var lookupCard: [String: JSONValue] {
        func text(_ value: String?) -> JSONValue? { value.map(JSONValue.string) }
        func orNull(_ value: String?) -> JSONValue {
            guard let value, !value.isEmpty else { return .null }
            return .string(value)
        }
        var card: [String: JSONValue] = [:]
        card["courtType"] = text(courtType)
        card["courtCode"] = text(courtCode)
        card["courtName"] = text(courtName)
        card["caseType"] = text(caseType)
        card["caseNumber"] = text(caseNumber)
        card["caseYear"] = text(caseYear)
        let identity: String? = (cnr?.isEmpty == false) ? cnr : diaryNumber
        card["cnr"] = orNull(identity)
        card["diaryNumber"] = orNull(diaryNumber)
        card["title"] = text(title)
        card["parties"] = orNull(parties)
        card["judge"] = orNull(judge)
        card["status"] = orNull(status)
        card["stage"] = orNull(stage)
        card["nextHearingDate"] = orNull(nextHearingDate)
        card["scrapeRef"] = scrapeRef ?? .null
        return card
    }

    /// The key a recent lookup is remembered under (`fetchOrdersApi.js` `rememberCase`): the CNR,
    /// else the diary number, else court, type, number and year.
    var historyKey: String {
        if let cnr, !cnr.isEmpty { return cnr }
        if let diaryNumber, !diaryNumber.isEmpty { return diaryNumber }
        let parts: [String] = [courtName ?? "", caseType ?? "", caseNumber ?? "", caseYear ?? ""]
        return parts.joined(separator: "|")
    }
}
