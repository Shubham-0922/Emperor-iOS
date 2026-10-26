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
