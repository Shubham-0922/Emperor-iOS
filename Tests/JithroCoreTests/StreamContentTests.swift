import XCTest
@testable import JithroCore

/// The server stores and streams answers with every control tag left in — stripping is
/// entirely the client's job. These pin what a practitioner should actually end up reading.
final class StreamContentTests: XCTestCase {

    func testPlainProsePassesThroughUntouched() {
        let content = StreamContent.parse("The Plaintiff's claim under Section 4 fails.")
        XCTAssertEqual(content.prose, "The Plaintiff's claim under Section 4 fails.")
        XCTAssertTrue(content.artifacts.isEmpty)
    }

    func testReasoningIsSeparatedFromProse() {
        let content = StreamContent.parse(
            "<think>The limitation point turns on Article 58.</think>The suit is barred.")
        XCTAssertEqual(content.reasoning, ["The limitation point turns on Article 58."])
        XCTAssertEqual(content.prose, "The suit is barred.")
    }

    /// A drafted document is delivered as a trigger line plus a body, and belongs in a side
    /// panel rather than inline in the transcript.
    func testCanvasArtifactIsExtractedWithItsTitle() {
        let content = StreamContent.parse("""
        Here is the petition.
        [CANVAS_TRIGGER: Writ Petition]
        <canvas_content><h1>IN THE HIGH COURT</h1></canvas_content>
        """)

        XCTAssertEqual(content.artifacts.count, 1)
        XCTAssertEqual(content.artifacts.first?.kind, .canvas)
        XCTAssertEqual(content.artifacts.first?.title, "Writ Petition")
        XCTAssertEqual(content.artifacts.first?.body, "<h1>IN THE HIGH COURT</h1>")
        XCTAssertEqual(content.prose, "Here is the petition.")
    }

    func testTableArtifactIsExtracted() {
        let content = StreamContent.parse(
            "[TABLE_TRIGGER: Chronology]<table_content>| Date | Event |</table_content>")
        XCTAssertEqual(content.artifacts.first?.kind, .table)
        XCTAssertEqual(content.artifacts.first?.title, "Chronology")
        XCTAssertEqual(content.prose, "")
    }

    /// Two documents in one answer must not cross-attach titles to bodies.
    func testMultipleArtifactsKeepTheirOwnTitles() {
        let content = StreamContent.parse("""
        [CANVAS_TRIGGER: First]<canvas_content>one</canvas_content>
        [CANVAS_TRIGGER: Second]<canvas_content>two</canvas_content>
        """)
        XCTAssertEqual(content.artifacts.map(\.title), ["First", "Second"])
        XCTAssertEqual(content.artifacts.map(\.body), ["one", "two"])
    }

    /// A trigger line whose body has not streamed in yet must not flash as prose.
    func testOrphanTriggerLineIsNotShownAsProse() {
        let content = StreamContent.parse("Drafting now.\n[CANVAS_TRIGGER: Writ Petition]")
        XCTAssertEqual(content.prose, "Drafting now.")
        XCTAssertTrue(content.artifacts.isEmpty)
    }

    /// A tag arriving a few characters at a time must not render half-open.
    func testPartialTrailingTagIsHidden() {
        let content = StreamContent.parse("The order is dated 4 March.<canvas_c")
        XCTAssertEqual(content.prose, "The order is dated 4 March.")
    }

    /// …but a mathematical or textual `<` is prose and must survive.
    func testLiteralAngleBracketInProseSurvives() {
        let content = StreamContent.parse("The claim is valid where damages < 50,000 rupees.")
        XCTAssertEqual(content.prose, "The claim is valid where damages < 50,000 rupees.")
    }

    func testPlanIsDecoded() {
        let content = StreamContent.parse("""
        <plan>{"tasks":[{"title":"Read the file","subtasks":[{"label":"Open paperbook","tools":["read"]}]}]}</plan>Working.
        """)
        XCTAssertEqual(content.plan?.tasks.first?.title, "Read the file")
        XCTAssertEqual(content.plan?.tasks.first?.subtasks?.first?.label, "Open paperbook")
        XCTAssertEqual(content.prose, "Working.")
    }

    func testFollowUpQueriesAreDecoded() {
        let content = StreamContent.parse(
            "Done.<follow-up-queries>[\"What is the limitation period?\",\"Who signed it?\"]</follow-up-queries>")
        XCTAssertEqual(content.followUps.count, 2)
        XCTAssertEqual(content.prose, "Done.")
    }

    /// The provider writes failures as bracketed prose once the response is already
    /// streaming, because the status line is long gone by then.
    func testInBandErrorIsSurfacedSeparately() {
        let content = StreamContent.parse("Partial answer.\n\n[Error: upstream timed out]")
        XCTAssertEqual(content.errors, ["Error: upstream timed out"])
        XCTAssertEqual(content.prose, "Partial answer.")
    }

    func testServerErrorVariantIsAlsoCaught() {
        let content = StreamContent.parse("Text.\n\n[Server Error: database is locked]")
        XCTAssertEqual(content.errors, ["Server Error: database is locked"])
    }

    /// The interrupted marker only exists on the persisted copy, so this is the signal when
    /// loading history rather than when streaming.
    func testInterruptedMarkerIsDetected() {
        let content = StreamContent.parse("""
        The draft stops here.

        ---
        ⚠️ **This response was interrupted and is incomplete.** Nothing above has been lost.
        """)
        XCTAssertTrue(content.wasInterrupted)
    }

    func testCleanAnswerIsNotFlaggedInterrupted() {
        XCTAssertFalse(StreamContent.parse("A complete answer.").wasInterrupted)
    }
}
