import XCTest
@testable import EmperorCore

/// `CaseTracking` — the web's `trackCase`: a case the user already tracks is used as it is; a new
/// one is saved; a "409 already there" is looked up again; a numberless collision is an error.
final class CaseTrackingTests: XCTestCase {

    private let pick = CourtSearchResult(
        courtType: "hc", courtCode: "PHHC", courtName: "Punjab and Haryana High Court", caseType: "CWP",
        caseNumber: "4412", caseYear: "2025", cnr: "PHHC010044122025", title: nil)

    private func tracked(_ id: String = "case-x", cnr: String? = "PHHC010044122025", team: String? = nil) -> LegalCase {
        var c = LegalCase(id: id)
        c.cnr = cnr
        c.teamID = team
        c.caseNumber = "4412"
        c.caseYear = "2025"
        c.caseType = "CWP"
        c.courtCode = "PHHC"
        return c
    }

    func testACaseAlreadyTrackedIsUsedWithoutSavingIt() async {
        let cases = FakeCases()
        cases.cases = [tracked()]
        let search = FakeTrackingSearch()
        let result = await CaseTracking(cases: cases, search: search).track(pick, title: "Bhalla")
        XCTAssertEqual(try? result.get(), "case-x")
        XCTAssertTrue(search.saved.isEmpty, "a tracked case was saved a second time")
    }

    func testTheOwnTeamsCopyIsPreferred() async {
        let cases = FakeCases()
        cases.cases = [tracked("theirs", team: "t-other"), tracked("mine", team: "t-mine")]
        let tracking = CaseTracking(cases: cases, search: FakeTrackingSearch(), ownedTeamIDs: { ["t-mine"] })
        let result = await tracking.track(pick, title: nil)
        XCTAssertEqual(try? result.get(), "mine")
    }

    func testANewCaseIsSavedWithTheMattersNameForATitlelessCard() async {
        let search = FakeTrackingSearch()
        search.outcome = .saved(id: "case-new")
        let result = await CaseTracking(cases: FakeCases(), search: search).track(pick, title: "Bhalla v. State")
        XCTAssertEqual(try? result.get(), "case-new")
        XCTAssertEqual(search.saved.first?.title, "Bhalla v. State")
    }

    func testAlreadySavedLooksTheCaseUpAgain() async {
        let cases = FakeCases()
        let search = FakeTrackingSearch()
        search.outcome = .alreadySaved(message: "This case is already on the team dashboard")
        search.onSave = { cases.cases = [self.tracked("case-found")] }
        let result = await CaseTracking(cases: cases, search: search).track(pick, title: nil)
        XCTAssertEqual(try? result.get(), "case-found")
    }

    func testANumberlessCollisionIsAnErrorNotASuccess() async {
        let search = FakeTrackingSearch()
        search.outcome = .refusedAsIndistinguishable(message: "could not be added")
        let result = await CaseTracking(cases: FakeCases(), search: search).track(pick, title: nil)
        guard case .failure(let failure) = result else { return XCTFail("a refused case was reported tracked") }
        XCTAssertEqual(failure.message, "could not be added")
    }

    func testAFailedSaveThatLeftNothingSaysWhy() async {
        let search = FakeTrackingSearch()
        search.failure = APIError.server(status: 500, message: "The court site did not answer")
        let result = await CaseTracking(cases: FakeCases(), search: search).track(pick, title: nil)
        guard case .failure(let failure) = result else { return XCTFail("expected a failure") }
        XCTAssertEqual(failure.message, "The court site did not answer")
    }
}
