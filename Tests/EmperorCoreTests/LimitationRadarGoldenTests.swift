import XCTest
@testable import EmperorCore

/// The radar held to the platform's own table, audits and refusals
/// (`scripts/generate-limitation-radar-fixtures.mjs`). Regenerate on a platform change; never edit.
final class LimitationRadarGoldenTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Profile: Decodable {
            var key: String, label: String, article: String, years: Int, runsFrom: String
        }
        struct Case: Decodable { var id: String; var output: LimitationAudit }
        struct Route: Decodable {
            var id: String
            var status: Int
            var response: LimitationRadarEnvelope
        }
        struct DateCase: Decodable { var iso: String; var long: String }
        struct DayCount: Decodable { var n: Int; var text: String }
        var profiles: [Profile]
        var defaultProfile: String
        var audits: [Case]
        var routes: [Route]
        var dates: [DateCase]
        var dayCounts: [DayCount]
    }

    private func load() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: try parityFixture("radar", "limitation-radar"))
    }

    func testProfilesMatchThePlatformTableInOrder() throws {
        let f = try load()
        XCTAssertEqual(LimitationProfile.defaultKey, f.defaultProfile)
        XCTAssertEqual(LimitationProfile.all.count, f.profiles.count)
        for (ours, theirs) in zip(LimitationProfile.all, f.profiles) {
            XCTAssertEqual(ours.key, theirs.key)
            XCTAssertEqual(ours.label, theirs.label)
            XCTAssertEqual(ours.article, theirs.article)
            XCTAssertEqual(ours.years, theirs.years)
            XCTAssertEqual(ours.runsFrom, theirs.runsFrom)
        }
    }

    func testEveryAuditDecodesWithItsOutcome() throws {
        let f = try load()
        XCTAssertFalse(f.audits.isEmpty)
        for c in f.audits {
            let o = c.output
            XCTAssertFalse(o.status.isEmpty, c.id)
            XCTAssertFalse(o.curativeStrategies.isEmpty, c.id)
            let expected: LimitationOutcome =
                o.statusColor == "emerald" ? .safe : (o.statusColor == "amber" ? .mediation : .barred)
            XCTAssertEqual(o.outcome, expected, c.id)
            XCTAssertEqual(o.reliesOnMediationExclusion, o.outcome == .mediation, c.id)
        }
        let barred = try XCTUnwrap(f.audits.first { $0.id == "barred-17-days" }).output
        XCTAssertEqual(barred.daysOverdue, 17)
        XCTAssertEqual(barred.outcome, .barred)
    }

    func testEveryRefusalDecodesToAMessage() throws {
        let f = try load()
        XCTAssertFalse(f.routes.isEmpty)
        for r in f.routes {
            XCTAssertEqual(r.status, 400, r.id)
            XCTAssertEqual(r.response.success, false, r.id)
            XCTAssertFalse(try XCTUnwrap(r.response.error?.message, r.id).isEmpty, r.id)
            XCTAssertNotNil(r.response.error?.code, r.id)
        }
    }

    func testServiceReadsEachRefusalMessage() throws {
        let raw = try parityFixture("radar", "limitation-radar")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let routes = try XCTUnwrap(json["routes"] as? [[String: Any]])
        for r in routes {
            let status = try XCTUnwrap(r["status"] as? Int)
            let body = try JSONSerialization.data(withJSONObject: try XCTUnwrap(r["response"]))
            let envelope = try JSONDecoder().decode(LimitationRadarEnvelope.self, from: body)
            XCTAssertThrowsError(try LimitationRadarService.read(data: body, status: status)) {
                XCTAssertEqual(
                    $0 as? APIError,
                    .server(status: 400, message: envelope.error?.message ?? ""))
            }
        }
    }

    func testLongDateAndDaysMatchThePage() throws {
        let f = try load()
        for d in f.dates {
            XCTAssertEqual(LimitationRadarViewModel.longDate(d.iso), d.long, d.iso)
        }
        for c in f.dayCounts {
            XCTAssertEqual(LimitationRadarViewModel.days(c.n), c.text)
        }
    }

    func testEveryAuditBannerReadsLikeThePage() async throws {
        let f = try load()
        for c in f.audits {
            let o = c.output
            let fake = FakeRadar()
            fake.answer = o
            let text = await radarHeadline(after: fake)
            let expected: String
            if o.reliesOnMediationExclusion {
                expected = "\(LimitationRadarViewModel.days(o.daysOverdue)) late without the exclusion · \(LimitationRadarViewModel.days(-o.adjustedDaysOverdue)) remaining with it"
            } else if o.daysOverdue > 0 {
                expected = "\(LimitationRadarViewModel.days(o.daysOverdue)) past the last day to file"
            } else {
                expected = "\(LimitationRadarViewModel.days(-o.daysOverdue)) remaining"
            }
            XCTAssertEqual(text, expected, c.id)
        }
    }
}

@MainActor
private func radarRun(_ fake: FakeRadar) async -> LimitationRadarViewModel {
    let vm = LimitationRadarViewModel(service: fake)
    vm.causeOfAction = WireDate.parseDay("2023-01-15")
    vm.intendedFiling = WireDate.parseDay("2026-02-01")
    await vm.run()
    return vm
}

private func radarHeadline(after fake: FakeRadar) async -> String? {
    await MainActor.run { }
    return await Task { @MainActor in await radarRun(fake).headline }.value
}
