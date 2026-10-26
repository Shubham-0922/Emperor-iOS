import SwiftUI

/// What the search shows: passages inside judgments, then each collection's title matches, so
/// nobody has to guess why something came up (`SearchResults.jsx`).
struct LibrarySearchResultsView: View {
    @Environment(\.theme) private var theme

    let model: LibraryHomeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            if model.isSearching {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                    Text("Searching every collection…")
                        .font(.brand(.subheadline))
                        .foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xxl)
            } else if model.searchFailed {
                EmptyStateContent(
                    title: LibraryHomeViewModel.searchFailedTitle, systemImage: "exclamationmark.triangle",
                    message: LibraryHomeViewModel.searchFailedHint, tone: .warning
                ) {
                    Button("Try again") { Task { await model.submitSearch() } }
                        .buttonStyle(.primaryAction)
                }
            } else if model.foundNothing {
                EmptyStateContent(
                    title: model.nothingFoundTitle, systemImage: "magnifyingglass",
                    message: LibraryHomeViewModel.nothingFoundHint, tone: .neutral
                ) { EmptyView() }
            } else {
                if !model.passageItems.isEmpty {
                    passages
                }
                ForEach(model.resultGroups, id: \.category) { group in
                    collection(group)
                }
            }
        }
        .padding(.top, Spacing.sm)
        .accessibilityIdentifier("library-search-results")
    }

    private var passages: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: Spacing.sm) {
                SectionHeader(title: "Inside judgments", detail: model.passageCountText)
                if let caseLaw = model.category(LibraryCategoryKey.caseLaw.rawValue) {
                    NavigationLink(value: LibraryRoute.collection(caseLaw, query: model.submittedQuery ?? "", inText: true)) {
                        Text("All passages")
                    }
                    .buttonStyle(.quietAction)
                    .accessibilityIdentifier("library-all-passages")
                }
            }
            RecordGroup {
                ForEach(Array(model.passageItems.enumerated()), id: \.element.id) { index, doc in
                    if index > 0 { RecordDivider(inset: 14) }
                    LibraryDocRow(doc: doc, snippet: doc.snippet ?? LibrarySnippet(), badge: nil)
                }
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-passages")
    }

    private func collection(_ group: LibraryGroupedResults.Group) -> some View {
        let category = model.category(group.category) ?? LibraryCategory(key: group.category, label: group.label)
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: Spacing.sm) {
                SectionHeader(title: LibraryHomeViewModel.resultTitle(for: group), detail: LibraryDisplay.fmtCount(group.total))
                if group.total > group.items.count {
                    NavigationLink(value: LibraryRoute.collection(category, query: model.submittedQuery ?? "", inText: false)) {
                        Text("See all \(LibraryDisplay.fmtCount(group.total))")
                    }
                    .buttonStyle(.quietAction)
                    .accessibilityIdentifier("library-results-see-all-\(group.category)")
                }
            }
            RecordGroup {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, doc in
                    if index > 0 { RecordDivider(inset: 14) }
                    LibraryDocRow(doc: doc)
                }
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-results-\(group.category)")
    }
}
