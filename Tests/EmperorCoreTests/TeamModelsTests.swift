import XCTest
@testable import EmperorCore

/// Team rows as `GET /teams` writes them (`sync-server.js:13497-13516`).
final class TeamModelsTests: XCTestCase {

    private func decode(_ json: String) throws -> TeamsResponse {
        try JSONDecoder().decode(TeamsResponse.self, from: Data(json.utf8))
    }

    func testDecodesTheRealBody() throws {
        let r = try decode("""
            {"success":true,"teams":[
             {"id":"team_1790000000000_ab12cd","name":"My Firm","owner_user_id":"42","role":"owner","member_count":1},
             {"id":"team_2","name":"Chambers","owner_user_id":"9","role":"member","member_count":4}]}
            """)
        XCTAssertEqual(r.teams.count, 2)
        XCTAssertEqual(r.teams[0].ownerUserID, "42")
        XCTAssertEqual(r.teams[1].memberCount, 4)
        XCTAssertEqual(r.teams[1].roleLabel, "Member")
    }

    func testNumericOwnerAndStringCount() throws {
        let r = try decode(#"{"success":true,"teams":[{"id":"t","name":"A","owner_user_id":7,"role":"admin","member_count":"3"},{"id":"u","name":"B","member_count":2.0}]}"#)
        XCTAssertEqual(r.teams[0].ownerUserID, "7")
        XCTAssertEqual(r.teams[0].memberCount, 3)
        XCTAssertEqual(r.teams[1].memberCount, 2)
    }

    func testMissingCountIsOne() throws {
        let r = try decode(#"{"success":true,"teams":[{"id":"t","name":"A"}]}"#)
        XCTAssertEqual(r.teams[0].memberCount, 1)
    }

    func testARowWithoutNameOrIdIsSkipped() throws {
        let r = try decode(#"{"success":true,"teams":[{"id":"t"},{"name":"X"},{"id":"ok","name":"Fine"}]}"#)
        XCTAssertEqual(r.teams.map(\.id), ["ok"])
    }

    func testCanInviteMatrix() {
        XCTAssertTrue(Team(id: "a", name: "A", role: "owner").canInvite)
        XCTAssertTrue(Team(id: "a", name: "A", role: "admin").canInvite)
        XCTAssertTrue(Team(id: "a", name: "A", role: nil).canInvite)
        XCTAssertFalse(Team(id: "a", name: "A", role: "member").canInvite)
    }

    func testPickerLabelAndRowDetail() {
        XCTAssertEqual(Team(id: "a", name: "Solo", memberCount: 1).pickerLabel, "Solo")
        XCTAssertEqual(Team(id: "a", name: "Chambers", memberCount: 4).pickerLabel, "Chambers · 4 members")
        XCTAssertEqual(Team(id: "a", name: "A", role: "owner", memberCount: 1).rowDetail, "Owner · 1 member")
        XCTAssertEqual(Team(id: "a", name: "A", role: "owner", memberCount: 3).rowDetail, "Owner · 3 members")
    }

    func testSharedWith() {
        let teams = [Team(id: "solo", name: "My Firm", memberCount: 1),
                     Team(id: "duo", name: "Chambers", memberCount: 2),
                     Team(id: "blank", name: "", memberCount: 2)]
        XCTAssertNil(TeamDirectory.sharedWith(teamID: "solo", teams: teams, fallbackName: "My Firm"))
        XCTAssertEqual(TeamDirectory.sharedWith(teamID: "duo", teams: teams, fallbackName: nil), "Chambers")
        XCTAssertNil(TeamDirectory.sharedWith(teamID: "gone", teams: teams, fallbackName: "X"))
        XCTAssertNil(TeamDirectory.sharedWith(teamID: nil, teams: teams, fallbackName: "X"))
        XCTAssertEqual(TeamDirectory.sharedWith(teamID: "blank", teams: teams, fallbackName: "Fallback"), "Fallback")
    }
}
