import XCTest
@testable import EmperorCore

final class PlanLabelTests: XCTestCase {

    func testInternalTiersAreNeverShown() {
        for tier in ["None", "Lite", "Premium", "Ultra", " Ultra ", ""] {
            XCTAssertNil(PlanLabel.customerFacing(tier), tier)
        }
        XCTAssertNil(PlanLabel.customerFacing(nil))
        XCTAssertEqual(PlanLabel.customerFacing("Partner"), "Partner")
    }

    func testThePillFallsBackToTheTierThenToPlan() {
        XCTAssertEqual(PlanLabel.pill(session: "Senior Associate", tierLabel: "Partner"), "Senior Associate")
        XCTAssertEqual(PlanLabel.pill(session: "Ultra", tierLabel: "Partner"), "Partner")
        XCTAssertEqual(PlanLabel.pill(session: nil, tierLabel: nil), "Plan")
        XCTAssertEqual(PlanLabel.pill(session: "Lite", entitlements: nil), "Plan", "never PRO or Lite")
    }

    func testTheAccountCardSaysWhosePlanAndNeverATier() {
        XCTAssertEqual(PlanLabel.accountPill(session: "Junior Associate"), "Junior Associate plan")
        XCTAssertEqual(PlanLabel.accountPill(session: "Ultra"), "Plan", "never an internal tier")
        XCTAssertEqual(PlanLabel.accountPill(session: nil), "Plan", "never PRO")
    }

    /// The plan sheet's name: the account's own label, else the allowances' tier name.
    func testThePlanSheetNameFallsBackToTheAllowancesTier() async {
        let usage = AccountUsage(
            planLabel: "Ultra", isMetered: true, hasExpired: false, renewsOn: nil, meters: [],
            planTierLabel: "Junior Associate")
        let names = await planSheetNames(usage, labels: ["Ultra", "Partner"])
        XCTAssertEqual(names, ["Junior Associate", "Partner"])
    }
}

private struct FixedUsage: UsageProviding {
    let value: AccountUsage
    func usage() async throws -> AccountUsage { value }
}

@MainActor
private func planSheetNames(_ usage: AccountUsage, labels: [String]) async -> [String] {
    let model = AccountUsageViewModel(service: FixedUsage(value: usage))
    await model.load()
    return labels.map { model.planName(sessionLabel: $0) }
}
