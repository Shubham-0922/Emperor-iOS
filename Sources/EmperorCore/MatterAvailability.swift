import Foundation

/// Which parts of the matter workspace this build carries.
enum MatterAvailability {
    /// Ask, Files and Drafts — the sections that read and write the matter's own documents and
    /// conversations. A switch rather than a constant in the bar, so the sections can be taken
    /// off again in one place should their routes ever have to be held back.
    static let contentSections = true

    /// The sections that need `contentSections`.
    static let contentSectionKeys: Set<MatterVocabulary.MatterSection> = [.ask, .files, .drafts]
}
