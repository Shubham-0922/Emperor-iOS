import SwiftUI

/// One collection: its facets as filters, its sort, its numbered pages — a list for what is read
/// by reference and date (case law, regulator orders, Parliament), a grid of covers for the rest
/// (`categories/CaseLaw.jsx`, `books/CoverGrid.jsx`).
struct LibraryCollectionView: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass

    let category: LibraryCategory
    var query = ""
    var inText = false

    @State private var model: LibraryCollectionViewModel?
    @State private var searchText = ""
    @State private var isShowingFilters = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.groupedBackground)
        .navigationTitle(category.displayLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingFilters = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel(filterLabel)
                .accessibilityIdentifier("library-filters")
                .disabled(model == nil)
            }
        }
        .sheet(isPresented: $isShowingFilters) {
            if let model {
                LibraryFilterSheet(model: model)
            }
        }
        .task {
            guard model == nil else { return }
            searchText = query
            let created = LibraryCollectionViewModel(
                category: category, query: query, mode: inText ? .text : .titles, service: session.library)
            model = created
            await created.load()
        }
        .task(id: searchText) {
            // Searched as the reader pauses, the way the field elsewhere in the app filters.
            guard let model, searchText.trimmingCharacters(in: .whitespacesAndNewlines) != model.query else { return }
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await model.setQuery(searchText)
        }
    }

    private var filterLabel: String {
        let n = model?.activeFilterCount ?? 0
        return n > 0 ? "Filters and sort, \(n) on" : "Filters and sort"
    }

    private var gridWidth: CGFloat { sizeClass == .regular ? 132 : 104 }

    private func content(_ model: LibraryCollectionViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    SerifHeader(title: model.category.displayLabel, subtitle: model.theme.blurb.isEmpty ? nil : model.theme.blurb)
                        .padding(.horizontal, Spacing.gutter)
                        .id("library-top")
                    RecordSearchField(text: $searchText, prompt: "Search \(model.category.displayLabel.lowercased())")
                        .padding(.horizontal, Spacing.gutter)
                        .accessibilityIdentifier("library-collection-search")
                    if model.offersTextMode {
                        RecordSegmentedControl(
                            label: "Search in",
                            options: [(value: LibraryCollectionViewModel.Mode.titles, title: "Titles and parties"),
                                      (value: LibraryCollectionViewModel.Mode.text, title: "Words inside")],
                            selection: Binding(
                                get: { model.effectiveMode },
                                set: { mode in Task { await model.setMode(mode) } }))
                            .padding(.horizontal, Spacing.gutter)
                            .accessibilityIdentifier("library-search-mode")
                    }
                    if model.isCaseLaw, !model.courts.isEmpty {
                        LibraryCourtChips(courts: model.courts, selected: model.filters.court) { value in
                            Task { await model.setCourt(value) }
                        }
                    }
                    if !model.activeFilters.isEmpty {
                        activeFilters(model)
                    }
                    if !model.countLine.isEmpty {
                        Text(model.countLine)
                            .font(.brand(.subheadline, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Spacing.gutter)
                            .accessibilityIdentifier("library-count")
                    }
                    results(model)
                    if (model.result?.items.isEmpty == false) && model.pageCount > 1 {
                        pager(model) {
                            withAnimation { proxy.scrollTo("library-top", anchor: .top) }
                        }
                    }
                }
                .padding(.vertical, Spacing.lg)
            }
            .refreshable { await model.reload() }
        }
    }

    private func activeFilters(_ model: LibraryCollectionViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(model.activeFilters) { filter in
                    Button {
                        Task { await model.remove(filter) }
                    } label: {
                        ChipLabel(title: filter.label, systemImage: "xmark", isSelected: true)
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: true))
                    .accessibilityLabel("Remove \(filter.label)")
                    .accessibilityIdentifier("library-active-\(filter.field.rawValue)")
                }
                if model.activeFilters.count > 1 {
                    Button("Clear all") { Task { await model.clearFilters() } }
                        .buttonStyle(.quietAction)
                }
            }
            .padding(.horizontal, Spacing.gutter)
        }
    }

    @ViewBuilder
    private func results(_ model: LibraryCollectionViewModel) -> some View {
        if let failure = model.state.failure {
            EmptyStateContent(
                title: model.isCaseLaw ? "We couldn’t load these judgments" : "This shelf could not be loaded",
                systemImage: "exclamationmark.triangle", message: failure.message, tone: .warning
            ) {
                if failure.isRetryable {
                    Button("Try again") { Task { await model.reload() } }
                        .buttonStyle(.secondaryAction)
                }
            }
        } else if model.result == nil {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xxxl)
        } else if model.items.isEmpty {
            EmptyStateContent(title: model.emptyTitle, systemImage: "books.vertical", message: model.emptyHint, tone: .neutral) {
                if model.activeFilterCount > 0 {
                    Button("Clear filters") { Task { await model.clearFilters() } }
                        .buttonStyle(.secondaryAction)
                } else if model.isCaseLaw, !model.query.isEmpty, model.effectiveMode == .titles {
                    Button("Search inside judgments") { Task { await model.setMode(.text) } }
                        .buttonStyle(.secondaryAction)
                }
            }
        } else if model.showsList {
            RecordGroup {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, doc in
                    if index > 0 { RecordDivider(inset: model.isCaseLaw ? 62 : 14) }
                    row(doc, model)
                }
            }
            .opacity(model.isStale ? 0.5 : 1)
            .padding(.horizontal, Spacing.gutter)
            .accessibilityIdentifier("library-results-list")
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: gridWidth), spacing: Spacing.md, alignment: .top)],
                      alignment: .leading, spacing: Spacing.lg) {
                ForEach(model.items) { doc in
                    LibraryDocCard(doc: doc, width: gridWidth, meta: caption(doc, model))
                }
            }
            .opacity(model.isStale ? 0.5 : 1)
            .padding(.horizontal, Spacing.gutter)
            .accessibilityIdentifier("library-results-grid")
        }
    }

    @ViewBuilder
    private func row(_ doc: LibraryDoc, _ model: LibraryCollectionViewModel) -> some View {
        if model.isCaseLaw {
            LibraryCaseRow(doc: doc, dateUnclear: model.isDateUnclear(doc),
                           showsPassage: model.effectiveMode == .text)
        } else {
            LibraryDocRow(doc: doc, meta: caption(doc, model), eyebrow: LibraryDisplay.referenceLine(doc))
        }
    }

    /// The facts under a document, in each collection's own words (`categories/*.jsx`).
    private func caption(_ doc: LibraryDoc, _ model: LibraryCollectionViewModel) -> [String] {
        switch LibraryCategoryKey(rawValue: model.key) {
        case .regulatorOrders:
            return [doc.publisher, doc.kind.flatMap { LibraryDisplay.kindOne[$0] },
                    doc.decidedOn == nil ? doc.year.map(String.init) : nil].compactMap { LibraryDisplay.truthy($0) }
        case .tribunals:
            return [doc.publisher, doc.decidedOn == nil ? doc.year.map(String.init) : nil].compactMap { LibraryDisplay.truthy($0) }
        case .lawCommission:
            return [doc.reportNo.map { "Report No. \($0)" }, doc.year.map(String.init),
                    doc.lang.map { "\($0) edition" }].compactMap { LibraryDisplay.truthy($0) }
        case .institutes:
            return [doc.publisher, doc.year.map(String.init)].compactMap { LibraryDisplay.truthy($0) }
        case .books, .parliament, .legalAid:
            return LibraryDisplay.captionMeta(doc, withSeries: model.key == LibraryCategoryKey.books.rawValue, withSize: model.showsList)
        default:
            return LibraryDisplay.docMeta(doc)
        }
    }

    private func pager(_ model: LibraryCollectionViewModel, scrollUp: @escaping @MainActor () -> Void) -> some View {
        AdaptiveStack(horizontalAlignment: .center, verticalAlignment: .center, spacing: Spacing.md) {
            Button {
                Task {
                    await model.previousPage()
                    scrollUp()
                }
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .buttonStyle(.compactSecondaryAction)
            .disabled(!model.canGoBack)
            .accessibilityIdentifier("library-page-prev")

            Text(model.pageLabel)
                .font(.brand(.subheadline, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("library-page-label")

            Button {
                Task {
                    await model.nextPage()
                    scrollUp()
                }
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .buttonStyle(.compactSecondaryAction)
            .disabled(!model.canGoForward)
            .accessibilityIdentifier("library-page-next")
        }
        .padding(.horizontal, Spacing.gutter)
    }
}
