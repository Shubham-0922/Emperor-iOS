import XCTest
@testable import EmperorCore

/// Filing's ported rules held to the platform's own code (`scripts/generate-filing-fixtures.mjs`):
/// marks and their order, the forum the assembler reads, and the assembly-error list.
/// Regenerate on a platform change; never edit.
final class FilingGoldenTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Parse: Decodable { var input: String?; var side: String; var number: Int }
        struct Compare: Decodable { var a: String; var b: String; var sign: Int }
        struct Sort: Decodable { var input: [String]; var sorted: [String]; var inOrder: Bool }
        struct Marks: Decodable { var parse: [Parse]; var compare: [Compare]; var sort: [Sort] }
        struct Forum: Decodable { var input: String?; var normalized: String? }
        struct ErrorList: Decodable { var input: JSONValue; var output: [String] }
        var forumOptions: [String]
        var marks: Marks
        var forums: [Forum]
        var errorLists: [ErrorList]
    }

    private func load() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: try parityFixture("13-F", "filing"))
    }

    func testForumSuggestionsAreThePagesInOrder() throws {
        let f = try load()
        XCTAssertEqual(FilingForum.suggestions, f.forumOptions)
        XCTAssertEqual(Array(FilingForum.suggestions.prefix(4)), FilingForum.supported)
    }

    func testMarksParseAsThePageParsesThem() throws {
        let f = try load()
        XCTAssertFalse(f.marks.parse.isEmpty)
        for c in f.marks.parse {
            let parsed = FilingMarks.parse(c.input)
            XCTAssertEqual(parsed.side, c.side, String(describing: c.input))
            XCTAssertEqual(parsed.number, c.number, String(describing: c.input))
        }
    }

    func testMarksCompareAsThePageComparesThem() throws {
        for c in try load().marks.compare {
            XCTAssertEqual(FilingMarks.compare(c.a, c.b).signum(), c.sign, "\(c.a) vs \(c.b)")
        }
    }

    func testMarkOrderAndItsCheckMatchThePage() throws {
        for c in try load().marks.sort {
            XCTAssertEqual(FilingMarks.sorted(c.input), c.sorted, "\(c.input)")
            XCTAssertEqual(FilingMarks.isInMarkOrder(c.input), c.inOrder, "\(c.input)")
        }
    }

    func testForumsNormaliseAsTheAssemblerReadsThem() throws {
        let f = try load()
        XCTAssertGreaterThan(f.forums.count, 20)
        for c in f.forums {
            XCTAssertEqual(FilingForum.normalize(c.input), c.normalized, String(describing: c.input))
        }
    }

    func testAssemblyErrorsFlattenAsThePageFlattensThem() throws {
        let f = try load()
        for c in f.errorLists {
            let data = try JSONEncoder().encode(c.input)
            let result = try JSONDecoder().decode(FilingAssemblyResult.self, from: data)
            XCTAssertEqual(result.errorList, c.output, "\(c.input)")
            XCTAssertEqual(
                result.errorLines,
                c.output.isEmpty ? [FilingAssemblyResult.unknownError] : c.output)
        }
    }
}

/// Filing from a conversation's draft held to the platform's own code: the cover read from the
/// cause title, the conversation's files offered as annexures, mentions stripped, and the
/// "Filing ready" package — its markup and its progress — built from the same answers.
final class FilingChatGoldenTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Cover: Decodable { var html: String; var cover: FilingCover }
        struct File: Decodable { var name: String?; var folderName: String? }
        struct Path: Decodable { var source_file_path: String? }
        struct Seed: Decodable { var attachedFiles: [File]; var annexures: [Path]; var seed: [File] }
        struct Mention: Decodable { var input: String; var output: String }
        var covers: [Cover]
        var seeds: [Seed]
        var mentions: [Mention]
    }

    private func load() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: try parityFixture("13-F", "filing"))
    }

    func testCoversAreReadFromTheCauseTitleAsThePageReadsThem() throws {
        let f = try load()
        XCTAssertGreaterThanOrEqual(f.covers.count, 15)
        for c in f.covers {
            XCTAssertEqual(FilingChatScope.deriveCover(html: c.html), c.cover, c.html)
        }
    }

    func testTheConversationsFilesAreOfferedAsThePageOffersThem() throws {
        for c in try load().seeds {
            let files = c.attachedFiles.map { ChatAttachment(name: $0.name ?? "", folderName: $0.folderName) }
            let paths = c.annexures.map { $0.source_file_path ?? "" }
            let seed = FilingChatScope.unannexed(attachments: files, annexurePaths: paths)
            XCTAssertEqual(seed.map(\.name), c.seed.map { $0.name ?? "" })
            XCTAssertEqual(seed.map { $0.folderName ?? "" }, c.seed.map { $0.folderName ?? "" })
        }
    }

    func testMentionsAreStrippedAsTheRegisterStripsThem() throws {
        for c in try load().mentions {
            XCTAssertEqual(FilingChatScope.stripMentions(c.input), c.output, c.input)
        }
    }

    func testFilingReadyIsTheWebsPackage() async throws {
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try parityFixture("13-F", "filing")) as? [String: Any])
        let cases = try XCTUnwrap(root["ready"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 5)
        for c in cases {
            let name = c["name"] as? String ?? ""
            let register = GoldenRegister(c)
            let draft = c["draft"] as? String ?? ""
            let (html, progress) = await buildFilingReady(register, draft: draft)
            XCTAssertEqual(html, c["html"] as? String, name)
            XCTAssertEqual(progress, c["progress"] as? [Int], name)
        }
    }
}

@MainActor
private func buildFilingReady(_ register: GoldenRegister, draft: String) async -> (String, [Int]) {
    let context = FilingChatContext(chatID: "c1", draftTitle: "Writ", draftHTML: draft, attachments: [])
    let model = FilingReadyExportModel(service: register, context: context)
    let package = await model.build(.word)
    return (package.html, model.progressHistory)
}

/// The annexure routes answering as one fixture case says, read through the same envelopes the
/// service reads.
private final class GoldenRegister: FilingProviding, @unchecked Sendable {
    private let annexuresAnswer: Any
    private let typedAnswer: Any
    private let pages: [String: Any]

    init(_ c: [String: Any]) {
        annexuresAnswer = c["annexures"] ?? "throw"
        typedAnswer = c["typedCopies"] ?? "throw"
        pages = c["pages"] as? [String: Any] ?? [:]
    }

    /// The body of an answer and its status, or `nil` for one that was lost.
    private func body(_ spec: Any) throws -> (Data, Int)? {
        if spec as? String == "throw" { return nil }
        guard let object = spec as? [String: Any] else { return nil }
        if let status = object["status"] as? Int, let inner = object["body"] {
            return (try JSONSerialization.data(withJSONObject: inner), status)
        }
        return (try JSONSerialization.data(withJSONObject: object), 200)
    }

    private static let lost = APIError.transport("network")

    func annexures(draftID: String?, chatID: String?) async throws -> [FilingAnnexure] {
        guard let (data, status) = try body(annexuresAnswer) else { throw Self.lost }
        guard status == 200 else { throw APIError.classify(status: status, body: data) }
        let response = try JSONDecoder().decode(FilingAnnexuresResponse.self, from: data)
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        return response.annexures ?? []
    }

    func typedCopies(chatID: String) async throws -> String {
        guard let (data, status) = try body(typedAnswer) else { throw Self.lost }
        guard status == 200 else { throw APIError.classify(status: status, body: data) }
        let response = try JSONDecoder().decode(FilingTypedCopiesResponse.self, from: data)
        try CaseService.throwIfUnsuccessful(success: response.success, error: response.error)
        return response.html ?? ""
    }

    func originalPages(chatID: String, mark: String) async throws -> FilingOriginalPages {
        guard let spec = pages[mark], let (data, _) = try body(spec) else { throw Self.lost }
        return try JSONDecoder().decode(FilingOriginalPages.self, from: data)
    }

    func drafts() async throws -> [FilingDraft] { throw Self.lost }
    func addAnnexure(draftID: String, folderName: String, fileName: String) async throws -> FilingAnnexure {
        throw Self.lost
    }
    func update(
        id: Int, title: String?, treatment: FilingTreatment?, verifyStatus: FilingVerify?
    ) async throws -> FilingAnnexure { throw Self.lost }
    func delete(id: Int) async throws { throw Self.lost }
    func reorder(draftID: String, orderedIDs: [Int]) async throws -> (Bool, [FilingAnnexure]) {
        throw Self.lost
    }
    func assemble(draftID: String, cover: FilingCover) async throws -> FilingAssemblyResult {
        throw Self.lost
    }
    func bundles(draftID: String?) async throws -> [FilingBundle] { throw Self.lost }
    func bundlePDF(id: Int) async throws -> Data { throw Self.lost }
    func checklist(draftID: String, forum: String) async throws -> FilingChecklist { throw Self.lost }
}
