import XCTest
@testable import EmperorCore

/// The cases `scripts/generate-liverun-fixtures.mjs` records by running the web's own
/// `src/lib/liveRun.js`: each is one call, its input and what it returned.
private struct LiveRunFixture: Decodable {
    struct Constants: Decodable {
        let pollMinMs: Int
        let pollMaxMs: Int
        let watchMaxMs: Int
        let maxPollFailures: Int
    }
    struct Case: Decodable {
        let fn: String
        let input: JSONValue
        let expected: JSONValue
    }

    let constants: Constants
    let cases: [Case]

    static let shared: LiveRunFixture = {
        do {
            return try JSONDecoder().decode(LiveRunFixture.self, from: Data(LiveRunGolden.json.utf8))
        } catch {
            fatalError("LiveRunGolden.json does not decode: \(error)")
        }
    }()

    func cases(_ fn: String) -> [Case] { cases.filter { $0.fn == fn } }
}

private func decode<T: Decodable>(_ type: T.Type, _ value: JSONValue?) throws -> T {
    let data = try JSONEncoder().encode(try XCTUnwrap(value))
    return try JSONDecoder().decode(T.self, from: data)
}

final class LiveRunTests: XCTestCase {
    private let fixture = LiveRunFixture.shared

    private func label(_ c: LiveRunFixture.Case) -> String {
        c.input["name"]?.stringValue ?? "\(c.input)"
    }

    func testTheFixtureIsNotEmpty() {
        for fn in ["isRunLive", "followDecision", "nextPollDelay", "formatElapsed", "liveStatusText",
                   "logFromStatusLines", "liveContent", "runOutcome", "failureText"] {
            XCTAssertFalse(fixture.cases(fn).isEmpty, fn)
        }
    }

    func testConstantsMatchTheWeb() {
        XCTAssertEqual(LiveRun.pollMinMs, fixture.constants.pollMinMs)
        XCTAssertEqual(LiveRun.pollMaxMs, fixture.constants.pollMaxMs)
        XCTAssertEqual(LiveRun.watchMaxMs, fixture.constants.watchMaxMs)
        XCTAssertEqual(LiveRun.maxPollFailures, fixture.constants.maxPollFailures)
    }

    func testIsRunLive() throws {
        for c in fixture.cases("isRunLive") {
            let status = try decode(StreamStatus.self, c.input["status"])
            XCTAssertEqual(LiveRun.isRunLive(status), c.expected == .bool(true), label(c))
        }
    }

    func testFollowDecision() throws {
        for c in fixture.cases("followDecision") {
            let status = try decode(StreamStatus.self, c.input["status"])
            let messages = try decode([ChatMessage].self, c.input["messages"])
            let decision = LiveRun.followDecision(messages: messages, status: status)
            XCTAssertEqual(decision.rawValue, c.expected.stringValue, label(c))
        }
    }

    func testNoAnswerAtAllIsNeverAFailure() {
        XCTAssertEqual(LiveRun.followDecision(messages: [ChatMessage(role: .user, content: "q")], status: nil), .idle)
    }

    func testNextPollDelay() {
        for c in fixture.cases("nextPollDelay") {
            let previous = c.input["prevMs"]?.intValue
            let changed = c.input["changed"] == .bool(true)
            XCTAssertEqual(LiveRun.nextPollDelay(previousMs: previous, changed: changed),
                           c.expected.intValue, "\(c.input)")
        }
    }

    func testFormatElapsed() {
        for c in fixture.cases("formatElapsed") {
            let ms = c.input["ms"]?.doubleValue ?? 0
            XCTAssertEqual(LiveRun.formatElapsed(ms), c.expected.stringValue, "\(ms)")
        }
    }

    func testLiveStatusText() throws {
        for c in fixture.cases("liveStatusText") {
            let status = try decode(StreamStatus.self, c.input["status"])
            let friendly = c.input["friendly"]?.stringValue ?? ""
            XCTAssertEqual(LiveRun.liveStatusText(status, friendly: friendly), c.expected.stringValue, label(c))
        }
    }

    func testElapsedFallsBackToTheStartTime() throws {
        let status = try JSONDecoder().decode(
            StreamStatus.self, from: Data(#"{"active":true,"startedAt":1000000}"#.utf8))
        let now = Date(timeIntervalSince1970: 1_192)
        XCTAssertEqual(LiveRun.liveStatusText(status, now: now), "Working on your request… · 3m 12s")
        XCTAssertEqual(LiveRun.liveStatusText(StreamStatus(active: true)), "Working on your request…")
    }

    func testLogFromStatusLines() throws {
        for c in fixture.cases("logFromStatusLines") {
            let lines = try decode([String].self, c.input["lines"])
            let groups = LiveRun.logFromStatusLines(lines)
            guard case .array(let expectedGroups) = c.expected else { return XCTFail(label(c)) }
            XCTAssertEqual(groups.count, expectedGroups.count, label(c))
            for (group, expected) in zip(groups, expectedGroups) {
                XCTAssertEqual(expected["kind"]?.stringValue, "group")
                XCTAssertEqual(expected["status"]?.stringValue, "in-progress")
                guard case .array(let steps)? = expected["steps"] else { return XCTFail(label(c)) }
                XCTAssertEqual(group.steps.map(\.label), steps.compactMap { $0["label"]?.stringValue }, label(c))
                XCTAssertEqual(group.steps.map { $0.completed ? "completed" : "in-progress" },
                               steps.compactMap { $0["status"]?.stringValue }, label(c))
            }
        }
    }

    func testLiveContentNeverShowsThePreviousTurn() throws {
        for c in fixture.cases("liveContent") {
            let status = try decode(StreamStatus.self, c.input["status"])
            var known: Set<String>?
            if case .array(let items)? = c.input["known"] { known = Set(items.compactMap(\.stringValue)) }
            XCTAssertEqual(LiveRun.liveContent(status, knownAnswers: known), c.expected.stringValue, label(c))
        }
    }

    func testRunOutcome() throws {
        for c in fixture.cases("runOutcome") {
            let saved = try decode([ChatMessage].self, c.input["saved"])
            let expected = c.expected
            let want: LiveRun.Outcome
            if expected["ok"] == .bool(false) {
                want = .noAnswer
            } else if expected["stopped"] == .bool(true) {
                want = .stopped
            } else if expected["incomplete"] == .bool(true) {
                want = .incomplete
            } else {
                want = .finished
            }
            XCTAssertEqual(LiveRun.runOutcome(saved), want, label(c))
        }
    }

    func testFailureText() {
        for c in fixture.cases("failureText") {
            XCTAssertEqual(LiveRun.failureText(c.input["reason"]?.stringValue), c.expected.stringValue, "\(c.input)")
        }
    }

    // MARK: - Decoding /stream-status

    func testDecodesTheRunStatusShape() throws {
        let json = """
        {"active":true,"isTyping":true,"step":"starting","contentLength":0,"content":"","done":false,
         "incomplete":false,"incompleteReason":null,"startedAt":1700000000000,"updatedAt":null,
         "fromLiveRun":false,"running":true,"phase":"research","writing":false,"elapsedMs":4200,
         "status":"Reading page 2 of a.pdf","statusAt":1700000003000,
         "statusLines":["Planning","Reading page 2 of a.pdf"],"aliveAt":1700000004000}
        """
        let status = try JSONDecoder().decode(StreamStatus.self, from: Data(json.utf8))

        XCTAssertEqual(status.running, true)
        XCTAssertEqual(status.phase, "research")
        XCTAssertEqual(status.writing, false)
        XCTAssertEqual(status.elapsedMs, 4200)
        XCTAssertEqual(status.status, "Reading page 2 of a.pdf")
        XCTAssertEqual(status.statusAt, 1_700_000_003_000)
        XCTAssertEqual(status.statusLines, ["Planning", "Reading page 2 of a.pdf"])
        XCTAssertEqual(status.aliveAt, 1_700_000_004_000)
        XCTAssertEqual(status.fromLiveRun, false)
    }

    func testDecodesTheOlderShapeWithoutRunFields() throws {
        let json = #"{"active":false,"isTyping":false,"step":"unknown","contentLength":5,"content":"hello","done":true,"incomplete":false,"startedAt":1700000000000,"updatedAt":1700000001000}"#
        let status = try JSONDecoder().decode(StreamStatus.self, from: Data(json.utf8))

        XCTAssertNil(status.running)
        XCTAssertNil(status.phase)
        XCTAssertNil(status.statusLines)
        XCTAssertNil(status.fromLiveRun)
        XCTAssertEqual(status.content, "hello")
    }

    func testDecodesTheNoCheckpointReply() throws {
        let json = #"{"active":false,"done":true,"incomplete":false,"isTyping":false,"step":"unknown","contentLength":0,"content":"","fromLiveRun":false,"running":false,"startedAt":null,"error":"No messages"}"#
        let status = try JSONDecoder().decode(StreamStatus.self, from: Data(json.utf8))

        XCTAssertEqual(status.error, "No messages")
        XCTAssertNil(status.startedAt)
        XCTAssertEqual(status.running, false)
    }
}
