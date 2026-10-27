import Foundation
#if canImport(Darwin)
import Observation
#endif

/// Which side of a case the user acts for, as "Add to Matters" asks: the first-named side, the
/// other, or not yet.
enum SideChoice: String, CaseIterable, Sendable {
    case first, second, skip
}

/// A case found at its court, to keep as a matter.
struct AddToMattersRequest: Equatable, Sendable {
    var pick: CourtSearchResult
    /// The court record's cause title, for the tracked case when the search card has none.
    var caseTitle: String?
    var name: String
    var side: SideChoice
    /// The lead party of each side, as the court record names them.
    var firstLead: String?
    var secondLead: String?

    init(pick: CourtSearchResult, caseTitle: String? = nil, name: String? = nil, side: SideChoice = .skip,
         firstLead: String? = nil, secondLead: String? = nil) {
        self.pick = pick
        self.caseTitle = caseTitle
        self.name = name ?? MatterMeta.lookupTitle(
            title: caseTitle ?? pick.title, caseType: pick.caseType, caseNumber: pick.caseNumber, caseYear: pick.caseYear)
        self.side = side
        self.firstLead = firstLead
        self.secondLead = secondLead
    }

    /// The name sent: what was typed, else the case's own title.
    var matterName: String {
        let typed = JSCompat.trim(name)
        return typed.isEmpty
            ? MatterMeta.lookupTitle(title: caseTitle ?? pick.title, caseType: pick.caseType,
                                     caseNumber: pick.caseNumber, caseYear: pick.caseYear)
            : typed
    }

    /// The two sides' words for this kind of proceeding: petitioner and respondent, plaintiff and
    /// defendant, appellant and respondent.
    var sideKeys: (MatterVocabulary.OurSide, MatterVocabulary.OurSide) { MatterMeta.sideKeys(caseType: pick.caseType) }

    /// The patch a chosen side makes — `ourSide`, `client`, `oppositeParty` — or nil for "not yet".
    var sideFields: ProjectFields? {
        let (first, second) = sideKeys
        let mine: String?, theirs: String?, side: MatterVocabulary.OurSide
        switch self.side {
        case .skip: return nil
        case .first: (side, mine, theirs) = (first, firstLead, secondLead)
        case .second: (side, mine, theirs) = (second, secondLead, firstLead)
        }
        return ProjectFields([
            "ourSide": .text(side.rawValue),
            "client": .text(CourtNames.tidy(mine ?? "")),
            "oppositeParty": .text(CourtNames.tidy(theirs ?? "")),
        ])
    }
}

/// A matter made or found for a case.
struct MatterCreated: Equatable, Sendable {
    let projectID: String
    /// The user already had a matter for this case; that one is opened.
    let existed: Bool

    /// The toast after Add to Matters.
    var toast: String { existed ? "Opened your existing matter for this case" : "Added to Matters" }
}

/// Why a case could not be opened as its matter, in the web's words (`CaseToMatter.jsx`).
enum CaseToMatterFailure: Error, Equatable, Sendable {
    /// No longer tracked, or a bad id.
    case notFound
    /// Someone else's team tracks it; the server's sentence.
    case notShared(String)
    /// Anything else — worth another try.
    case other(String)

    var title: String {
        switch self {
        case .notFound: return "Case not found"
        case .notShared: return "This case is not shared with you"
        case .other: return "Could not open this case"
        }
    }

    var message: String {
        switch self {
        case .notFound:
            return "It is no longer tracked — it may have been removed — or the link is incomplete."
        case .notShared(let error):
            var said = JSCompat.trim(error)
            if said.isEmpty { said = "You are not a member of the team that tracks it" }
            if said.hasSuffix(".") { said.removeLast() }
            return "\(said). Ask whoever tracks it to add you to their team."
        case .other(let error):
            return error.isEmpty ? "The server did not answer." : error
        }
    }

    var canRetry: Bool { if case .other = self { return true } else { return false } }

    /// The server's 404 "Case not found" and 403 get words of their own; anything else is
    /// worth another try.
    static func from(_ error: Error) -> CaseToMatterFailure {
        if case .server(let status, let message)? = error as? APIError {
            if status == 404, message.range(of: "not found", options: .caseInsensitive) != nil { return .notFound }
            if status == 403 { return .notShared(message) }
        }
        return .other(DisplayText.message(for: error))
    }
}

/// Keeping a court case as a matter, from wherever a case is found — the court lookup's
/// "Add to Matters", Fetch Orders' "Open matter", a case's "Open as matter".
protocol MatterCreating: Sendable {
    /// Tracks the case (or finds it tracked), makes its matter (or finds it), and records the side.
    func addToMatters(_ r: AddToMattersRequest) async -> Result<MatterCreated, MatterRuleError>
    /// The user's matter for this case when there is one, archived ones included.
    func existingMatter(for pick: CourtSearchResult) async -> String?
    /// The matter for a tracked case — its own, made now if there is none.
    func openCaseAsMatter(caseID: String) async -> Result<MatterCreated, CaseToMatterFailure>
}

/// `MatterCreating` over the tracked cases, the matter writes and the matter list — the web's
/// `FetchOrders.jsx` `addToMatters`: track → `projectFromCase(name)` → the side, when one is chosen.
struct MatterCreationService: MatterCreating {
    let tracking: CaseTracking
    let writes: any ProjectWriting
    let projects: any ProjectProviding

    func addToMatters(_ r: AddToMattersRequest) async -> Result<MatterCreated, MatterRuleError> {
        let name = r.matterName
        // The tracked case is named by the court record's title, else the case's own number — as
        // the web's `record.case.title || titleOf(record.case)`.
        let recordTitle = JSCompat.trim(r.caseTitle ?? "")
        let title: String = recordTitle.isEmpty
            ? MatterMeta.lookupTitle(title: r.pick.title, caseType: r.pick.caseType,
                                     caseNumber: r.pick.caseNumber, caseYear: r.pick.caseYear)
            : recordTitle
        let caseID: String
        switch await tracking.track(r.pick, title: title) {
        case .success(let id): caseID = id
        case .failure(let failure): return .failure(failure)
        }
        let made: (project: Project, existed: Bool)
        do {
            made = try await writes.projectFromCase(caseID: caseID, name: name, banner: nil, color: nil)
        } catch {
            let said = DisplayText.message(for: error)
            return .failure(MatterRuleError(message: said.isEmpty ? "The matter could not be created. Try again." : said))
        }
        // As the web: the side is recorded after, and a failure there leaves the matter as made.
        if let fields = r.sideFields {
            _ = try? await writes.patch(projectID: made.project.id, fields: fields)
        }
        return .success(MatterCreated(projectID: made.project.id, existed: made.existed))
    }

    func existingMatter(for pick: CourtSearchResult) async -> String? {
        guard let tracked = try? await tracking.cases.cases() else { return nil }
        let owned = await tracking.ownedTeamIDs?() ?? []
        guard let caseID = MatterMeta.findTrackedCase(
            CaseTracking.casePick(pick), in: tracked.map(CaseTracking.candidate), ownedTeamIDs: owned)
        else { return nil }
        guard let list = try? await projects.projects(includeArchived: true) else { return nil }
        return CaseToMatter.matterID(forCase: caseID, in: list)
    }

    func openCaseAsMatter(caseID: String) async -> Result<MatterCreated, CaseToMatterFailure> {
        do {
            let made = try await writes.projectFromCase(caseID: caseID, name: nil, banner: nil, color: nil)
            return .success(MatterCreated(projectID: made.project.id, existed: made.existed))
        } catch {
            return .failure(CaseToMatterFailure.from(error))
        }
    }
}

/// The "Add to Matters" sheet — the web's `AddToMattersDialog`: the matter's name, which side the
/// user acts for, what adding does, and the one action.
///
/// See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class AddToMattersViewModel {
    var request: AddToMattersRequest { didSet { error = nil } }
    private(set) var isAdding = false
    var error: String?

    private let service: any MatterCreating

    init(request: AddToMattersRequest, service: any MatterCreating) {
        self.request = request
        self.service = service
    }

    static let explainer = [
        "We check the court every hour and keep the record up to date.",
        "You get an alert when a new order or hearing date appears.",
        "You also get a workspace for files, tasks, fees and notes.",
    ]

    /// "I act for the petitioner side", the other side's words, and "Not sure yet".
    func optionTitle(_ side: SideChoice) -> String {
        let (first, second) = request.sideKeys
        switch side {
        case .first: return "I act for the \(first.label.lowercased()) side"
        case .second: return "I act for the \(second.label.lowercased()) side"
        case .skip: return "Not sure yet — just follow the case"
        }
    }

    /// The lead party under a side, tidied from the court's capitals; nil for none.
    func optionDetail(_ side: SideChoice) -> String? {
        let lead: String?
        switch side {
        case .first: lead = request.firstLead
        case .second: lead = request.secondLead
        case .skip: lead = nil
        }
        let tidy = CourtNames.tidy(lead ?? "")
        return tidy.isEmpty ? nil : tidy
    }

    var canAdd: Bool { !isAdding && !JSCompat.trim(request.name).isEmpty }

    var actionTitle: String { isAdding ? "Adding…" : "Add to Matters" }

    func add() async -> MatterCreated? {
        guard canAdd else { return nil }
        isAdding = true
        defer { isAdding = false }
        switch await service.addToMatters(request) {
        case .success(let made): return made
        case .failure(let failure):
            error = failure.message
            return nil
        }
    }
}
