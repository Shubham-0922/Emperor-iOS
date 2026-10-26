import Foundation

/// The three document-analysis tools the web runs as background jobs. The raw value is the
/// `tool` name the platform knows each by.
enum AnalysisToolKind: String, Sendable, CaseIterable {
    case devilsAdvocate = "devils-advocate"
    case docIndex = "doc-index"
    case listOfDates = "list-of-dates"
}
