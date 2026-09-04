import SwiftUI

/// Everything that is not one of the three primary destinations.
///
/// The web app's mobile navigation is a bottom bar of **Home · Cases · Chat · More**, where
/// "More" opens the full sidebar (`src/shell/MobileNav.jsx`). This is that sidebar.
///
/// Labels are the web's, not the ones this app used to use. It said "Diary", "Digitise" and
/// "Auctions" where the platform says **Calendar**, **Translate** and **Liquidations**; someone
/// who uses both should not have to learn two vocabularies for one product.
///
/// Order follows `src/shell/Sidebar.jsx`, minus what is already a tab and minus what this client
/// deliberately does not carry:
///
/// - **Upgrade / `/buy`** — a pricing surface would attach StoreKit obligations to an app that
///   takes no money. It must stay absent.
/// - **Filing Assembly** — a 293-page bundle where a wrong folio gets the matter rejected at the
///   registry should not be assembled on a phone (`GAPS.md` Tier 3).
/// - **Projects** — routed on the web but deliberately unlinked while it is trialled.
/// - **My Files** — `FileLibraryView` is a picker: it requires `alreadyAttached` and `onAttach`
///   and its confirmation action is "Attach". Giving it a browse mode is real work, not a row,
///   so it stays reachable from the composer until that is done.
///
/// - Important: every destination here **presents rather than pushes**. All five own a
///   `NavigationStack` — they were built as self-contained modals and every other call site
///   already presents them that way. Pushing one into this list's stack would nest two stacks
///   and give it two navigation bars and a back button that unwinds the wrong one.
struct MoreView: View {
    @Environment(\.theme) private var theme
    @State private var destination: Destination?

    /// The rows, in the platform's own order.
    private enum Destination: String, Identifiable {
        case calendar, library, translate, liquidations, settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .calendar: return "Calendar"
            case .library: return "Library"
            case .translate: return "Translate"
            case .liquidations: return "Liquidations"
            case .settings: return "Settings"
            }
        }

        /// Chosen to read as the web's `lucide` icon for the same row.
        var symbol: String {
            switch self {
            case .calendar: return "calendar"
            case .library: return "books.vertical"
            case .translate: return "character.bubble"
            case .liquidations: return "hammer"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(.calendar)
                    row(.library)
                } header: {
                    SectionHeader(title: "Your practice")
                }

                Section {
                    row(.translate)
                    row(.liquidations)
                } header: {
                    // The platform groups these under "Tools" in its rail, and the tool registry
                    // itself lands here when it is ported (PARITY_PLAN.md, Phase 2).
                    SectionHeader(title: "Tools")
                }

                Section {
                    row(.settings)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.canvas)
            .navigationTitle("More")
            .sheet(item: $destination) { chosen in
                switch chosen {
                case .calendar: CalendarView()
                case .library: LibraryView()
                case .translate: OCRView()
                case .liquidations: AuctionListView()
                case .settings: SettingsView()
                }
            }
        }
    }

    private func row(_ item: Destination) -> some View {
        Button {
            destination = item
        } label: {
            HStack {
                Label(item.title, systemImage: item.symbol)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.brand(.footnote, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
