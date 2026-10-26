import Foundation

/// A court case picked in the search, as a **tracked** case — a port of the platform's
/// `src/components/projects/trackCase.js`.
///
/// A matter scrapes nothing itself: it links one of the user's tracked cases, whose worker keeps the
/// hearings and the next date current. New matter and the Court section both hand over a picked
/// case, and they must agree on what "the same case" is, or one of them files a second copy of a
/// case the user already tracks. So the lookup and the save live here once.
struct CaseTracking: Sendable {
    let cases: any CaseProviding
    let search: any CourtSearching
    /// The teams the user owns, so a case their own team tracks is preferred over a colleague's
    /// copy. Nil when not known; the first match is then used, as the web does with no teams.
    var ownedTeamIDs: (@Sendable () async -> Set<String>)?

    init(cases: any CaseProviding, search: any CourtSearching,
         ownedTeamIDs: (@Sendable () async -> Set<String>)? = nil) {
        self.cases = cases
        self.search = search
        self.ownedTeamIDs = ownedTeamIDs
    }

    static let fallbackError = "The case could not be added to your tracked cases."

    /// The tracked case's id for this pick: one the user already tracks, else the case saved now
    /// (to the user's personal team, as `/save-case` files a case sent without a team).
    ///
    /// `title` stands in for a card with no cause title — the matter's name reads better in the
    /// tracked cases than "Untitled Case". Never throws: every failure is a sentence to show.
    func track(_ pick: CourtSearchResult, title: String?) async -> Result<String, MatterRuleError> {
        let owned = await ownedTeamIDs?() ?? []
        if let known = await find(pick, owned: owned) { return .success(known) }

        var card = pick
        if (card.title ?? "").isEmpty, let title, !JSCompat.trim(title).isEmpty { card.title = title }
        var failure: String?
        do {
            switch try await search.save(card) {
            case .saved(let id): return .success(id)
            case .alreadySaved: break
            case .refusedAsIndistinguishable(let message): return .failure(MatterRuleError(message: message))
            }
        } catch {
            failure = DisplayText.message(for: error)
        }
        // Refused as "already there", or the save failed: look again — if it is tracked now, it is
        // the one to use.
        if let found = await find(pick, owned: owned) { return .success(found) }
        return .failure(MatterRuleError(message: failure ?? Self.fallbackError))
    }

    private func find(_ pick: CourtSearchResult, owned: Set<String>) async -> String? {
        guard let tracked = try? await cases.cases() else { return nil }
        return MatterMeta.findTrackedCase(Self.casePick(pick), in: tracked.map(Self.candidate), ownedTeamIDs: owned)
    }

    /// The search card, under the keys `findTrackedCase` compares.
    static func casePick(_ r: CourtSearchResult) -> MatterMeta.CasePick {
        MatterMeta.CasePick(
            courtType: r.courtType, courtCode: r.courtCode, courtName: r.courtName, caseType: r.caseType,
            caseNumber: r.caseNumber, caseYear: r.caseYear, cnr: r.cnr, diaryNumber: r.diaryNumber,
            title: r.title, parties: r.parties, judge: r.judge, status: r.status, stage: r.stage,
            nextHearingDate: r.nextHearingDate)
    }

    /// A tracked case, as `findTrackedCase` reads it. The stored `ext_id` is not sent with the
    /// docket, so it is computed from the fields, as the server computed it on save.
    static func candidate(_ c: LegalCase) -> MatterMeta.TrackedCaseCandidate {
        MatterMeta.TrackedCaseCandidate(
            id: c.id, teamID: c.teamID, cnr: c.cnr, diaryNumber: c.diaryNumber, caseNumber: c.caseNumber,
            caseYear: c.caseYear, caseType: c.caseType, courtCode: c.courtCode, courtName: c.courtName)
    }
}
