import Foundation

/// The nine collections of the reference library, in the web's shelf order
/// (`src/components/library/coverTheme.js`, `CATEGORY_ORDER`).
///
/// The wire carries the key as a string and a category this client does not know is still shown
/// (under its own label), so `LibraryCategory.key` stays a `String`; this enum names the ones a
/// screen treats specially.
enum LibraryCategoryKey: String, CaseIterable, Sendable {
    case bareActs = "bare-acts"
    case caseLaw = "case-law"
    case books = "books-and-law-reports"
    case regulatorOrders = "regulator-orders"
    case tribunals = "tribunals"
    case lawCommission = "law-commission-reports"
    case institutes = "professional-institutes"
    case parliament = "parliament-prs"
    case legalAid = "legal-aid-nalsa"

    /// The keys in shelf order, as strings.
    static let order: [String] = allCases.map(\.rawValue)
}

/// The catalogue's sort vocabulary (`lib/library/query.js`, `SORTS` and `JS_SORTS`). An unknown
/// value falls back to the collection's default on the server, so a sort is passed as its raw
/// string; these name the ones the client chooses itself.
enum LibrarySort: String, CaseIterable, Sendable {
    case titleAscending = "title_asc"
    case titleDescending = "title_desc"
    case newest = "date_desc"
    case oldest = "date_asc"
    case yearNewest = "year_desc"
    case yearOldest = "year_asc"
    case court = "court"
    case largest = "size_desc"
    case smallest = "size_asc"
    case reportNewest = "report_desc"
    case reportOldest = "report_asc"

    /// The server's own default for a collection, used until the reader picks another.
    static func defaultSort(for category: String) -> String {
        switch category {
        case LibraryCategoryKey.caseLaw.rawValue: return LibrarySort.newest.rawValue
        case LibraryCategoryKey.lawCommission.rawValue: return LibrarySort.reportNewest.rawValue
        default: return LibrarySort.titleAscending.rawValue
        }
    }

    /// What the web chooses for a collection before the reader does (the `defaultSort` each
    /// `categories/*.jsx` passes its grid) — `nil` leaves it to the server.
    static func webDefault(for category: String) -> String? {
        switch category {
        case LibraryCategoryKey.caseLaw.rawValue: return LibrarySort.newest.rawValue
        case LibraryCategoryKey.regulatorOrders.rawValue, LibraryCategoryKey.tribunals.rawValue:
            return LibrarySort.yearNewest.rawValue
        default: return nil
        }
    }
}

/// Why a library request failed, read from the catalogue's `error` code
/// (`lib/library/routes.js`). The catalogue's error bodies carry a code and no sentence worth
/// showing, so the words are this client's — the web's own, where it has them.
enum LibraryError: Error, Equatable, Sendable {
    /// `503 catalogue_unavailable`: this server has no catalogue built.
    case catalogueUnavailable
    case notFound
    case notAnAct
    case notAJudgment
    /// `404 file_missing`: listed, but the file is not on this server yet.
    case fileMissing
    /// `413 too_large`, or a file over the size this client opens in memory.
    case tooLarge
    /// `503 search_busy` / `search_timeout`: the search pool is full; try again in a moment.
    case busy
    case missingQuery
    case other(String)

    /// Maps an `APIError` from a catalogue route. A signed-out answer, maintenance, a refusal and
    /// a transport failure are not library errors and are returned as they came — the caller
    /// rethrows them, so the session handling and the offline wording stay the app's own.
    static func from(_ error: Error) -> Error {
        guard let api = error as? APIError, case .server(let status, let code) = api else { return error }
        switch (status, code) {
        case (503, "catalogue_unavailable"): return LibraryError.catalogueUnavailable
        case (_, "not_found"), (_, "unknown_category"): return LibraryError.notFound
        case (_, "not_an_act"): return LibraryError.notAnAct
        case (_, "not_a_judgment"): return LibraryError.notAJudgment
        case (_, "file_missing"): return LibraryError.fileMissing
        case (413, _), (_, "too_large"): return LibraryError.tooLarge
        case (_, "search_busy"), (_, "search_timeout"): return LibraryError.busy
        case (_, "missing_query"): return LibraryError.missingQuery
        default: return LibraryError.other(code)
        }
    }

    /// Plain words, the web's where it has them.
    var message: String {
        switch self {
        case .catalogueUnavailable: return "The catalogue has not been built on this server yet."
        case .notFound: return "There is no such document."
        case .notAnAct: return "This document is not part of the Bare Acts."
        case .notAJudgment: return "This document is not a judgment."
        case .fileMissing:
            return "It is listed in the catalogue, but its file has not been copied to this server. Try again later."
        case .tooLarge: return "This document is too large to open here."
        case .busy: return "The library is busy. Try again in a moment."
        case .missingQuery: return "Type something to search for."
        case .other: return "The library did not answer properly. Try again in a moment."
        }
    }
}

extension LibraryError: LocalizedError {
    var errorDescription: String? { message }
}
