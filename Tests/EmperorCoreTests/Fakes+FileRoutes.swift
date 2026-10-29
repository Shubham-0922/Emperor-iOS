import Foundation
@testable import EmperorCore

/// A stand-in for `FileRouteService`: records what it was asked, answers what it is told.
final class FakeFileRoutes: FileRouteProviding, @unchecked Sendable {
    var text = FileTextResponse(
        success: true, fileName: nil, fileExists: true, totalPages: 0, matchedBy: nil,
        truncated: false, pages: [], error: nil)
    var textError: Error?
    private(set) var textRequests: [(name: String, folderName: String?)] = []

    var modelError: Error?
    private(set) var models: [ChatModel] = []

    var maintenanceState = MaintenanceState(active: false)

    func fileText(name: String, folderName: String?) async throws -> FileTextResponse {
        textRequests.append((name, folderName))
        if let textError { throw textError }
        return text
    }

    func setPreferredModel(_ model: ChatModel) async throws {
        models.append(model)
        if let modelError { throw modelError }
    }

    func maintenance() async throws -> MaintenanceState { maintenanceState }
}
