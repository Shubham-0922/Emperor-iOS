import Foundation

/// Which parts of the matter workspace this build carries.
enum MatterAvailability {
    /// Ask, Files and Drafts — the sections that read and write the matter's own documents and
    /// conversations. Off until those routes are built here; the section bar leaves them out
    /// rather than offering screens that do nothing.
    static let contentSections = false

    /// The sections that need `contentSections`.
    static let contentSectionKeys: Set<MatterVocabulary.MatterSection> = [.ask, .files, .drafts]
}
