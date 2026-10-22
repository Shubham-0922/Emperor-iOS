import XCTest
@testable import EmperorCore

/// The links About & Compliance and More promise: the company's own addresses, all https, the
/// company's name, and the two legal pages honestly absent until the platform has them.
final class EmperorLinksTests: XCTestCase {
    func testTheSocialHandlesAreTheCompanysOwnAndAllSecure() {
        XCTAssertEqual(
            EmperorLinks.socials.map(\.name),
            ["YouTube", "Facebook", "LinkedIn", "X", "Instagram"])
        for social in EmperorLinks.socials {
            XCTAssertEqual(social.url.scheme, "https", social.name)
            XCTAssertFalse(social.monogram.isEmpty, "\(social.name) has no tile letters")
            XCTAssertFalse(social.handle.isEmpty, "\(social.name) has no handle")
        }
    }

    func testTheWebsiteIsTheAppsOwn() {
        XCTAssertEqual(EmperorLinks.website.scheme, "https")
        XCTAssertEqual(EmperorLinks.website.host, "app.emperorailabs.com")
    }

    /// `nil` while the platform has no such page — the rows stand in rather than lie.
    func testTheLegalPagesAreNotLinkedUntilTheyExist() {
        XCTAssertNil(EmperorLinks.privacyPolicy)
        XCTAssertNil(EmperorLinks.terms)
    }

    func testTheCompanyNameIsTheOneTheAppIsBuiltFor() {
        XCTAssertEqual(EmperorLinks.companyName, "Emperor AI Labs")
    }
}
