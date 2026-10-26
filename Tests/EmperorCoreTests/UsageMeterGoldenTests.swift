import XCTest
@testable import EmperorCore

/// The usage meters held to what the web's own helpers produce
/// (`scripts/generate-usage-meter-fixtures.mjs`). On a mismatch regenerate; do not edit the fixture.
final class UsageMeterGoldenTests: XCTestCase {

    private struct Golden: Decodable {
        struct Bytes: Decodable { var bytes: Double; var text: String }
        struct Tone: Decodable { var used: Double; var limit: Double?; var tone: String }
        struct Row: Decodable {
            var key: String, title: String, usedText: String, limitText: String
            var unlimited: Bool, tone: String
        }
        struct Body: Decodable {
            var name: String
            var body: JSONValue
            var rows: [Row]
        }
        struct Top: Decodable { var label: String?; var shown: String? }
        var fmtBytes: [Bytes]
        var usageTone: [Tone]
        var bodies: [Body]
        var topbar: [Top]
    }

    private func golden() throws -> Golden {
        try JSONDecoder().decode(Golden.self, from: parityFixture("08-O", "usage-meter"))
    }

    private let kinds: [String: AccountUsage.Meter.Kind] = [
        "chat": .questions, "deep": .deepThinking, "scans": .scannedPages,
        "docs": .documents, "matters": .matters, "storage": .storage,
    ]

    func testBytesReadAsTheWebReadsThem() throws {
        for c in try golden().fmtBytes where c.bytes >= 0 {
            XCTAssertEqual(AccountUsage.bytes(c.bytes), c.text, "\(c.bytes)")
        }
    }

    func testToneMatchesTheWeb() throws {
        for c in try golden().usageTone {
            let limit = c.limit.flatMap { $0 < 0 ? nil : $0 }
            let meter = AccountUsage.Meter(kind: .questions, used: c.used, limit: limit)
            XCTAssertEqual(meter.tone.rawValue, c.tone, "\(c.used) of \(String(describing: c.limit))")
        }
    }

    func testEveryBodyDrawsTheWebsRows() throws {
        for entry in try golden().bodies {
            let data = try JSONEncoder().encode(entry.body)
            let usage = try JSONDecoder().decode(EntitlementsResponse.self, from: data).usageModel
            XCTAssertEqual(usage.meters.count, entry.rows.count, entry.name)
            for (meter, row) in zip(usage.meters, entry.rows) {
                XCTAssertEqual(meter.kind, kinds[row.key], "\(entry.name) \(row.key)")
                XCTAssertEqual(meter.title, row.title, entry.name)
                XCTAssertEqual(meter.usedText, row.usedText, "\(entry.name) \(row.key)")
                XCTAssertEqual(meter.isUnlimited, row.unlimited, "\(entry.name) \(row.key)")
                if !row.unlimited {
                    XCTAssertEqual(meter.limitText, row.limitText, "\(entry.name) \(row.key)")
                    XCTAssertEqual(meter.summary, "\(row.usedText) of \(row.limitText)")
                } else {
                    XCTAssertEqual(meter.summary, "\(row.usedText) · no limit")
                }
                XCTAssertEqual(meter.tone.rawValue, row.tone, "\(entry.name) \(row.key)")
            }
        }
    }

    func testTheTopBarsPlanNameFilter() throws {
        for c in try golden().topbar {
            XCTAssertEqual(PlanLabel.customerFacing(c.label), c.shown, "\(String(describing: c.label))")
        }
    }
}
