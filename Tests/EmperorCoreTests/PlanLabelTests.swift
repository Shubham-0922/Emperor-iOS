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
}
