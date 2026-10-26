import Foundation
@testable import EmperorCore

// The matters stand-in; each area's stand-ins live in a file of their own.

final class FakeProjects: ProjectProviding, @unchecked Sendable {
    var list: [Project] = []
    var detail: ProjectDetail?
    var listError: Error?
    var detailError: Error?
    /// The bytes `bannerImage` answers with, or nil to fail as a matter without a picture.
    var banner: Data?

    /// Every `includeArchived` value asked for. The point of recording it is that "filtered
    /// locally" and "re-fetched" look identical on screen.
    private(set) var archivedRequests: [Bool] = []
    private(set) var detailRequests: [String] = []
    private(set) var bannerRequests: [(id: String, version: String)] = []

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

    func bannerImage(projectID: String, version: String) async throws -> Data {
        bannerRequests.append((projectID, version))
        guard let banner else { throw APIError.server(status: 404, message: "No banner image.") }
        return banner
    }
}
