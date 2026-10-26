import SwiftUI

/// The web sidebar's case tools and the Team screen, as More draws and opens them.
///
/// Each tool's screen lives in its feature's folder and says itself whether it is built
/// (`isReady`). A card for a tool that is not ready is drawn but does nothing; a ready one opens
/// its screen as a sheet. Every screen owns its `NavigationStack` and its "Done", as the
/// `ToolDestination` screens do.
enum WorkspaceTool: String, Identifiable, CaseIterable {
    case fetchOrders, devilsAdvocate, docIndex, listOfDates, limitationRadar, filingAssembly, teams

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fetchOrders: return "Fetch Orders"
        case .devilsAdvocate: return "Devil's Advocate"
        case .docIndex: return "Doc Index"
        case .listOfDates: return "List of Dates"
        case .limitationRadar: return "Limitation Radar"
        case .filingAssembly: return "Filing Assembly"
        case .teams: return "Team"
        }
    }

    var subtitle: String {
        switch self {
        case .fetchOrders: return "Autopull from SC & Delhi HC portals"
        case .devilsAdvocate: return "AI adversary cross-exam prep"
        case .docIndex: return "Pagination & court filing indices"
        case .listOfDates: return "Chronology generator for SLP & writs"
        case .limitationRadar: return "Limitation periods & condonation risk"
        case .filingAssembly: return "Index, annexures & paper-book"
        case .teams: return "Share matters with colleagues"
        }
    }

    var systemImage: String {
        switch self {
        case .fetchOrders: return "doc.text.magnifyingglass"
        case .devilsAdvocate: return "shield"
        case .docIndex: return "tablecells"
        case .listOfDates: return "calendar"
        case .limitationRadar: return "exclamationmark.triangle"
        case .filingAssembly: return "books.vertical.fill"
        case .teams: return "person.2"
        }
    }

    /// The product tag on a case-tool card; `nil` for a workspace row, which has none.
    var tag: String? {
        switch self {
        case .fetchOrders: return "Live Court"
        case .devilsAdvocate: return "Adversary AI"
        case .docIndex: return "E-Filing"
        case .listOfDates: return "SLP Ready"
        case .limitationRadar: return "Deadlines"
        case .filingAssembly: return "E-Filing"
        case .teams: return nil
        }
    }

    /// Whether the tool's screen is built. Until it is, its card stays inert. On the main actor
    /// because each screen, as a `View`, keeps its flag there.
    @MainActor
    var isReady: Bool {
        switch self {
        case .fetchOrders: return FetchOrdersScreen.isReady
        case .devilsAdvocate, .docIndex, .listOfDates: return AnalysisToolScreen.isReady
        case .limitationRadar: return LimitationRadarScreen.isReady
        case .filingAssembly: return FilingAssemblyScreen.isReady
        case .teams: return TeamsScreen.isReady
        }
    }

    /// The case tools, in the order More draws their cards.
    static let caseTools: [WorkspaceTool] = [
        .fetchOrders, .devilsAdvocate, .docIndex, .listOfDates, .limitationRadar, .filingAssembly,
    ]

    /// The tool's screen, at the size of a page on iPad.
    @MainActor @ViewBuilder
    var screen: some View {
        switch self {
        case .fetchOrders: FetchOrdersScreen()
        case .devilsAdvocate: AnalysisToolScreen(kind: .devilsAdvocate)
        case .docIndex: AnalysisToolScreen(kind: .docIndex)
        case .listOfDates: AnalysisToolScreen(kind: .listOfDates)
        case .limitationRadar: LimitationRadarScreen()
        case .filingAssembly: FilingAssemblyScreen()
        case .teams: TeamsScreen()
        }
    }
}
