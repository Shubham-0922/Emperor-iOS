import XCTest
@testable import EmperorCore

/// Fetch Orders held to the platform's own record builder and `lookupModel.js`
/// (`scripts/generate-lookup-fixtures.mjs`). Regenerate on a platform change; never edit.
final class LookupGoldenTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Sample: Decodable {
            var id: String
            var card: CourtSearchResult
            var record: LookupRecord
        }
        struct Case: Decodable {
            var fn: String
            var input: JSONValue
            var expected: JSONValue
        }
        var today: String
        var records: [Sample]
        var cases: [Case]
    }

    private func load() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: try parityFixture("06-C", "lookup"))
    }

    private func list(_ value: JSONValue?) -> [JSONValue] {
        if case .array(let items)? = value { return items }
        return []
    }

    private func record(_ f: Fixture, _ input: JSONValue) throws -> LookupRecord {
        let id = try XCTUnwrap(input["recordId"]?.stringValue)
        return try XCTUnwrap(f.records.first { $0.id == id }).record
    }

    func testEveryRecordDecodes() throws {
        let f = try load()
        XCTAssertEqual(f.records.count, 3)
        let full = try XCTUnwrap(f.records.first { $0.id == "full" }).record
        XCTAssertEqual(full.case.nextHearing, "2099-01-15")
        XCTAssertEqual(full.case.filingDate, "2025-03-01")
        XCTAssertEqual(full.parties.respondents, ["UNION OF INDIA", "COMMISSIONER OF CUSTOMS"])
        XCTAssertEqual(full.hearings.count, 3, "the undated hearing is dropped by the platform")
        XCTAssertEqual(full.orders.count, 4)
        XCTAssertEqual(full.applications.first?.status, "Disposed")
        XCTAssertEqual(full.courtFees.first?.amount, 1250)
        XCTAssertNil(full.courtFees.last?.amount)
        XCTAssertEqual(full.connected.first?.orderDate, "2020-12-12")
        // The court's PDF opens; the consumer forum's marker and a missing copy do not.
        XCTAssertNotNil(full.orders[0].webURL)
        XCTAssertNil(full.orders[1].webURL)
        XCTAssertNil(full.orders[2].webURL)

        let sparse = try XCTUnwrap(f.records.first { $0.id == "sparse" }).record
        XCTAssertTrue(sparse.parties.petitioners.isEmpty)
        XCTAssertEqual(sparse.case.diaryNumber, "41207/2025")
    }

    func testTheModelMatchesThePlatform() throws {
        let f = try load()
        var checked = 0
        for c in f.cases {
            let i = c.input
            switch c.fn {
            case "isDisposed":
                XCTAssertEqual(LookupModel.isDisposed(i["status"]?.stringValue), c.expected.boolValue, "\(i)")
            case "statusWord":
                // The page reads an empty word as none at all.
                XCTAssertEqual(LookupModel.statusWord(i["status"]?.stringValue) ?? "",
                               c.expected.stringValue ?? "", "\(i)")
            case "ago":
                XCTAssertEqual(LookupModel.ago(i["day"]?.stringValue, today: f.today), c.expected.stringValue, "\(i)")
            case "roomOf":
                XCTAssertEqual(LookupModel.roomOf(i["courtNo"]?.stringValue), c.expected.stringValue, "\(i)")
            case "timelineOf":
                let today = try XCTUnwrap(i["today"]?.stringValue)
                let rows = LookupModel.timelineOf(try record(f, i), today: today)
                let expected = list(c.expected)
                XCTAssertEqual(rows.count, expected.count, "\(i)")
                for (ours, theirs) in zip(rows, expected) {
                    XCTAssertEqual(ours.key, theirs["key"]?.stringValue, "\(i)")
                    XCTAssertEqual(ours.day, theirs["day"]?.stringValue, "\(i)")
                    XCTAssertEqual(ours.kind.rawValue, theirs["kind"]?.stringValue, "\(i)")
                    XCTAssertEqual(ours.title, theirs["title"]?.stringValue, "\(i)")
                    XCTAssertEqual(ours.sub, theirs["sub"]?.stringValue, "\(i)")
                }
            case "summaryText":
                let today = try XCTUnwrap(i["today"]?.stringValue)
                XCTAssertEqual(LookupModel.summaryText(try record(f, i), today: today), c.expected.stringValue, "\(i)")
            case "yearsOf":
                let years = LookupModel.yearsOf(try record(f, i).orders)
                XCTAssertEqual(years, (list(c.expected)).compactMap(\.stringValue), "\(i)")
            case "caseNumberOf":
                XCTAssertEqual(LookupModel.caseNumberOf(try record(f, i).case), c.expected.stringValue, "\(i)")
            case "titleOf":
                XCTAssertEqual(LookupModel.titleOf(try record(f, i).case), c.expected.stringValue, "\(i)")
            case "sidesOf":
                let sides = LookupModel.sidesOf(try record(f, i).parties)
                for (ours, key) in [(sides.first, "first"), (sides.second, "second")] {
                    let theirs = c.expected[key]
                    XCTAssertEqual(ours.names, list(theirs?["names"]).compactMap(\.stringValue), "\(i)")
                    XCTAssertEqual(ours.counsel, list(theirs?["counsel"]).compactMap(\.stringValue), "\(i)")
                    XCTAssertEqual(ours.lead, theirs?["lead"]?.stringValue, "\(i)")
                }
            default:
                XCTFail("unknown case \(c.fn)")
                continue
            }
            checked += 1
        }
        XCTAssertEqual(checked, f.cases.count)
        XCTAssertGreaterThan(checked, 50)
    }

    func testARecordedCardSendsThePlatformsCard() throws {
        let f = try load()
        let sparse = try XCTUnwrap(f.records.first { $0.id == "sparse" }).card
        // A court with no CNR is found again by its diary number, sent in `cnr`.
        XCTAssertEqual(sparse.lookupCard["cnr"], .string("41207/2025"))
        XCTAssertEqual(sparse.lookupCard["diaryNumber"], .string("41207/2025"))
        XCTAssertEqual(sparse.lookupCard["scrapeRef"], .null)
    }
}
