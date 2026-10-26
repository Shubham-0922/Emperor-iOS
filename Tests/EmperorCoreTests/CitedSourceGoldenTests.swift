import XCTest
@testable import EmperorCore

/// `CitedSource` held to the platform's own `src/lib/citedSource.js`
/// (`scripts/generate-cited-source-fixtures.mjs`). Regenerate on a platform change; never edit.
final class CitedSourceGoldenTests: XCTestCase {

    private struct Ref: Decodable, Equatable {
        var file: String
        var page: Int?
        var quote: String
    }
    private struct Doc: Decodable { var n: Int; var file: String; var page: Int?; var quote: String }
    private struct Range: Decodable { var start: Int; var end: Int }
    private struct Fixture: Decodable {
        struct Parse: Decodable { var text: String; var ref: Ref? }
        struct Docs: Decodable { var content: String; var docs: [Doc] }
        struct Norm: Decodable { var text: String; var norm: String }
        struct Find: Decodable { var id: String; var words: [String]; var quote: String; var range: Range? }
        struct Rects: Decodable {
            var id: String; var boxes: [[Double]]; var start: Int; var end: Int; var rects: [[Double]]
        }
        var parse: [Parse]
        var docs: [Docs]
        var norm: [Norm]
        var find: [Find]
        var rects: [Rects]
    }

    private func load() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: try parityFixture("p7", "cited-source"))
    }

    private func box(_ a: [Double]) -> QuoteBox { QuoteBox(x0: a[0], y0: a[1], x1: a[2], y1: a[3]) }

    func testReferenceLinesParseAsTheWebParsesThem() throws {
        let f = try load()
        XCTAssertGreaterThan(f.parse.count, 20)
        for c in f.parse {
            let ours = CitedSource.parse(c.text).map { Ref(file: $0.file, page: $0.page, quote: $0.quote) }
            XCTAssertEqual(ours, c.ref, c.text)
        }
    }

    func testAnAnswersCitedDocumentsMatchTheWebs() throws {
        for c in try load().docs {
            let ours = CitedSource.citedDocs(c.content)
            XCTAssertEqual(ours.map(\.number), c.docs.map(\.n), c.content)
            XCTAssertEqual(ours.map(\.ref.file), c.docs.map(\.file), c.content)
            XCTAssertEqual(ours.map(\.ref.page), c.docs.map(\.page), c.content)
            XCTAssertEqual(ours.map(\.ref.quote), c.docs.map(\.quote), c.content)
        }
    }

    func testCharactersNormaliseAsTheWebsDo() throws {
        for c in try load().norm {
            XCTAssertEqual(CitedSource.normChars(c.text), c.norm, c.text)
        }
    }

    func testQuotesAreFoundOnTheSameWords() throws {
        for c in try load().find {
            let ours = CitedSource.findQuoteRange(words: c.words, quote: c.quote)
            XCTAssertEqual(ours?.lowerBound, c.range?.start, c.id)
            XCTAssertEqual(ours?.upperBound, c.range?.end, c.id)
        }
    }

    func testAFoundQuoteIsMarkedLineByLine() throws {
        for c in try load().rects {
            let ours = CitedSource.lineRects(c.boxes.map(box), c.start...c.end)
            XCTAssertEqual(ours, c.rects.map(box), c.id)
        }
    }
}
