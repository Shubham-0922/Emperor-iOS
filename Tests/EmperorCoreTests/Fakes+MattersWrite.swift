import Foundation
@testable import EmperorCore

// The matter-write stand-ins: every call recorded in order, so a test can hold a form to the
// web's sequence (the banner before the fields on an edit, after them on a create).

final class FakeProjectWrites: ProjectWriting, @unchecked Sendable {
    /// Every call, as "save", "patch", "upload", "removeBanner", "delete", "saveUpdate"…
    private(set) var calls: [String] = []
    private(set) var saved: [ProjectBody] = []
    private(set) var patched: [(projectID: String, fields: ProjectFields)] = []
    private(set) var uploads: [(projectID: String, bytes: Int, mime: String)] = []
    private(set) var deleted: [(projectID: String, confirm: String)] = []
    private(set) var bodies: [String: [[String: JSONValue]]] = [:]
    private(set) var links: [String?] = []
    private(set) var fromCase: [(caseID: String, name: String?, banner: String?, color: String?)] = []

    var saveError: Error?
    var uploadError: Error?
    var patchError: Error?
    var deleteError: Error?
    var childError: Error?
    var linkError: Error?
    var savedProject = Project(id: "prj-new-1", name: "New")
    var existed = false
    var nextHearing: String?
    var refreshOutcome: RefreshOutcome = .done(lastSyncedAt: nil, counts: RefreshCounts(hearings: 3, orders: 1))

    func save(_ body: ProjectBody) async throws -> Project {
        calls.append("save")
        saved.append(body)
        if let saveError { throw saveError }
        var p = savedProject
        if let id = body.id { p = Project(id: id, name: p.name) }
        return p
    }

    func patch(projectID: String, fields: ProjectFields) async throws -> Project {
        calls.append("patch")
        patched.append((projectID, fields))
        if let patchError { throw patchError }
        return Project(id: projectID)
    }

    func delete(projectID: String, confirmName: String) async throws -> DeleteSummary {
        calls.append("delete")
        deleted.append((projectID, confirmName))
        if let deleteError { throw deleteError }
        return DeleteSummary(tasks: 1)
    }

    func uploadBanner(projectID: String, jpegOrPNG image: Data, mime: String) async throws {
        calls.append("upload")
        uploads.append((projectID, image.count, mime))
        if let uploadError { throw uploadError }
    }

    func removeBanner(projectID: String) async throws {
        calls.append("removeBanner")
    }

    private func child(_ name: String, _ body: [String: JSONValue]) throws {
        calls.append(name)
        bodies[name, default: []].append(body)
        if let childError { throw childError }
    }

    func saveUpdate(_ body: [String: JSONValue]) async throws -> SavedUpdate {
        try child("saveUpdate", body)
        return SavedUpdate(id: "pup-1", update: ProjectUpdate(id: "pup-1"), nextHearingDate: nextHearing)
    }

    func deleteUpdate(id: String) async throws { try child("deleteUpdate", ["id": .string(id)]) }

    func saveTask(_ body: [String: JSONValue]) async throws -> ProjectTask {
        try child("saveTask", body)
        return ProjectTask(id: body["id"]?.stringValue ?? "pt-1")
    }

    func deleteTask(id: String) async throws { try child("deleteTask", ["id": .string(id)]) }

    func saveLedger(_ body: [String: JSONValue]) async throws -> LedgerEntry {
        try child("saveLedger", body)
        return LedgerEntry(id: "pl-1")
    }

    func deleteLedger(id: String) async throws { try child("deleteLedger", ["id": .string(id)]) }

    func savePerson(_ body: [String: JSONValue]) async throws -> ProjectPerson {
        try child("savePerson", body)
        return ProjectPerson(id: "pp-1")
    }

    func deletePerson(id: String) async throws { try child("deletePerson", ["id": .string(id)]) }

    func linkCase(projectID: String, caseID: String?) async throws -> Project {
        calls.append("link")
        links.append(caseID)
        if let linkError { throw linkError }
        return Project(id: projectID, linkedCaseID: caseID)
    }

    func projectFromCase(caseID: String, name: String?, banner: String?, color: String?) async throws
        -> (project: Project, existed: Bool) {
        calls.append("fromCase")
        fromCase.append((caseID, name, banner, color))
        if let saveError { throw saveError }
        return (Project(id: "prj-from-\(caseID)"), existed)
    }

    func refreshCase(projectID: String) async throws -> RefreshOutcome {
        calls.append("refresh")
        return refreshOutcome
    }
}

/// The court search, for tracking: only `save` is used.
final class FakeTrackingSearch: CourtSearching, @unchecked Sendable {
    var outcome: SaveCaseOutcome = .saved(id: "case-new")
    var failure: Error?
    /// Run when a save is made — to add the case to the docket, as the server would.
    var onSave: (() -> Void)?
    private(set) var saved: [CourtSearchResult] = []

    func search(_ query: CourtSearchQuery) async throws -> [CourtSearchResult] { [] }
    func startCaptchaSession() async throws -> SupremeCourtCaptcha {
        throw APIError.server(status: 500, message: "not used")
    }
    func submitCaptcha(_ answer: String, for query: CourtSearchQuery, session: String) async throws -> CaptchaOutcome {
        .results([])
    }
    func save(_ result: CourtSearchResult) async throws -> SaveCaseOutcome {
        saved.append(result)
        onSave?()
        if let failure { throw failure }
        return outcome
    }
}
