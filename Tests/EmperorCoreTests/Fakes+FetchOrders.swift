import Foundation
@testable import EmperorCore

/// Fetch Orders' court, answering from a queue: each lookup takes the next answer, the last one
/// repeating. `MatterCreating`'s stand-in is `FakeMatterCreation` (Fakes+MattersContent.swift).
final class FakeFetchOrders: FetchOrdersProviding, @unchecked Sendable {
    var answers: [Result<LookupResult, LookupFailure>] = []
    private(set) var cards: [CourtSearchResult] = []
    /// Holds each lookup until `release()`, for a test that acts while one is in flight.
    var holds = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private let lock = NSLock()

    func lookup(_ card: CourtSearchResult) async throws -> LookupResult {
        let answer: Result<LookupResult, LookupFailure>? = lock.withLock {
            cards.append(card)
            let next = answers.first
            if answers.count > 1 { answers.removeFirst() }
            return next
        }
        if holds {
            await withCheckedContinuation { continuation in
                lock.withLock { waiting.append(continuation) }
            }
        }
        try Task.checkCancellation()
        guard let answer else { throw LookupFailure.other("no answer configured") }
        return try answer.get()
    }

    /// Lets every held lookup go on.
    func release() {
        let all: [CheckedContinuation<Void, Never>] = lock.withLock {
            let held = waiting
            waiting = []
            return held
        }
        for continuation in all { continuation.resume() }
    }

    /// Whether a lookup is waiting on `release()`.
    var isHolding: Bool { lock.withLock { !waiting.isEmpty } }
}

/// A recorded court case for the Fetch Orders tests.
func lookupRecord(
    title: String? = "RAM KUMAR vs. STATE", status: String? = "Pending", next: String? = nil,
    orders: [LookupRecord.Order] = [], petitioners: [String] = ["RAM KUMAR"], respondents: [String] = ["STATE"]
) -> LookupRecord {
    LookupRecord(
        case: LookupRecord.Case(
            title: title, courtType: "hc", courtName: "High Court — Delhi", caseType: "W.P.(C)",
            caseNumber: "12", caseYear: "2025", cnr: "DLHC010000122025", status: status, nextHearing: next),
        parties: LookupRecord.Parties(petitioners: petitioners, respondents: respondents),
        orders: orders)
}

/// A search card the lookup is given.
func lookupCard(cnr: String? = "DLHC010000122025", diary: String? = nil, number: String = "12") -> CourtSearchResult {
    CourtSearchResult(
        courtType: "hc", courtCode: "hc-delhi", courtName: "High Court — Delhi", caseType: "W.P.(C)",
        caseNumber: number, caseYear: "2025", cnr: cnr, diaryNumber: diary, title: "Ram Kumar v. State")
}
