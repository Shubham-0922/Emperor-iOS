import Foundation
#if canImport(Darwin)
import Observation
#endif

/// A tracked case opened as its matter — the web's `/cases/:caseId` (`CaseToMatter.jsx`): the
/// user's matter for the case, made now if there is none, opened on its Court section. The case
/// page is reached through its matter, so the case and the matter are one thing to the reader.
enum CaseToMatter {
    /// The section a case opens its matter on.
    static let section = "court"

    /// The matter that links `caseID`, among `projects` (archived ones included), or nil.
    static func matterID(forCase caseID: String, in projects: [Project]) -> String? {
        let id = caseID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        return projects.first { ($0.linkedCaseID ?? "") == id }?.id
    }
}

/// "Open as matter" on a case's page: a wait, then the matter — or why not, with Try again for a
/// failure that is worth another try.
///
/// See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class CaseToMatterViewModel {
    let caseID: String
    private(set) var isOpening = false
    var failure: CaseToMatterFailure?

    private let service: any MatterCreating

    init(caseID: String, service: any MatterCreating) {
        self.caseID = caseID
        self.service = service
    }

    static let opening = "Opening the matter for this case…"

    /// The matter to open, or nil with `failure` set. A second tap while the first is on its way
    /// does nothing.
    func open() async -> MatterCreated? {
        guard !isOpening else { return nil }
        isOpening = true
        defer { isOpening = false }
        failure = nil
        switch await service.openCaseAsMatter(caseID: caseID) {
        case .success(let made): return made
        case .failure(let why):
            failure = why
            return nil
        }
    }
}
