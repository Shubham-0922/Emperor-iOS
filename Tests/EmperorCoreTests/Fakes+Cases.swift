import Foundation
@testable import EmperorCore

// Moved out of `Fakes.swift` unchanged; each area's stand-ins live in a file of their own.

final class FakeCases: CaseProviding, @unchecked Sendable {
    var cases: [LegalCase] = []
    var detail: CaseDetail?
    var listings: [CauseListing] = []
    var error: Error?
    /// Fails `/cause-list` alone, for a screen that also reads the docket.
    var causeListError: Error?
    var orderData = Data("%PDF-1.4 stub".utf8)
    /// `/cause-list` takes no date parameter and returns the entire history, so the client
    /// fetches once and windows locally. Counting proves it does not re-fetch per day.
    private(set) var causeListCallCount = 0
    private(set) var notesAdded: [(caseID: String, body: String)] = []
    private(set) var tasksAdded: [(caseID: String, title: String, dueDate: Date?)] = []

    func cases() async throws -> [LegalCase] {
        if let error { throw error }
        return cases
    }

    func caseDetail(id: String) async throws -> CaseDetail {
        if let error { throw error }
        guard let detail else {
            throw APIError.server(status: 404, message: "That matter could not be found.")
        }
        return detail
    }

    func causeList() async throws -> [CauseListing] {
        causeListCallCount += 1
        if let error = causeListError ?? error { throw error }
        return listings
    }

    func addNote(caseID: String, title: String?, body: String) async throws {
        if let error { throw error }
        notesAdded.append((caseID, body))
    }

    func addTask(caseID: String, title: String, dueDate: Date?) async throws {
        if let error { throw error }
        tasksAdded.append((caseID, title, dueDate))
    }

    func orderDocument(for item: CaseItem, in legalCase: LegalCase) async throws -> Data {
        if let error { throw error }
        return orderData
    }
}
