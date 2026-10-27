import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol FilingProviding: Sendable {
    func drafts() async throws -> [FilingDraft]
    func annexures(draftID: String?, chatID: String?) async throws -> [FilingAnnexure]
    func addAnnexure(draftID: String, folderName: String, fileName: String) async throws -> FilingAnnexure
    func update(
        id: Int, title: String?, treatment: FilingTreatment?, verifyStatus: FilingVerify?
    ) async throws -> FilingAnnexure
    func delete(id: Int) async throws
    func reorder(draftID: String, orderedIDs: [Int]) async throws -> (Bool, [FilingAnnexure])
    func assemble(draftID: String, cover: FilingCover) async throws -> FilingAssemblyResult
    func bundles(draftID: String?) async throws -> [FilingBundle]
    func bundlePDF(id: Int) async throws -> Data
    func checklist(draftID: String, forum: String) async throws -> FilingChecklist

    // A conversation's own annexures — the draft on screen in a chat rather than a saved one.
    func addAnnexure(chatID: String, folderName: String, fileName: String) async throws -> FilingAnnexure
    func assemble(chatID: String, html: String, title: String, cover: FilingCover) async throws -> FilingAssemblyResult
    func typedCopy(chatID: String, mark: String) async throws -> FilingTypedCopy
    func original(chatID: String, mark: String) async throws -> FilingOriginal
    func originalPages(chatID: String, mark: String) async throws -> FilingOriginalPages
    func typedCopies(chatID: String) async throws -> String
}

extension FilingProviding {
    /// A conversation's annexures: the ones its draft cited, and any added to it.
    func annexures(chatID: String) async throws -> [FilingAnnexure] {
        try await annexures(draftID: nil, chatID: chatID)
    }

    // Defaults, so a stand-in written before these existed still conforms.
    func addAnnexure(chatID: String, folderName: String, fileName: String) async throws -> FilingAnnexure {
        throw FilingService.unavailable
    }
    func assemble(chatID: String, html: String, title: String, cover: FilingCover) async throws -> FilingAssemblyResult {
        throw FilingService.unavailable
    }
    func typedCopy(chatID: String, mark: String) async throws -> FilingTypedCopy {
        throw FilingService.unavailable
    }
    func original(chatID: String, mark: String) async throws -> FilingOriginal {
        throw FilingService.unavailable
    }
    func originalPages(chatID: String, mark: String) async throws -> FilingOriginalPages {
        throw FilingService.unavailable
    }
    func typedCopies(chatID: String) async throws -> String {
        throw FilingService.unavailable
    }
}

/// Filing assembly (`/filing/*`): drafts, their annexures, the assembler and its bundles.
///
/// Reads are retried; writes are not. Assembly above all is never retried: each run makes a new
/// bundle, and a run can take minutes. A Free account is refused on every route with a coded
/// 402, which `APIClient` turns into `.refused`.
struct FilingService: FilingProviding {
    let client: APIClient

    // MARK: - Reads

    func drafts() async throws -> [FilingDraft] {
        let response = try await withRetry {
            let request = try await client.makeRequest("GET", "/filing/drafts")
            return try await client.send(request, as: FilingDraftsResponse.self)
        }
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        return response.drafts ?? []
    }

    /// A draft's annexures. With the draft's own chat as well, annexures that chat cited are
    /// listed with the draft's, as the web lists them.
    func annexures(draftID: String?, chatID: String?) async throws -> [FilingAnnexure] {
        var query: [String: String] = [:]
        if let draftID, !draftID.isEmpty { query["draftId"] = draftID }
        if let chatID, !chatID.isEmpty { query["chatId"] = chatID }
        let response = try await withRetry { [query] in
            let request = try await client.makeRequest("GET", "/filing/annexures", query: query)
            return try await client.send(request, as: FilingAnnexuresResponse.self)
        }
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        return response.annexures ?? []
    }

    func bundles(draftID: String?) async throws -> [FilingBundle] {
        var query: [String: String] = [:]
        if let draftID, !draftID.isEmpty { query["draftId"] = draftID }
        let response = try await withRetry { [query] in
            let request = try await client.makeRequest("GET", "/filing/bundles", query: query)
            return try await client.send(request, as: FilingBundlesResponse.self)
        }
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        return response.bundles ?? []
    }

    func checklist(draftID: String, forum: String) async throws -> FilingChecklist {
        let response = try await withRetry {
            let request = try await client.makeRequest(
                "GET", "/filing/checklist", query: ["draftId": draftID, "forum": forum])
            return try await client.send(request, as: FilingChecklistResponse.self)
        }
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        guard let checklist = response.checklist else {
            throw APIError.server(status: 200, message: "The checklist could not be prepared.")
        }
        return checklist
    }

    /// A bundle's PDF. A bundle that is gone answers with JSON, not bytes; anything that is not
    /// a PDF is treated as gone.
    func bundlePDF(id: Int) async throws -> Data {
        let request = try await client.makeRequest(
            "GET", "/filing/bundle-download", query: ["bundleId": String(id)])
        let (data, response) = try await client.perform(request)
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.classify(status: response.statusCode, body: data)
        }
        guard data.starts(with: Data("%PDF".utf8)) else {
            throw APIError.server(status: 404, message: "That bundle is no longer available.")
        }
        return data
    }

    // MARK: - Writes

    private struct AddBody: Encodable {
        let userId: String
        let draftId: String
        let folderName: String
        let fileName: String
    }

    private struct UpdateBody: Encodable {
        let userId: String
        let id: Int
        let title: String?
        let treatment: String?
        let verify_status: String?
    }

    private struct IDBody: Encodable {
        let userId: String
        let id: Int
    }

    private struct ReorderBody: Encodable {
        let userId: String
        let draftId: String
        let orderedIds: [Int]
    }

    private struct AssembleBody: Encodable {
        struct Options: Encodable { let numbering: String }
        let userId: String
        let draftId: String
        let cover: FilingCover
        let options: Options
    }

    private struct ChatAddBody: Encodable {
        let userId: String
        let chatId: String
        let folderName: String
        let fileName: String
    }

    private struct ChatAssembleBody: Encodable {
        let userId: String
        let chatId: String
        let draftHtml: String
        let draftTitle: String
        let cover: FilingCover
        let options: AssembleBody.Options
    }

    private func userID() async throws -> String {
        guard let credentials = await client.currentCredentials() else {
            throw APIError.notAuthenticated
        }
        return credentials.userIDString
    }

    /// Registers a file from My Files as the draft's next annexure. A file at the storage root
    /// is in the folder `"."`; the route refuses an empty folder.
    func addAnnexure(draftID: String, folderName: String, fileName: String) async throws -> FilingAnnexure {
        let body = AddBody(
            userId: try await userID(), draftId: draftID,
            folderName: folderName.isEmpty ? "." : folderName, fileName: fileName)
        let request = try await client.makeRequest("POST", "/filing/annexures", body: body)
        let response = try await client.send(request, as: FilingAnnexureResponse.self)
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        guard let annexure = response.annexure else {
            throw APIError.server(status: 200, message: "Could not add annexure")
        }
        return annexure
    }

    /// Changes an annexure's title, treatment or verification; only what is given is sent.
    func update(
        id: Int, title: String?, treatment: FilingTreatment?, verifyStatus: FilingVerify?
    ) async throws -> FilingAnnexure {
        let body = UpdateBody(
            userId: try await userID(), id: id, title: title, treatment: treatment?.rawValue,
            verify_status: verifyStatus?.rawValue)
        let request = try await client.makeRequest("POST", "/filing/annexures/update", body: body)
        let response = try await client.send(request, as: FilingAnnexureResponse.self)
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        guard let annexure = response.annexure else {
            throw APIError.server(status: 200, message: "Could not update the annexure")
        }
        return annexure
    }

    func delete(id: Int) async throws {
        let body = IDBody(userId: try await userID(), id: id)
        let request = try await client.makeRequest("POST", "/filing/annexures/delete", body: body)
        let response = try await client.send(request, as: FilingOKResponse.self)
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
    }

    /// Sets the binding order. Marks are never renumbered; the answer says whether the order
    /// still follows them.
    func reorder(draftID: String, orderedIDs: [Int]) async throws -> (Bool, [FilingAnnexure]) {
        let body = ReorderBody(userId: try await userID(), draftId: draftID, orderedIds: orderedIDs)
        let request = try await client.makeRequest("POST", "/filing/annexures/reorder", body: body)
        let response = try await client.send(request, as: FilingReorderResponse.self)
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        return (response.orderMatchesMarks ?? true, response.annexures ?? [])
    }

    /// Assembles the bundle. Once, never retried: every run makes a bundle of its own. A run
    /// the assembler refused comes back as a result with `success: false`, not as an error.
    func assemble(draftID: String, cover: FilingCover) async throws -> FilingAssemblyResult {
        let body = AssembleBody(
            userId: try await userID(), draftId: draftID, cover: cover,
            options: .init(numbering: "arabic"))
        return try await runAssembly(body)
    }

    /// Assembles the draft as it stands in the conversation, with the conversation's annexures.
    /// Once, never retried, as above; the bundle is listed under `chat:<id>`.
    func assemble(chatID: String, html: String, title: String, cover: FilingCover) async throws -> FilingAssemblyResult {
        let body = ChatAssembleBody(
            userId: try await userID(), chatId: chatID, draftHtml: html, draftTitle: title,
            cover: cover, options: .init(numbering: "arabic"))
        return try await runAssembly(body)
    }

    private func runAssembly(_ body: some Encodable & Sendable) async throws -> FilingAssemblyResult {
        let request = try await client.makeRequest("POST", "/filing/assemble", body: body)
        let (data, response) = try await client.perform(request)
        let status = response.statusCode
        // A rejected assembly is a 400 carrying every reason in `errors`; they are all shown,
        // so it is read as an answer, not thrown as the one-line `error`.
        if status == 400 {
            let rejected = try? JSONDecoder().decode(FilingAssemblyResult.self, from: data)
            if let rejected, !rejected.success { return rejected }
        }
        if !(200..<300).contains(status) {
            throw APIError.classify(status: status, body: data)
        }
        do {
            return try JSONDecoder().decode(FilingAssemblyResult.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    // MARK: - A conversation's annexures

    /// Registers a file the conversation carries as its next annexure. The same file twice
    /// answers with the annexure it already is.
    func addAnnexure(chatID: String, folderName: String, fileName: String) async throws -> FilingAnnexure {
        let body = ChatAddBody(
            userId: try await userID(), chatId: chatID,
            folderName: folderName.isEmpty ? "." : folderName, fileName: fileName)
        let request = try await client.makeRequest("POST", "/filing/annexures", body: body)
        let response = try await client.send(request, as: FilingAnnexureResponse.self)
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        guard let annexure = response.annexure else {
            throw APIError.server(status: 200, message: "Could not add annexure")
        }
        return annexure
    }

    /// One annexure's typed true copy, or why there is none (an original is not typed).
    func typedCopy(chatID: String, mark: String) async throws -> FilingTypedCopy {
        let response = try await withRetry {
            let request = try await client.makeRequest(
                "GET", "/filing/annexures/typed-copy", query: ["chatId": chatID, "mark": mark])
            return try await client.send(request, as: FilingTypedCopyResponse.self)
        }
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        if response.skipped == true {
            return FilingTypedCopy(html: nil, skipped: true, reason: response.reason)
        }
        return FilingTypedCopy(html: response.html, skipped: false, reason: nil)
    }

    /// The original file behind an annexure — its cited pages of a PDF, or the image. A kind of
    /// file that cannot be shown is `FilingPreviewError.unpreviewable`.
    func original(chatID: String, mark: String) async throws -> FilingOriginal {
        let request = try await client.makeRequest(
            "GET", "/filing/annexures/original", query: ["chatId": chatID, "mark": mark])
        let (data, response) = try await client.perform(request)
        let status = response.statusCode
        if status == 415 { throw FilingPreviewError.unpreviewable }
        guard (200..<300).contains(status) else {
            throw APIError.classify(status: status, body: data)
        }
        let header = response.value(forHTTPHeaderField: "Content-Type") ?? ""
        return FilingOriginal(data: data, mime: FilingOriginal.mime(fromContentType: header))
    }

    /// Every page of an annexure's original as an image — or, for a mark that repeats an
    /// earlier one, which mark it repeats. Read whatever the status, as the page reads it: a
    /// failure carries the sentence to show in place of the pages.
    func originalPages(chatID: String, mark: String) async throws -> FilingOriginalPages {
        let request = try await client.makeRequest(
            "GET", "/filing/annexures/original-pages", query: ["chatId": chatID, "mark": mark])
        let (data, response) = try await client.perform(request)
        if let pages = try? JSONDecoder().decode(FilingOriginalPages.self, from: data) {
            return pages
        }
        throw APIError.classify(status: response.statusCode, body: data)
    }

    /// The typed copies of every typed annexure in the conversation, as one piece of HTML; empty
    /// when there are none.
    func typedCopies(chatID: String) async throws -> String {
        let response = try await withRetry {
            let request = try await client.makeRequest(
                "GET", "/filing/annexures/typed-copies", query: ["chatId": chatID])
            return try await client.send(request, as: FilingTypedCopiesResponse.self)
        }
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        return response.html ?? ""
    }

    /// What a stand-in without a conversation's routes answers.
    static let unavailable = APIError.server(status: 404, message: "not found")
}
