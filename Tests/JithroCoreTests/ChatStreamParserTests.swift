import XCTest
@testable import JithroCore

/// These pin the hand-rolled `/chat` wire format. Every case below is a behaviour the
/// server actually produces, cited to the emperor-ai source that produces it.
final class ChatStreamParserTests: XCTestCase {

    private func feed(_ parser: ChatStreamParser, _ chunks: [String]) -> [ChatStreamEvent] {
        var events: [ChatStreamEvent] = []
        for chunk in chunks { events += parser.consume(text: chunk) }
        events += parser.finish()
        return events
    }

    // MARK: - Status extraction

    func testStatusTagsNeverReachTheAnswer() {
        let parser = ChatStreamParser()
        let events = feed(parser, ["<status>Preparing...</status>The Plaintiff"])

        XCTAssertEqual(events.first, .status("Preparing..."))
        XCTAssertEqual(parser.raw, "The Plaintiff")
    }

    /// The server writes several statuses inside one chunk when it reads multiple files.
    func testMultipleStatusesInOneChunk() {
        let parser = ChatStreamParser()
        _ = feed(parser, ["<status>Reading: a.pdf</status><status>Thinking...</status>Answer"])
        XCTAssertEqual(parser.raw, "Answer")
    }

    /// A chunk boundary landing inside a status tag must not leak the fragment.
    /// The web client splits only on the full literal `"<status"`, so `"<sta"` escapes there
    /// (src/lib/api.js:132). We hold back on any prefix of `"<status>"`.
    func testStatusTagSplitAcrossChunkBoundary() {
        let parser = ChatStreamParser()
        _ = feed(parser, ["Before<sta", "tus>Reading: x.pdf</status>After"])
        XCTAssertEqual(parser.raw, "BeforeAfter")
    }

    func testStatusSplitImmediatelyAfterOpeningBracket() {
        let parser = ChatStreamParser()
        _ = feed(parser, ["Before<", "status>Thinking...</status>After"])
        XCTAssertEqual(parser.raw, "BeforeAfter")
    }

    /// A held-back `<` that turns out to be prose, not a tag, must be released.
    func testLoneAngleBracketIsNotSwallowed() {
        let parser = ChatStreamParser()
        _ = feed(parser, ["where x < ", "y applies"])
        XCTAssertEqual(parser.raw, "where x < y applies")
    }

    /// A stream that dies mid-tag still has to yield its prose. The web client drops this
    /// tail on the floor because its loop simply ends.
    func testUnterminatedStatusIsFlushedAtEndOfStream() {
        let parser = ChatStreamParser()
        _ = feed(parser, ["Answer text<status>Thinking"])
        XCTAssertTrue(parser.raw.hasPrefix("Answer text"))
    }

    // MARK: - Rollback

    /// `<truncate:N/>` rolls back a retried round. Without it the retry double-renders.
    func testTruncateRollsBackToOffset() {
        let parser = ChatStreamParser()
        _ = feed(parser, ["Good start.", "BAD ATTEMPT<truncate:11/>", "Real answer."])
        XCTAssertEqual(parser.raw, "Good start.Real answer.")
    }

    /// N is a UTF-16 offset because the server computes it with JavaScript `.length`.
    /// An emoji is two UTF-16 units but one Swift Character, so a Character-based slice
    /// would cut in the wrong place.
    func testTruncateOffsetIsUTF16NotCharacters() {
        let parser = ChatStreamParser()
        // "⚖️" is U+2696 U+FE0F — 2 UTF-16 units, 1 Character.
        let prefix = "⚖️ok"                       // 4 UTF-16 units, 3 Characters
        XCTAssertEqual(prefix.utf16.count, 4)
        _ = feed(parser, [prefix + "junk<truncate:4/>", "tail"])
        XCTAssertEqual(parser.raw, prefix + "tail")
    }

    func testTruncateBeyondBufferIsClamped() {
        let parser = ChatStreamParser()
        _ = feed(parser, ["short<truncate:9999/>"])
        XCTAssertEqual(parser.raw, "short")
    }

    // MARK: - Busy refusal

    /// A second send on a chat that is still generating is answered 200, with the refusal
    /// arriving as a status tag ahead of its own explanation (sync-server.js:7256-7276).
    /// The explanation must not land in the transcript.
    func testBusyRefusalIsDivertedFromTheAnswer() {
        let parser = ChatStreamParser()
        let events = feed(parser, [
            "<status>Still drafting your earlier request</status>",
            "Your draft for this chat is still being generated (3m 12s so far).",
        ])

        XCTAssertTrue(events.contains(.busy))
        XCTAssertTrue(parser.isBusy)
        XCTAssertEqual(parser.raw, "")
        XCTAssertTrue(parser.busyNotice.contains("still being generated"))
    }

    // MARK: - Usage

    /// Written once, last, immediately before the response ends.
    func testUsageIsLiftedOutOfContent() {
        let parser = ChatStreamParser()
        let events = feed(parser, ["Answer.\n<usage>{\"total_tokens\":42,\"cost\":0.0141}</usage>"])

        XCTAssertEqual(parser.raw.trimmingCharacters(in: .whitespacesAndNewlines), "Answer.")
        let usage = events.compactMap { if case .usage(let u) = $0 { return u } else { return nil } }.first
        XCTAssertEqual(usage?["total_tokens"]?.intValue, 42)
    }

    /// `<usage>` is only written `if (finalUsage)`, so it is not a terminator.
    func testStreamWithoutUsageStillCompletes() {
        let parser = ChatStreamParser()
        _ = feed(parser, ["Answer with no usage block."])
        XCTAssertEqual(parser.raw, "Answer with no usage block.")
    }

    // MARK: - UTF-8 boundaries

    /// Chunk boundaries fall mid-character routinely on Devanagari and ₹.
    func testMultiByteCharacterSplitAcrossChunks() {
        let parser = ChatStreamParser()
        let text = "देखिए ₹1,00,000"
        var bytes = Array(Data(text.utf8))
        var events: [ChatStreamEvent] = []
        // Feed one byte at a time — the worst case for a naive decoder.
        while !bytes.isEmpty {
            events += parser.consume(Data([bytes.removeFirst()]))
        }
        events += parser.finish()
        XCTAssertEqual(parser.raw, text)
    }
}
