import Foundation
@testable import EmperorCore

/// A stand-in for `FileRouteService`: records what it was asked, answers what it is told.
final class FakeFileRoutes: FileRouteProviding, @unchecked Sendable {
    struct Save: Equatable {
        let id: String
        let title: String
        let content: String
        let type: String
        let chatId: String?
    }

    var saveResult = SaveDocumentResult(
        success: true, id: nil, type: "doc", deduped: false, reclassified: false, error: nil)
    var saveError: Error?
    private(set) var saves: [Save] = []

    var zipData = Data([0x50, 0x4B, 0x03, 0x04, 0x00])
    var zipError: Error?
    private(set) var zipped: [[ZipEntry]] = []

    var text = FileTextResponse(
        success: true, fileName: nil, fileExists: true, totalPages: 0, matchedBy: nil,
        truncated: false, pages: [], error: nil)
    var textError: Error?
    private(set) var textRequests: [(name: String, folderName: String?)] = []

    var pdf = Data("%PDF-1.7".utf8)
    var pdfError: Error?
    private(set) var printed: [(html: String, title: String, pageSetup: PageSetup)] = []

    var modelError: Error?
    private(set) var models: [ChatModel] = []

    var maintenanceState = MaintenanceState(active: false)

    func saveDocument(
        id: String, title: String, content: String, type: String, chatId: String?
    ) async throws -> SaveDocumentResult {
        saves.append(Save(id: id, title: title, content: content, type: type, chatId: chatId))
        if let saveError { throw saveError }
        return SaveDocumentResult(
            success: saveResult.success, id: saveResult.id ?? id, type: saveResult.type,
            deduped: saveResult.deduped, reclassified: saveResult.reclassified, error: nil)
    }

    func zip(_ entries: [ZipEntry]) async throws -> Data {
        zipped.append(entries)
        if let zipError { throw zipError }
        return zipData
    }

    func fileText(name: String, folderName: String?) async throws -> FileTextResponse {
        textRequests.append((name, folderName))
        if let textError { throw textError }
        return text
    }

    func printPDF(html: String, title: String, pageSetup: PageSetup) async throws -> Data {
        printed.append((html, title, pageSetup))
        if let pdfError { throw pdfError }
        return pdf
    }

    func setPreferredModel(_ model: ChatModel) async throws {
        models.append(model)
        if let modelError { throw modelError }
    }

    func maintenance() async throws -> MaintenanceState { maintenanceState }
}
