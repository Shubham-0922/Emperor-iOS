import SwiftUI

/// The destinations the workspace presents whole — each owns its `NavigationStack` and a Done.
///
/// This was the More tab — the web's sidebar on a phone (`src/shell/MobileNav.jsx`). The
/// redesign has five tabs, and this file is now just the destinations behind them: **More**'s
/// Library row and its Doc tools open these as one sheet (`.library`, `.ocr`, `.fileTools`),
/// and the Calendar tab embeds the Corporate calendar directly rather than presenting it.
/// The rest — the role's workspace, All tools, Translate, Projects, eAuctions — lost their row
/// when the Tools sections left You; their screens, view models, services and tests are all
/// still here and still built. To bring one back, set the sheet's `destination` from a row —
/// and add that row to the UI tests and the screenshot tour. Projects and eAuctions stay hidden
/// at the product owner's request either way.
///
/// Labels are the web's — **Translate**, **eAuctions** — not the names this app once used, so
/// someone who uses both learns one vocabulary.
///
/// - Important: every destination here **presents rather than pushes**. Every one owns a
///   `NavigationStack` — they were built as self-contained modals — and pushing one into a
///   tab's stack would nest two stacks, with two navigation bars and a back button that unwinds
///   the wrong one. So each carries its own "Done" at `.cancellationAction`, and More owns the
///   one sheet they are presented in.
enum ToolDestination: String, Identifiable {
    case deck, corporateCalendar, library, projects, tools, fileTools, ocr, translate, eAuctions

    var id: String { rawValue }

    var title: String {
        switch self {
        // Named for the role rather than fixed, because that is what it is.
        case .deck: return "Your workspace"
        case .corporateCalendar: return "Corporate Calendar"
        case .library: return "Library"
        case .projects: return "Projects"
        case .tools: return "All tools"
        case .fileTools: return "File tools"
        case .ocr: return "OCR"
        case .translate: return "Translate"
        case .eAuctions: return "eAuctions"
        }
    }

    /// Chosen to read as the web's `lucide` icon for the same row.
    func symbol(for role: PractitionerRole) -> String {
        switch self {
        case .deck: return role.systemImage
        case .corporateCalendar: return "calendar.badge.checkmark"
        case .library: return "books.vertical"
        case .projects: return "folder.badge.person.crop"
        case .tools: return "wrench.and.screwdriver"
        case .fileTools: return "scissors"
        case .ocr: return "doc.text.viewfinder"
        case .translate: return "character.bubble"
        case .eAuctions: return "hammer"
        }
    }

    /// The screen, at the size of a page on iPad.
    @MainActor @ViewBuilder
    var screen: some View {
        switch self {
        case .deck: RoleHomeView()
        case .corporateCalendar: ComplianceCalendarView()
        case .library: LibraryView()
        // Read-only while the feature is trialled on the web. See `ProjectService`.
        case .projects: ProjectListView()
        case .tools: ToolsListView()
        case .fileTools: PDFToolsView()
        // One screen with an OCR | Translate switch at its head; each row opens it in its own mode.
        case .ocr: OCRView(mode: .ocr)
        case .translate: OCRView(mode: .translate)
        case .eAuctions: AuctionListView()
        }
    }
}
