import Foundation
#if canImport(Darwin)
import Observation
#endif

/// The Team screen: your teams, a new one, and a colleague added to one.
///
/// Words and rules follow the web's `TeamModal` (`src/components/cases/TeamModal.jsx`). There is
/// no active-team notion here: the invite target is the team picked, else the first the account
/// may invite to. See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class TeamsViewModel {

    struct Message: Equatable, Sendable {
        let text: String
        let isError: Bool
    }

    static let createFailedMessage = "Could not create team."
    static let inviteFailedMessage = "Could not add member."
    static let createdMessage = "Team created."
    static let addedMessage = "Member added."
    static let inviteFootnote =
        "The person must already have an Emperor AI account. They will see this team’s tracked cases under Matters."

    private let service: TeamProviding

    private(set) var teams: [Team] = []
    private(set) var state: LoadState = .idle
    var newTeamName = ""
    var inviteEmail = ""
    var pickedTeamID: String?
    private(set) var isCreating = false
    private(set) var isInviting = false
    private(set) var message: Message?

    init(service: TeamProviding) {
        self.service = service
    }

    // MARK: - Derived

    /// The teams this account may add people to.
    var invitable: [Team] { teams.filter(\.canInvite) }

    var inviteTarget: Team? {
        if let pickedTeamID, let picked = invitable.first(where: { $0.id == pickedTeamID }) {
            return picked
        }
        return invitable.first
    }

    var showsPicker: Bool { invitable.count > 1 }

    /// "Invite a member to" above a picker, `Invite a member to “Name”` when there is one team.
    var inviteHeading: String {
        if showsPicker { return "Invite a member to" }
        if let target = inviteTarget { return "Invite a member to “\(target.name)”" }
        return "Invite a member"
    }

    private var trimmedName: String { newTeamName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedEmail: String { inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canCreate: Bool { !trimmedName.isEmpty && !isCreating && !isInviting }
    var canInvite: Bool { !trimmedEmail.isEmpty && inviteTarget != nil && !isInviting && !isCreating }

    // MARK: - Intents

    func load() async {
        if teams.isEmpty { state = .loading }
        do {
            teams = try await service.teams()
            state = .loaded
        } catch {
            // A list already on screen stays; the failure state is for a screen with nothing.
            if teams.isEmpty { state = .failed(LoadFailure(error)) }
        }
    }

    func create() async {
        guard canCreate else { return }
        let name = trimmedName
        isCreating = true
        message = nil
        defer { isCreating = false }
        do {
            let id = try await service.createTeam(name: name)
            newTeamName = ""
            pickedTeamID = id
            message = Message(text: Self.createdMessage, isError: false)
            await load()
        } catch {
            message = Message(text: Self.createFailedMessage, isError: true)
        }
    }

    func invite() async {
        guard canInvite, let target = inviteTarget else { return }
        let email = trimmedEmail
        isInviting = true
        message = nil
        defer { isInviting = false }
        do {
            try await service.invite(teamID: target.id, email: email)
            inviteEmail = ""
            message = Message(text: Self.addedMessage, isError: false)
            await load()
        } catch {
            let text = DisplayText.message(for: error)
            message = Message(text: text.isEmpty ? Self.inviteFailedMessage : text, isError: true)
        }
    }

    func clearMessage() { message = nil }
}
