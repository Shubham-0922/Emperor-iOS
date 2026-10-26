import SwiftUI

/// Bare Acts: an index that reads like the index of a statute book — the codes on every
/// advocate's desk, then every Act by name, jurisdiction, letter and what it holds
/// (`categories/BareActs.jsx`). Every Act opens its Act page.
struct LibraryBareActsView: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass

    let category: LibraryCategory
    var query = ""

    @State private var model: LibraryActIndexViewModel?
    @State private var searchText = ""

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
                if let model {
                    Menu {
                        Picker("Sort", selection: Binding(
                            get: { model.query.sort ?? "" },
                            set: { value in Task { await model.setSort(value) } }
                        )) {
                            ForEach(LibraryActIndexViewModel.sorts, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sort")
                    .accessibilityIdentifier("library-acts-sort")
                }
            }
        }
        .task {
            guard model == nil else { return }
            searchText = query
            let created = LibraryActIndexViewModel(q: query, total: category.count, service: session.library)
            model = created
            await created.load()
        }
        .task(id: searchText) {
            guard let model, searchText.trimmingCharacters(in: .whitespacesAndNewlines) != (model.query.q ?? "") else { return }
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await model.search(searchText)
        }
    }

    private var cardWidth: CGFloat { sizeClass == .regular ? 132 : 104 }

    private func content(_ model: LibraryActIndexViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    SerifHeader(
                        title: "Bare acts",
                        subtitle: "Every Central and State Act, bound with its rules, regulations, notifications and amendments."
                            + (category.count.map { " \(LibraryDisplay.fmtCount($0)) documents." } ?? ""))
                        .padding(.horizontal, Spacing.gutter)
                        .id("acts-top")

                    if model.isBrowsing, !model.featured.isEmpty {
                        featured(model)
                    }

                    RecordSearchField(text: $searchText, prompt: "Find an Act — name or short name: crpc, pmla")
                        .padding(.horizontal, Spacing.gutter)
                        .accessibilityIdentifier("library-acts-search")

                    if !model.jurisdictions.isEmpty {
                        chipStrip(model.jurisdictions.map { (value: $0.value, label: $0.displayLabel, count: $0.count) },
                                  selected: model.query.jurisdiction, prefix: "library-jurisdiction") { value in
                            Task { await model.setJurisdiction(value) }
                        }
                    }
                    chipStrip(LibraryDisplay.hasFilters.map { (value: $0.key, label: $0.label, count: nil) },
                              selected: model.query.has, prefix: "library-has", leading: "Contains") { value in
                        Task { await model.setHas(value) }
                    }
                    if !model.letters.isEmpty {
                        letterStrip(model)
                    }

                    if !model.countLine.isEmpty {
                        AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: Spacing.sm) {
                            Text(model.countLine)
                                .font(.brand(.subheadline, weight: .medium))
                                .foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("library-count")
                            if model.isFiltered {
                                Button("Clear filters") {
                                    searchText = ""
                                    Task { await model.clearFilters() }
                                }
                                .buttonStyle(.quietAction)
                            }
                        }
                        .padding(.horizontal, Spacing.gutter)
                    }

                    results(model)

                    if model.pageCount > 1 {
                        pager(model) { withAnimation { proxy.scrollTo("acts-top", anchor: .top) } }
                    }
                }
                .padding(.vertical, Spacing.lg)
            }
            .refreshable { await model.reload() }
        }
    }

    private func featured(_ model: LibraryActIndexViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "On every advocate’s desk")
                .padding(.horizontal, Spacing.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Spacing.md) {
                    ForEach(model.featured) { act in
                        actCard(act, model)
                    }
                }
                .padding(.horizontal, Spacing.gutter)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-acts-featured")
    }

    private func actCard(_ act: LibraryDoc, _ model: LibraryActIndexViewModel) -> some View {
        let title = LibraryDisplay.actTitle(act)
        let holds = model.holds(act)
        return NavigationLink(value: LibraryRoute.act(id: act.id, seed: act)) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                LibraryCoverView(doc: act, width: cardWidth, showsImage: false)
                Text(title)
                    .font(.brand(.footnote, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .dynamicLineLimit(3)
                if !holds.isEmpty {
                    Text(holds)
                        .font(.brand(.caption2))
                        .foregroundStyle(theme.textTertiary)
                        .dynamicLineLimit(2)
                }
            }
            .frame(width: cardWidth, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, LibraryDisplay.jurisdictionOf(act).label, holds].filter { !$0.isEmpty }.joined(separator: ". "))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("library-doc-\(act.id)")
    }

    @ViewBuilder
    private func results(_ model: LibraryActIndexViewModel) -> some View {
        if let failure = model.state.failure {
            EmptyStateContent(title: "The index could not be loaded", systemImage: "exclamationmark.triangle",
                              message: failure.message, tone: .warning) {
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
            EmptyStateContent(title: "No Act in this part of the index", systemImage: "scroll",
                              message: model.emptyHint, tone: .neutral) {
                if model.isFiltered {
                    Button("Clear filters") {
                        searchText = ""
                        Task { await model.clearFilters() }
                    }
                    .buttonStyle(.secondaryAction)
                }
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cardWidth), spacing: Spacing.md, alignment: .top)],
                      alignment: .leading, spacing: Spacing.lg) {
                ForEach(model.items) { act in
                    actCard(act, model)
                }
            }
            .opacity(model.isStale ? 0.5 : 1)
            .padding(.horizontal, Spacing.gutter)
            .accessibilityIdentifier("library-results-grid")
        }
    }

    private func chipStrip(
        _ options: [(value: String, label: String, count: Int?)],
        selected: String?, prefix: String, leading: String? = nil,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                if let leading {
                    Text(leading)
                        .recordText(RecordTokens.Typography.label)
                        .foregroundStyle(theme.textTertiary)
                }
                ForEach(options, id: \.value) { option in
                    let isSelected = selected == option.value
                    Button {
                        onSelect(option.value)
                    } label: {
                        ChipLabel(title: option.label, count: option.count, isSelected: isSelected)
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: isSelected))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("\(prefix)-\(option.value)")
                }
            }
            .padding(.horizontal, Spacing.gutter)
        }
    }

    private func letterStrip(_ model: LibraryActIndexViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(model.letters, id: \.letter) { item in
                    let isSelected = model.query.letter == item.letter
                    let weight: Font.Weight? = isSelected ? Font.Weight.bold : Font.Weight.medium
                    Button {
                        Task { await model.setLetter(item.letter) }
                    } label: {
                        Text(item.letter)
                            .font(.brand(.subheadline, weight: weight))
                            .foregroundStyle(isSelected ? theme.accentText : theme.textPrimary)
                            .frame(minWidth: Layout.touchTarget, minHeight: Layout.touchTarget)
                            .background(isSelected ? theme.accentSoft : theme.surface,
                                        in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(item.count == 0 && !isSelected)
                    .opacity(item.count == 0 && !isSelected ? 0.4 : 1)
                    .accessibilityLabel(item.letter == "#" ? "Numbers and other scripts, \(item.count)" : "\(item.letter), \(item.count)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("library-letter-\(item.letter)")
                }
            }
            .padding(.horizontal, Spacing.gutter)
        }
    }

    private func pager(_ model: LibraryActIndexViewModel, scrollUp: @escaping @MainActor () -> Void) -> some View {
        AdaptiveStack(horizontalAlignment: .center, verticalAlignment: .center, spacing: Spacing.md) {
            Button {
                Task {
                    await model.go(toPage: model.page - 1)
                    scrollUp()
                }
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .buttonStyle(.compactSecondaryAction)
            .disabled(model.page <= 1 || model.isLoading)
            .accessibilityIdentifier("library-page-prev")
            Text(model.pageLabel)
                .font(.brand(.subheadline, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("library-page-label")
            Button {
                Task {
                    await model.go(toPage: model.page + 1)
                    scrollUp()
                }
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .buttonStyle(.compactSecondaryAction)
            .disabled(model.page >= model.pageCount || model.isLoading)
            .accessibilityIdentifier("library-page-next")
        }
        .padding(.horizontal, Spacing.gutter)
    }
}
