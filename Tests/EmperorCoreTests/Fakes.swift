import Foundation
@testable import EmperorCore

// Stand-ins for the three services the screens depend on. Shared across the view-model tests
// so each file states only what it is actually exercising.

final class FakeFiles: FileProviding, @unchecked Sendable {
    var tree: [FileNode] = []
    var treeError: Error?
    var data: [String: Data] = [:]
    var dataError: Error?
    /// How many times the tree was fetched. `tree()` is an expensive server-side walk, so
    /// "was it fetched at all" and "was it fetched twice" are both worth asserting.
    private(set) var treeCallCount = 0
    /// The last name passed to `fileData`, or `nil` if it was never called. Lets a test assert
    /// a document was routed *away* from `/view-file`, which is what the office-preview path
    /// has to do for a `.docx`.
    private(set) var lastRequestedName: String?

    func tree() async throws -> [FileNode] {
        treeCallCount += 1
        if let treeError { throw treeError }
        return tree
    }

    func fileData(name: String, folderName: String?) async throws -> Data {
        lastRequestedName = name
        if let dataError { throw dataError }
        return data[name] ?? Data()
    }
}

final class FakeUploads: UploadProviding, @unchecked Sendable {
    var events: [UploadService.UploadEvent] = []
    var error: Error?
    private(set) var uploadedNames: [String] = []
    private(set) var uploadedFolders: [String] = []

    func upload(
        data: Data, fileName: String, folderName: String, chunkSize: Int
    ) -> AsyncThrowingStream<UploadService.UploadEvent, Error> {
        uploadedNames.append(fileName)
        uploadedFolders.append(folderName)
        let queued = events
        let failure = error
        return AsyncThrowingStream { continuation in
            if let failure {
                continuation.finish(throwing: failure)
                return
            }
            for event in queued { continuation.yield(event) }
            continuation.finish()
        }
    }
}

// MARK: - Builders

/// A file the model can read. `status` matters: a `nil` status classifies as *in progress*,
/// which makes a file unattachable — an easy way to write a test that passes for the wrong
/// reason.
func readyFile(_ path: String, size: Int? = 1024) -> FileNode.StoredFile {
    FileNode.StoredFile(
        name: String(path.split(separator: "/").last ?? ""),
        path: path,
        size: size,
        status: "ready")
}

func folder(_ path: String, _ children: [FileNode]) -> FileNode {
    .folder(FileNode.Folder(
        name: String(path.split(separator: "/").last ?? ""),
        path: path,
        files: children))
}

final class FakeNotifications: NotificationProviding, @unchecked Sendable {
    var notifications: [AppNotification] = []
    var unreadCount = 0
    var error: Error?
    private(set) var markedRead: [String] = []
    private(set) var markedAllRead = false

    func notifications(limit: Int) async throws -> [AppNotification] {
        if let error { throw error }
        return notifications
    }

    func unreadCount() async throws -> Int {
        if let error { throw error }
        return unreadCount
    }

    func markRead(id: String) async throws {
        if let error { throw error }
        markedRead.append(id)
    }

    func markAllRead() async throws {
        if let error { throw error }
        markedAllRead = true
    }
}

/// The on-device tools, without PDFKit. Records what each tool was asked to do.
final class FakeDocumentToolEngine: DocumentToolEngine, @unchecked Sendable {
    var error: Error?
    var output = Data("%PDF-1.7 fake".utf8)
    var compressResult = PDFCompression.Result(
        outcome: PDFCompression.Outcome(
            originalBytes: 0, compressedBytes: 0, pageCount: 1, pagesReencoded: 1),
        data: Data(count: 600))
    var imageReport = ImageCompression.Report(
        originalWidth: 4032, originalHeight: 3024,
        result: ImageCompression.Result(
            data: Data(count: 90_000), width: 1579, height: 1184, quality: 0.5, hitTarget: true))
    /// Fractions reported through `progress` before `compressPDF` returns.
    var progressSteps: [Double] = []

    private(set) var rearranged: [(url: URL, pages: [Int], name: String)] = []
    private(set) var compressedLevels: [PDFCompression.Level] = []
    private(set) var imageTargets: [Int] = []
    private(set) var imageBatches: [(urls: [URL], size: ImagePDFLayout.PageSize, name: String)] = []

    func rearrange(_ source: URL, pages: [Int], outputName: String) async throws -> ToolFile {
        if let error { throw error }
        rearranged.append((source, pages, outputName))
        return ToolFile(name: outputName, data: output)
    }

    func compressPDF(
        _ source: URL, level: PDFCompression.Level,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> PDFCompression.Result {
        if let error { throw error }
        compressedLevels.append(level)
        for step in progressSteps { progress(step) }
        return compressResult
    }

    func compressImage(_ source: URL, targetBytes: Int) async throws -> ImageCompression.Report {
        if let error { throw error }
        imageTargets.append(targetBytes)
        return imageReport
    }

    func imagesToPDF(
        _ images: [URL], pageSize: ImagePDFLayout.PageSize, outputName: String
    ) async throws -> ToolFile {
        if let error { throw error }
        imageBatches.append((images, pageSize, outputName))
        return ToolFile(name: outputName, data: output)
    }
}

final class FakeCalendar: CalendarProviding, @unchecked Sendable {
    var events: [ComplianceEvent] = []
    var error: Error?
    private(set) var saved: [ComplianceDraft] = []
    private(set) var deleted: [String] = []

    func events() async throws -> [ComplianceEvent] {
        if let error { throw error }
        return events
    }

    func save(_ draft: ComplianceDraft) async throws {
        if let error { throw error }
        saved.append(draft)
    }

    func delete(id: String) async throws {
        if let error { throw error }
        deleted.append(id)
    }
}
