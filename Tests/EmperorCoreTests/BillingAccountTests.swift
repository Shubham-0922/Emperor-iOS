import XCTest
@testable import EmperorCore

struct ModelSnapshot {
    var planStatus: BillingPlanStatus?
    var standing: PlanStanding?
    var meterCount: Int
    var loaded: Bool
    var names: [String: String]
    var includedTitles: [String]
    var includedValues: [String]
    var featureCount: Int
}

@MainActor
private func loaded(
    usage: AccountUsage?, billing: any BillingAccountProviding, now: Date,
    sessionLabels: [String] = []
) async -> ModelSnapshot {
    let model = AccountUsageViewModel(
        service: FakeUsageProvider(usage: usage, error: nil), billing: billing, now: { now })
    await model.load()
    var names: [String: String] = [:]
    for label in sessionLabels { names[label] = model.planName(sessionLabel: label) }
    return ModelSnapshot(
        planStatus: model.planStatus, standing: model.standing, meterCount: model.visibleMeters.count,
        loaded: model.state == .loaded, names: names,
        includedTitles: model.includedRows.map(\.title), includedValues: model.includedRows.map(\.value),
        featureCount: model.productFeatures.count)
}

private let now = Date(timeIntervalSince1970: 1_790_000_000)
private let dayLength = 86_400.0

final class BillingAccountTests: XCTestCase {

    private func standing(_ source: String?, expires: Date?, expired: Bool = false) -> PlanStanding {
        PlanStanding.of(BillingPlanStatus(planSource: source, expiresAt: expires, expired: expired), now: now)
    }

    func testStandingFollowsTheBillingPage() {
        XCTAssertEqual(standing(nil, expires: nil).text, "No plan")
        XCTAssertEqual(PlanStanding.of(nil, now: now).text, "No plan")
        XCTAssertEqual(standing("purchase", expires: nil, expired: true).text, "Expired")
        XCTAssertEqual(standing("purchase", expires: nil).text, "Active")
        XCTAssertEqual(standing("purchase", expires: now.addingTimeInterval(-60)).text, "Expires today")
        XCTAssertEqual(standing("purchase", expires: now.addingTimeInterval(3600)).text, "Expires in 1 day")
        XCTAssertEqual(standing("purchase", expires: now.addingTimeInterval(5 * dayLength)).text, "Expires in 5 days")
        XCTAssertEqual(standing("purchase", expires: now.addingTimeInterval(13 * dayLength)).text, "Expires in 13 days")
        XCTAssertEqual(standing("purchase", expires: now.addingTimeInterval(13 * dayLength + 60)).text, "Active", "13 days and a minute rounds up to 14")
        XCTAssertEqual(standing("purchase", expires: now.addingTimeInterval(14 * dayLength)).text, "Active")
        XCTAssertEqual(standing("purchase", expires: now.addingTimeInterval(3 * dayLength)).tone, .warning)
    }

    func testTheSourceLine() {
        let end = WireDate.parse("2026-11-12T10:00:00.000Z")
        let bought = BillingPlanStatus(planSource: "purchase", expiresAt: end)
        XCTAssertEqual(PlanStanding.sourceLine(bought, now: now), "purchased · Active until 12 November 2026")
        let old = BillingPlanStatus(planSource: "purchase", expiresAt: end, expired: true)
        XCTAssertEqual(PlanStanding.sourceLine(old, now: now), "purchased · Expired on 12 November 2026")
        let grandfathered = BillingPlanStatus(planSource: "grandfathered", expiresAt: end)
        XCTAssertEqual(PlanStanding.sourceLine(grandfathered, now: now), "included · No expiry")
        XCTAssertEqual(PlanStanding.sourceLine(BillingPlanStatus(planSource: "coupon"), now: now), "free trial · No expiry")
        XCTAssertNil(PlanStanding.sourceLine(BillingPlanStatus(), now: now))
    }

    func testTheBillingAnswerDecodes() throws {
        let json = #"{"planSource":"purchase","expiresAt":"2026-11-12T10:00:00.000Z","expired":false,"displayLabel":"Junior Associate","feeTier":"essential"}"#
        let status = try JSONDecoder().decode(BillingPlanStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.displayLabel, "Junior Associate")
        XCTAssertNotNil(status.expiresAt)
    }

    func testAFailedBillingReadLeavesTheUsage() async {
        let usage = AccountUsage(
            planLabel: nil, isMetered: true, hasExpired: false, renewsOn: nil,
            meters: [.init(kind: .questions, used: 3, limit: 30)])
        let model = await loaded(
            usage: usage, billing: FakeBillingAccount(error: APIError.transport("down")), now: now)
        XCTAssertNil(model.planStatus)
        XCTAssertNil(model.standing)
        XCTAssertEqual(model.meterCount, 1)
        XCTAssertTrue(model.loaded)
    }

    func testThePlanNameNeverShowsAnInternalTier() async {
        let usage = AccountUsage(
            planLabel: "Ultra", isMetered: true, hasExpired: false, renewsOn: nil, meters: [],
            planTierLabel: "Junior Associate")
        let model = await loaded(
            usage: usage, billing: FakeBillingAccount(status: nil), now: now, sessionLabels: ["Ultra"])
        XCTAssertEqual(model.names["Ultra"], "Junior Associate")
        let named = await loaded(
            usage: usage, billing: FakeBillingAccount(status: BillingPlanStatus(
                planSource: "purchase", displayLabel: "Partner")), now: now, sessionLabels: ["Ultra"])
        XCTAssertEqual(named.names["Ultra"], "Partner")
    }

    func testWhatThePlanIncludes() async {
        let usage = AccountUsage(
            planLabel: nil, isMetered: true, hasExpired: false, renewsOn: nil, meters: [],
            supportLabel: "Email support", storageBytes: 50 * 1_073_741_824,
            filingReady: true, cloudSync: false,
            productFeatures: [
                .init(key: "a", label: "A", status: .included),
                .init(key: "b", label: "B", status: .inDevelopment)])
        let model = await loaded(usage: usage, billing: FakeBillingAccount(status: nil), now: now)
        XCTAssertEqual(model.includedTitles, ["Support", "Storage", "Filing Ready", "Cloud Sync"])
        XCTAssertEqual(model.includedValues,
                       ["Email support", "50 GB", "Included", "Not on your plan"])
        XCTAssertEqual(model.featureCount, 2)
    }

    func testTheEntitlementsExtrasDecode() throws {
        let json = #"""
        {"success":true,"signedIn":true,"metered":true,"limits":{"label":"Junior Associate","support":"email"},
         "usage":{"chatQueries":1},"features":{"filingReady":true,"cloudSync":true},"storageBytes":53687091200,
         "support":"Email support","overageRates":{"scannedPagePaise":50},
         "coreFeatures":[{"key":"chat","label":"Chat"},{"key":"x","label":"X","comingSoon":true}],
         "roadmap":[{"key":"r1","label":"R1","status":"available","detail":"d"},{"key":"r2","label":"R2","status":"in-development"}]}
        """#
        let usage = try JSONDecoder().decode(EntitlementsResponse.self, from: Data(json.utf8)).usageModel
        XCTAssertEqual(usage.planTierLabel, "Junior Associate")
        XCTAssertEqual(usage.supportLabel, "Email support")
        XCTAssertEqual(usage.productFeatures.map(\.status), [.included, .comingSoon, .included, .inDevelopment])
    }
}
