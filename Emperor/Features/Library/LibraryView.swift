import SwiftUI

/// Where a tap in the Library leads, pushed on the Library's own stack.
enum LibraryRoute: Hashable {
    /// A collection, with the search it was opened with (and Case Law's "Words inside").
    case collection(LibraryCategory, query: String, inText: Bool)
    /// Every book of Books & law reports, A–Z.
    case allBooks(LibraryCategory, query: String)
    /// Every volume of one series.
    case series(String)
    /// The reading room.
    case doc(LibraryDoc)
    /// An Act page — any Bare Acts id opens its Act.
    case act(id: Int, seed: LibraryDoc?)

    /// An Act opens its Act page, anything else the reading room (`openAny`).
    static func open(_ doc: LibraryDoc) -> LibraryRoute {
        doc.opensAsAct ? .act(id: doc.id, seed: doc) : .doc(doc)
    }
}

/// The reference library: every collection's shelf, a search across them all, and each
/// collection, document, judgment and Act a push away (`pages/Library.jsx`).
///
/// A sheet with its own stack. "Done" stays in the root bar for every state the catalogue can be
/// in — including "unavailable", where swiping is not an obvious way out.
struct LibraryView: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var model: LibraryHomeViewModel?
    @State private var covers: LibraryCoverLoader?
    @State private var path: [LibraryRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let model {
                    root(model)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(theme.groupedBackground)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                destination(route)
            }
        }
        .environment(\.libraryCovers, covers)
        .task {
            guard model == nil else { return }
            covers = LibraryCoverLoader(service: session.library)
            let created = LibraryHomeViewModel(service: session.library)
            model = created
            await created.load()
        }
    }

    @ViewBuilder
    private func root(_ model: LibraryHomeViewModel) -> some View {
        @Bindable var bindable = model

        content(model)
            .searchable(text: $bindable.query, prompt: "Search judgments, acts, books and orders")
            .onSubmit(of: .search) {
                Task { await model.submitSearch() }
            }
            .onChange(of: model.query) { _, new in
                if new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, model.isShowingResults {
                    model.clearSearch()
                }
            }
    }

    @ViewBuilder
    private func content(_ model: LibraryHomeViewModel) -> some View {
        if model.isUnavailable {
            EmptyStateView(
                LibraryHomeViewModel.unavailableTitle, systemImage: "books.vertical",
                message: LibraryHomeViewModel.unavailableMessage, tone: .neutral
            ) {
                Button("Try again") {
                    Task { await model.load() }
                }
                .buttonStyle(.primaryAction)
            }
            .accessibilityIdentifier("library-unavailable")
        } else if let failure = model.state.failure, model.categories.isEmpty {
            LoadFailureView(failure: failure, retry: { await model.load() })
        } else if model.categories.isEmpty, !model.state.hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.isEmpty {
            EmptyStateView(
                "Nothing on the shelves yet", systemImage: "books.vertical",
                message: "The library’s collections will appear here as they are added.", tone: .neutral)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    categoryStrip(model)
                    if model.isShowingResults {
                        LibrarySearchResultsView(model: model)
                    } else {
                        LibraryHomeView(model: model)
                    }
                }
                .padding(.bottom, Spacing.xxl)
            }
            .refreshable { await model.load() }
        }
    }

    /// The collections as chips with their counts; each opens its collection with the search kept.
    private func categoryStrip(_ model: LibraryHomeViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(model.orderedCategories) { category in
                    NavigationLink(value: LibraryRoute.collection(
                        category, query: model.submittedQuery ?? "", inText: false)) {
                        ChipLabel(
                            title: category.displayLabel,
                            systemImage: LibraryDisplay.theme(category.key).systemImage,
                            count: category.count,
                            isSelected: false)
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: false))
                    .accessibilityIdentifier("library-category-\(category.key)")
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.sm)
        }
    }

    @ViewBuilder
    private func destination(_ route: LibraryRoute) -> some View {
        switch route {
        case .collection(let category, let query, let inText):
            switch LibraryCategoryKey(rawValue: category.key) {
            case .bareActs:
                LibraryBareActsView(category: category, query: query)
            case .books where query.isEmpty:
                LibraryBooksView(category: category)
            default:
                LibraryCollectionView(category: category, query: query, inText: inText)
            }
        case .allBooks(let category, let query):
            LibraryCollectionView(category: category, query: query, inText: false)
        case .series(let name):
            LibrarySeriesView(series: name)
        case .doc(let doc):
            LibraryReadingRoom(seed: doc)
        case .act(let id, let seed):
            LibraryActPage(id: id, seed: seed)
        }
    }
}
