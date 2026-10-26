import XCTest
@testable import EmperorCore

final class TeamsViewModelTests: XCTestCase {

    private static func standard() -> FakeTeams {
        FakeTeams([
            Team(id: "team_1", name: "My Firm", ownerUserID: "1", role: "owner", memberCount: 1),
            Team(id: "team_2", name: "Chambers", ownerUserID: "9", role: "member", memberCount: 4),
        ])
    }

    func testLoadListsTeams() async {
        await run { _, model in
            await model.load()
            XCTAssertEqual(model.teams.count, 2)
            XCTAssertEqual(model.state, .loaded)
        }
    }

    func testLoadFailureShowsFailedState() async {
        await run { fake, model in
            fake.listError = APIError.server(status: 500, message: "boom")
            await model.load()
            XCTAssertNotNil(model.state.failure)
        }
    }

    func testDefaultTargetSkipsMemberRoleTeams() async {
        await run { _, model in
            await model.load()
            XCTAssertEqual(model.invitable.map(\.id), ["team_1"])
            XCTAssertEqual(model.inviteTarget?.id, "team_1")
            XCTAssertFalse(model.showsPicker)
            XCTAssertEqual(model.inviteHeading, "Invite a member to “My Firm”")
        }
    }

    func testBlankNameIsANoOp() async {
        await run { fake, model in
            await model.load()
            model.newTeamName = "   "
            XCTAssertFalse(model.canCreate)
            await model.create()
            XCTAssertTrue(fake.created.isEmpty)
        }
    }

    func testCreateTrimsTargetsItAndReloads() async {
        await run { fake, model in
            await model.load()
            model.newTeamName = "  Litigation Team "
            await model.create()
            XCTAssertEqual(fake.created, ["Litigation Team"])
            XCTAssertEqual(model.newTeamName, "")
            XCTAssertEqual(model.pickedTeamID, "team_new_1")
            XCTAssertEqual(model.message, TeamsViewModel.Message(text: "Team created.", isError: false))
            XCTAssertEqual(model.teams.count, 3)
            XCTAssertEqual(model.inviteTarget?.name, "Litigation Team")
            XCTAssertTrue(model.showsPicker)
            XCTAssertEqual(model.inviteHeading, "Invite a member to")
        }
    }

    func testCreateFailureMessage() async {
        await run { fake, model in
            await model.load()
            fake.createError = APIError.server(status: 500, message: "Missing userId or name")
            model.newTeamName = "X"
            await model.create()
            XCTAssertEqual(model.message, TeamsViewModel.Message(text: "Could not create team.", isError: true))
            XCTAssertEqual(model.newTeamName, "X")
        }
    }

    func testInviteSuccessClearsEmailAndReloads() async {
        await run { fake, model in
            await model.load()
            model.inviteEmail = " colleague@example.com "
            await model.invite()
            XCTAssertEqual(fake.invited.first?.email, "colleague@example.com")
            XCTAssertEqual(fake.invited.first?.teamID, "team_1")
            XCTAssertEqual(model.inviteEmail, "")
            XCTAssertEqual(model.message, TeamsViewModel.Message(text: "Member added.", isError: false))
            XCTAssertEqual(model.teams.first?.memberCount, 2)
        }
    }

    func testServerSentencesSurface() async {
        await run { fake, model in
            await model.load()
            fake.inviteError = APIError.server(status: 404, message: "No user with that email")
            model.inviteEmail = "nobody@example.com"
            await model.invite()
            XCTAssertEqual(model.message?.text, "No user with that email")
            XCTAssertEqual(model.message?.isError, true)
            XCTAssertEqual(model.inviteEmail, "nobody@example.com")

            fake.inviteError = APIError.server(status: 403, message: "Only team owners/admins can invite")
            await model.invite()
            XCTAssertEqual(model.message?.text, "Only team owners/admins can invite")
        }
    }

    func testDoubleTapSendsOnce() async {
        await run { fake, model in
            await model.load()
            fake.inviteDelay = .milliseconds(150)
            model.inviteEmail = "a@example.com"
            async let first: Void = model.invite()
            async let second: Void = model.invite()
            _ = await (first, second)
            XCTAssertEqual(fake.invited.count, 1)
        }
    }

    func testNoInvitableTeamsDisablesInvite() async {
        let fake = FakeTeams([Team(id: "t", name: "Theirs", role: "member", memberCount: 3)])
        await runWith(fake) { _, model in
            await model.load()
            model.inviteEmail = "a@example.com"
            XCTAssertNil(model.inviteTarget)
            XCTAssertFalse(model.canInvite)
        }
    }

    private func run(_ body: @MainActor (FakeTeams, TeamsViewModel) async -> Void) async {
        await runWith(Self.standard(), body)
    }

    private func runWith(
        _ fake: FakeTeams, _ body: @MainActor (FakeTeams, TeamsViewModel) async -> Void
    ) async {
        await teamsModel(fake, body)
    }
}

@MainActor
private func teamsModel(
    _ fake: FakeTeams, _ body: @MainActor (FakeTeams, TeamsViewModel) async -> Void
) async {
    await body(fake, TeamsViewModel(service: fake))
}
