import Foundation
@testable import EmperorCore

// Moved out of `ProjectTests.swift` unchanged; each area's stand-ins live in a file of their own.

final class FakeProjects: ProjectProviding, @unchecked Sendable {
    var list: [Project] = []
    var detail: ProjectDetail?
    var listError: Error?
    var detailError: Error?

    /// Every `includeArchived` value the view model actually asked the server for. The point of
    /// recording it is that "filtered locally" and "re-fetched" look identical on screen.
    private(set) var archivedRequests: [Bool] = []
    private(set) var detailRequests: [String] = []

    func projects(includeArchived: Bool) async throws -> [Project] {
        archivedRequests.append(includeArchived)
        if let listError { throw listError }
        return list
    }

    func project(id: String) async throws -> ProjectDetail {
        detailRequests.append(id)
        if let detailError { throw detailError }
        guard let detail else {
            throw APIError.server(status: 404, message: ProjectService.projectGoneMessage)
        }
        return detail
    }
}
