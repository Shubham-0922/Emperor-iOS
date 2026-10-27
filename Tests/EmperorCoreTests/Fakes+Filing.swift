import Foundation
@testable import EmperorCore

/// A filing server in memory: annexures held per draft, marks assigned as the server assigns
/// them, every call recorded.
final class FakeFiling: FilingProviding, @unchecked Sendable {
    private let lock = NSLock()

    var draftList: [FilingDraft] = []
    var rows: [FilingAnnexure] = []
    var bundleList: [FilingBundle] = []
    var checklistAnswer = FilingChecklist(forum: "High Court", items: [])
    var assembleAnswer = FilingAssemblyResult(success: true, bundleId: 7, pageCount: 42)

    /// Thrown by the named call (`"drafts"`, `"annexures"`, `"add"`, `"update"`, `"delete"`,
    /// `"reorder"`, `"assemble"`, `"bundles"`, `"checklist"`, `"pdf"`), or by every call when
    /// keyed `"*"`.
    var errors: [String: Error] = [:]
    /// Bundles added when assemble is called, before it throws or answers — the run the server
    /// finished although its answer was lost.
    var bundlesMadeByAssemble: [FilingBundle] = []

    private var _calls: [String] = []
    private var _updates: [(id: Int, title: String?, treatment: FilingTreatment?, verify: FilingVerify?)] = []
    private var _reorders: [[Int]] = []
    private var _adds: [(draftID: String, folderName: String, fileName: String)] = []
    private var _annexureReads: [(draftID: String?, chatID: String?)] = []

    var calls: [String] { lock.withLock { _calls } }
    var updates: [(id: Int, title: String?, treatment: FilingTreatment?, verify: FilingVerify?)] {
        lock.withLock { _updates }
    }
    var reorders: [[Int]] { lock.withLock { _reorders } }
    var adds: [(draftID: String, folderName: String, fileName: String)] { lock.withLock { _adds } }
    var annexureReads: [(draftID: String?, chatID: String?)] { lock.withLock { _annexureReads } }

    private func record(_ name: String) throws {
        lock.withLock { _calls.append(name) }
        if let error = errors[name] ?? errors["*"] { throw error }
    }

    func drafts() async throws -> [FilingDraft] {
        try record("drafts")
        return draftList
    }

    func annexures(draftID: String?, chatID: String?) async throws -> [FilingAnnexure] {
        lock.withLock { _annexureReads.append((draftID, chatID)) }
        try record("annexures")
        return rows
    }

    func addAnnexure(draftID: String, folderName: String, fileName: String) async throws -> FilingAnnexure {
        lock.withLock { _adds.append((draftID, folderName, fileName)) }
        try record("add")
        let next = (rows.compactMap { FilingMarks.parse($0.mark).number }.max() ?? 0) + 1
        let row = FilingAnnexure(
            id: (rows.map(\.id).max() ?? 0) + 1, draftID: draftID, mark: "P-\(next)",
            title: fileName, sourceFilePath: "/data/\(folderName)/\(fileName)")
        rows.append(row)
        return row
    }

    func update(
        id: Int, title: String?, treatment: FilingTreatment?, verifyStatus: FilingVerify?
    ) async throws -> FilingAnnexure {
        lock.withLock { _updates.append((id, title, treatment, verifyStatus)) }
        try record("update")
        guard let i = rows.firstIndex(where: { $0.id == id }) else {
            throw APIError.server(status: 400, message: "annexure not found")
        }
        if let title { rows[i].title = title }
        if let treatment { rows[i].treatment = treatment.rawValue }
        if let verifyStatus { rows[i].verifyStatus = verifyStatus.rawValue }
        return rows[i]
    }

    func delete(id: Int) async throws {
        try record("delete")
        rows.removeAll { $0.id == id }
    }

    func reorder(draftID: String, orderedIDs: [Int]) async throws -> (Bool, [FilingAnnexure]) {
        lock.withLock { _reorders.append(orderedIDs) }
        try record("reorder")
        rows = orderedIDs.compactMap { id in rows.first { $0.id == id } }
        return (FilingMarks.isInMarkOrder(rows.map(\.mark)), rows)
    }

    func assemble(draftID: String, cover: FilingCover) async throws -> FilingAssemblyResult {
        bundleList.append(contentsOf: bundlesMadeByAssemble)
        try record("assemble")
        return assembleAnswer
    }

    func bundles(draftID: String?) async throws -> [FilingBundle] {
        try record("bundles")
        return bundleList
    }

    func bundlePDF(id: Int) async throws -> Data {
        try record("pdf")
        return Data("%PDF-1.4".utf8)
    }

    func checklist(draftID: String, forum: String) async throws -> FilingChecklist {
        try record("checklist")
        return checklistAnswer
    }

    func count(_ name: String) -> Int { calls.filter { $0 == name }.count }

    // MARK: - A conversation's annexures

    /// `"chatAdd"`, `"chatAssemble"`, `"typedCopy"`, `"original"`, `"originalPages"` and
    /// `"typedCopies"` are the names `errors` takes for these; `"original:P-3"` and
    /// `"originalPages:P-3"` fail one mark.
    var typedCopyAnswer = FilingTypedCopy(html: "<p>typed</p>", skipped: false, reason: nil)
    var originalAnswers: [String: FilingOriginal] = [:]
    var pageAnswers: [String: FilingOriginalPages] = [:]
    var typedCopiesHTML = ""

    private var _chatAdds: [(chatID: String, folderName: String, fileName: String)] = []
    private var _chatAssembles: [(chatID: String, html: String, title: String, cover: FilingCover)] = []

    var chatAdds: [(chatID: String, folderName: String, fileName: String)] { lock.withLock { _chatAdds } }
    var chatAssembles: [(chatID: String, html: String, title: String, cover: FilingCover)] {
        lock.withLock { _chatAssembles }
    }

    private func recordMark(_ name: String, _ mark: String) throws {
        try record(name)
        if let error = errors["\(name):\(mark)"] { throw error }
    }

    func addAnnexure(chatID: String, folderName: String, fileName: String) async throws -> FilingAnnexure {
        lock.withLock { _chatAdds.append((chatID, folderName, fileName)) }
        try record("chatAdd")
        let next = (rows.compactMap { FilingMarks.parse($0.mark).number }.max() ?? 0) + 1
        let row = FilingAnnexure(
            id: (rows.map(\.id).max() ?? 0) + 1, chatID: chatID, mark: "P-\(next)",
            title: fileName, sourceFilePath: "/data/\(folderName)/\(fileName)")
        rows.append(row)
        return row
    }

    func assemble(chatID: String, html: String, title: String, cover: FilingCover) async throws -> FilingAssemblyResult {
        lock.withLock { _chatAssembles.append((chatID, html, title, cover)) }
        bundleList.append(contentsOf: bundlesMadeByAssemble)
        try record("chatAssemble")
        return assembleAnswer
    }

    func typedCopy(chatID: String, mark: String) async throws -> FilingTypedCopy {
        try recordMark("typedCopy", mark)
        return typedCopyAnswer
    }

    func original(chatID: String, mark: String) async throws -> FilingOriginal {
        try recordMark("original", mark)
        guard let answer = originalAnswers[mark] else {
            throw APIError.server(status: 404, message: "annexure not found")
        }
        return answer
    }

    func originalPages(chatID: String, mark: String) async throws -> FilingOriginalPages {
        try recordMark("originalPages", mark)
        return pageAnswers[mark] ?? FilingOriginalPages(success: false, error: "annexure not found")
    }

    func typedCopies(chatID: String) async throws -> String {
        try record("typedCopies")
        return typedCopiesHTML
    }
}
