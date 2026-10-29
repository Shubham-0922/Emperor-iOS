import XCTest
@testable import EmperorCore

/// The line under an answer: "2 citations · checked against source", worded as the web's
/// `CitationMeta`, one question per file and quote.
final class CitationCheckTests: XCTestCase {

    private static let quoteA = "the lessee shall pay the monthly rent"
    private static let quoteB = "the vendor hereby conveys the property"

    private static func answer(_ refs: [String]) -> String {
        "The answer [1].\n\n## References\n\n" + refs.enumerated()
            .map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n")
    }

    // MARK: - Classification

    func testEachOutcomeIsClassifiedAsTheWebClassifiesIt() {
        let q = Self.quoteA
        XCTAssertEqual(CitationOutcome.classify(ResolvedFile(found: false), quote: q), .missing)
        XCTAssertEqual(CitationOutcome.classify(resolvedFile("a.pdf", page: 3), quote: q), .verified)
        XCTAssertEqual(CitationOutcome.classify(resolvedFile("a.pdf", page: nil, status: "mismatch"), quote: q), .unverified)
        XCTAssertEqual(CitationOutcome.classify(resolvedFile("a.pdf", page: 3), quote: ""), .unchecked)
        XCTAssertEqual(CitationOutcome.classify(resolvedFile("a.pdf", page: 3), quote: "  too short  "), .unchecked)
        XCTAssertEqual(
            CitationOutcome.classify(resolvedFile("a.pdf", page: 3, status: "too_short"), quote: q), .unchecked,
            "the server's own verdict counts too")
    }

    func testTheWordingForEveryMixOfOutcomes() {
        func label(_ o: [CitationOutcome]) -> CitationCheck.State { CitationCheck.summary(o) }
        XCTAssertEqual(label([.verified]), .done(label: "1 citation · checked against source", tone: .ok))
        XCTAssertEqual(label([.verified, .verified]), .done(label: "2 citations · checked against source", tone: .ok))
        XCTAssertEqual(label([.verified, .unchecked, .unknown]), .done(label: "3 citations · 1 checked against source", tone: .ok))
        XCTAssertEqual(label([.missing]), .done(label: "1 citation · not found in its source", tone: .warn))
        XCTAssertEqual(label([.unverified, .missing]), .done(label: "2 citations · none found in their sources", tone: .warn))
        XCTAssertEqual(label([.unverified, .verified, .verified]), .done(label: "3 citations · 1 not found in its source", tone: .warn))
        XCTAssertEqual(label([.unverified, .missing, .verified]), .done(label: "3 citations · 2 not found in their sources", tone: .warn))
        XCTAssertEqual(label([.unchecked, .unknown]), .done(label: "2 citations", tone: .plain))
    }

    // MARK: - Running

    func testAnAnswerCitingNoDocumentShowsNothing() async {
        await withCheck(content: "Vishaka [1].\n\n[1] Vishaka v. State of Rajasthan, (1997) 6 SCC 241") { fake, check in
            XCTAssertFalse(check.isVisible)
            await check.run()
            XCTAssertTrue(fake.resolves.isEmpty)
        }
    }

    func testItSaysCheckingUntilTheAnswersArrive() async {
        await withCheck(content: Self.answer([#"Lease.pdf, p. 2 — "\#(Self.quoteA)""#])) { fake, check in
            fake.files["Lease.pdf"] = resolvedFile("Lease.pdf", page: 2, status: "verified")
            XCTAssertEqual(check.label, "1 citation · checking against source…")
            XCTAssertEqual(check.tone, .plain)
            await check.run()
            XCTAssertEqual(check.label, "1 citation · checked against source")
            XCTAssertEqual(check.tone, .ok)
            XCTAssertEqual(fake.resolves, [.init(name: "Lease.pdf", quote: Self.quoteA, projectID: nil)])
        }
    }

    func testOneRequestPerFileAndQuote() async {
        let cache = CitationCheckCache()
        let content = Self.answer([
            #"Lease.pdf, p. 2 — "\#(Self.quoteA)""#,
            #"Deed.pdf, p. 4 — "\#(Self.quoteB)""#,
        ])
        await withCheck(content: content, cache: cache) { fake, first in
            fake.files["Lease.pdf"] = resolvedFile("Lease.pdf", page: 2)
            fake.files["Deed.pdf"] = resolvedFile("Deed.pdf", page: nil)
            await first.run()
            XCTAssertEqual(first.label, "2 citations · 1 not found in its source")
            // The same answer drawn again — and another answer citing the same lease.
            let again = CitationCheck(content: content, resolver: fake, projectID: nil, cache: cache)
            await again.run()
            let other = CitationCheck(
                content: Self.answer([#"Lease.pdf, p. 9 — "\#(Self.quoteA)""#]), resolver: fake,
                projectID: nil, cache: cache)
            await other.run()
            XCTAssertEqual(fake.resolves.count, 2, "asked once per file and quote")
            XCTAssertEqual(again.label, first.label)
        }
    }

    func testTwoChecksAtOnceShareOneRequest() async {
        let cache = CitationCheckCache()
        let content = Self.answer([#"Lease.pdf, p. 2 — "\#(Self.quoteA)""#])
        await withCheck(content: content, cache: cache) { fake, first in
            fake.files["Lease.pdf"] = resolvedFile("Lease.pdf", page: 2)
            fake.delay = .milliseconds(50)
            let second = CitationCheck(content: content, resolver: fake, projectID: nil, cache: cache)
            async let a: Void = first.run()
            async let b: Void = second.run()
            _ = await (a, b)
            XCTAssertEqual(fake.resolves.count, 1)
            XCTAssertEqual(second.label, "1 citation · checked against source")
        }
    }

    func testTheMatterIsSentAndChangesTheKey() async {
        let cache = CitationCheckCache()
        let content = Self.answer([#"Lease.pdf, p. 2 — "\#(Self.quoteA)""#])
        await withCheck(content: content, projectID: "12", cache: cache) { fake, inMatter in
            fake.files["Lease.pdf"] = resolvedFile("Lease.pdf", page: 2)
            await inMatter.run()
            let outside = CitationCheck(content: content, resolver: fake, projectID: nil, cache: cache)
            await outside.run()
            XCTAssertEqual(fake.resolves.map(\.projectID), ["12", nil])
        }
    }

    func testAFailedCheckIsAskedAgainNextTime() async {
        let cache = CitationCheckCache()
        let content = Self.answer([#"Lease.pdf, p. 2 — "\#(Self.quoteA)""#])
        await withCheck(content: content, cache: cache) { fake, first in
            fake.resolveError = APIError.transport("offline")
            await first.run()
            XCTAssertEqual(first.label, "1 citation")
            XCTAssertEqual(first.tone, .plain)
            fake.resolveError = nil
            fake.files["Lease.pdf"] = resolvedFile("Lease.pdf", page: 2)
            let again = CitationCheck(content: content, resolver: fake, projectID: nil, cache: cache)
            await again.run()
            XCTAssertEqual(again.label, "1 citation · checked against source")
            XCTAssertEqual(fake.resolves.count, 2)
        }
    }

    func testWithoutAResolverTheCountStandsAlone() async {
        await withCheck(content: Self.answer(["Lease.pdf, p. 2"]), resolver: false) { _, check in
            await check.run()
            XCTAssertEqual(check.label, "1 citation")
        }
    }
}

@MainActor
private func withCheck(
    content: String, projectID: String? = nil, cache: CitationCheckCache = CitationCheckCache(),
    resolver: Bool = true,
    _ body: @MainActor (FakeCitedSources, CitationCheck) async -> Void
) async {
    let fake = FakeCitedSources()
    await body(fake, CitationCheck(
        content: content, resolver: resolver ? fake : nil, projectID: projectID, cache: cache))
}
