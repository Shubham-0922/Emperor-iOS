import Foundation

/// The three document-analysis tools the web runs as background jobs. The raw value is the
/// `tool` name the platform knows each by.
///
/// Every sentence here is the web page's own (`src/pages/analysis/DevilsAdvocate.jsx`,
/// `DocIndexPage.jsx`, `ListOfDatesPage.jsx`), so the three tools read the same in both places.
enum AnalysisToolKind: String, Sendable, CaseIterable {
    case devilsAdvocate = "devils-advocate"
    case docIndex = "doc-index"
    case listOfDates = "list-of-dates"

    var title: String {
        switch self {
        case .devilsAdvocate: return "Devil's Advocate"
        case .docIndex: return "Doc Index"
        case .listOfDates: return "List of Dates"
        }
    }

    /// The other name a tool goes by, shown beside its title.
    var aka: String? {
        self == .listOfDates ? "Synopsis of dates" : nil
    }

    var tagline: String {
        switch self {
        case .devilsAdvocate:
            return "Find where your case is weak and what the other side's lawyer will ask, so you are ready before they ask it."
        case .docIndex:
            return "One table of every document: what it is, who it is between, what it says. The AI picks the columns."
        case .listOfDates:
            return "Every date in your papers, on one page: who did what, and when."
        }
    }

    /// Step 2 of the intake: the optional note's heading.
    var referenceLabel: String {
        switch self {
        case .devilsAdvocate: return "Say who you act for and where you feel exposed"
        case .docIndex: return "Anything the index should focus on?"
        case .listOfDates: return "Which side are you? Anything to emphasise?"
        }
    }

    var referencePlaceholder: String {
        switch self {
        case .devilsAdvocate:
            return "For example: We act for Helios, the plaintiff. I am worried about the arbitration clause and the older invoices."
        case .docIndex:
            return "For example: flag anything that helps prove the unpaid invoices, and note which papers have missing signatures."
        case .listOfDates:
            return "e.g. We act for the plaintiff, Helios. Please stress the payment history and the dates that matter for limitation."
        }
    }

    var referenceHint: String {
        switch self {
        case .devilsAdvocate: return "Optional. A line or two helps the report focus on what keeps you up at night."
        case .docIndex: return "Leave this blank and the AI will choose the columns on its own."
        case .listOfDates: return "Optional. It helps decide which side of the table each event goes on."
        }
    }

    /// The one button that starts a run.
    var cta: String {
        switch self {
        case .devilsAdvocate: return "Find my blind spots"
        case .docIndex: return "Build my index"
        case .listOfDates: return "Build the list of dates"
        }
    }

    /// The line beside the button once documents are chosen. List of Dates drops the web's
    /// mention of its sample, which the app does not carry.
    var ctaNote: String {
        switch self {
        case .devilsAdvocate:
            return "You will get a full prep report: weak spots, likely questions, missing papers."
        case .docIndex:
            return "Usually takes under a minute. The AI decides which columns are useful for these papers."
        case .listOfDates:
            return "Takes a few minutes for long papers. You can copy it or save it as a Word file."
        }
    }

    /// The beside-the-button line before any document is chosen.
    static let chooseFirstNote = "Choose at least one document to begin."

    /// The running screen's heading.
    var runningTitle: String {
        switch self {
        case .devilsAdvocate: return "Playing the other side"
        case .docIndex: return "Building your index"
        case .listOfDates: return "Building your list of dates"
        }
    }

    /// The failure panel's heading.
    var failureTitle: String {
        switch self {
        case .devilsAdvocate: return "We could not finish the report"
        case .docIndex: return "We could not build your index"
        case .listOfDates: return "The list could not be built"
        }
    }

    /// Said after a failure that is not about the plan. Only the report says it.
    var failureReassurance: String? {
        self == .devilsAdvocate ? " Your documents are safe; nothing was shared." : nil
    }

    /// A finished run whose result cannot be drawn.
    var unreadableMessage: String {
        switch self {
        case .devilsAdvocate: return "The report came back in a form we could not read."
        case .docIndex: return "The AI sent back an index we could not read. Please try again."
        case .listOfDates: return "The list came back in a form we could not read."
        }
    }

    /// A run from History whose stored result cannot be drawn.
    var unreadableSavedMessage: String {
        self == .devilsAdvocate ? "This saved report could not be read." : "This saved run could not be read."
    }

    var systemImage: String {
        switch self {
        case .devilsAdvocate: return "exclamationmark.shield"
        case .docIndex: return "tablecells"
        case .listOfDates: return "calendar"
        }
    }

    /// The History panel's subtitle.
    var historySubtitle: String { "Your past runs of \(title). Only you can see them." }
}
