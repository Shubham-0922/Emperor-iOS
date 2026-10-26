import SwiftUI

/// A collection's filters and sort, from its facets: courts, regulators, kinds and types as
/// chips with their counts, the years as a From/To pair bounded by the collection's range, the
/// A–Z letters, and the sorts the server offers (`FacetChips.jsx`, `CoverGrid.jsx`).
///
/// Every change applies at once; the sheet is a place to choose, not a form to submit.
struct LibraryFilterSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    let model: LibraryCollectionViewModel

    var body: some View {
        VStack(spacing: 0) {
            RecordSheetHeader(
                title: "Filters and sort",
                subtitle: model.countLine.isEmpty ? nil : model.countLine,
                onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    if !model.sortOptions.isEmpty {
                        sortSection
                    }
                    ForEach(model.facetRows, id: \.self) { row in
                        section(row)
                    }
                    if model.activeFilterCount > 0 {
                        Button("Clear filters") { Task { await model.clearFilters() } }
                            .buttonStyle(.secondaryAction)
                            .accessibilityIdentifier("library-filter-clear")
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
            }
        }
        .background(theme.surface)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("library-filter-sheet")
        .task { await model.loadFacets() }
    }

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Sort")
            Picker("Sort", selection: Binding(
                get: { model.sort },
                set: { value in Task { await model.setSort(value) } }
            )) {
                ForEach(model.sortOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .tint(theme.accentText)
            .accessibilityIdentifier("library-filter-sort")
        }
    }

    @ViewBuilder
    private func section(_ row: LibraryCollectionViewModel.FacetRow) -> some View {
        let facets = model.facets
        switch row {
        case .courts:
            if let courts = facets?.courts, !courts.isEmpty {
                chips(row, options: model.courts.map {
                    (value: $0.value, label: LibraryDisplay.courtInfo($0.value, label: $0.label).short, count: $0.count)
                }, selected: model.filters.court) { value in await model.setCourt(value) }
            }
        case .publishers:
            if let list = facets?.publishers, list.count > 1 {
                chips(row, options: list.map { (value: $0.value, label: $0.displayLabel, count: $0.count) },
                      selected: model.filters.publisher) { value in await model.setPublisher(value) }
            }
        case .kinds:
            if let list = facets?.kinds, list.count > 1 {
                chips(row, options: list.map { (value: $0.value, label: $0.displayLabel, count: $0.count) },
                      selected: model.filters.kind) { value in await model.setKind(value) }
            }
        case .years:
            if let range = facets?.yearRange {
                years(range)
            }
        case .letters:
            if let letters = facets?.letters, !letters.isEmpty {
                lettersGrid(letters)
            }
        }
    }

    private func chips(
        _ row: LibraryCollectionViewModel.FacetRow,
        options: [(value: String, label: String, count: Int?)],
        selected: String?,
        apply: @escaping @MainActor (String?) async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: model.rowLabel(row))
            LibraryFlowLayout(spacing: Spacing.sm) {
                chip("All", isSelected: selected == nil, id: "library-filter-\(row.rawValue)-all") {
                    await apply(nil)
                }
                ForEach(options, id: \.value) { option in
                    chip(option.label, count: option.count, isSelected: selected == option.value,
                         id: "library-filter-\(row.rawValue)-\(option.value)") {
                        await apply(selected == option.value ? nil : option.value)
                    }
                }
            }
        }
    }

    private func chip(
        _ title: String, count: Int? = nil, isSelected: Bool, id: String,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            ChipLabel(title: title, count: count, isSelected: isSelected)
        }
        .buttonStyle(ChipButtonStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    /// From and To, bounded by the collection's years; no later than next year, because a year
    /// read from a title is not always one.
    private func years(_ range: LibraryYearRange) -> some View {
        let latest = min(range.max, Calendar(identifier: .gregorian).component(.year, from: Date()) + 1)
        let all = Array(stride(from: latest, through: range.min, by: -1))
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: model.rowLabel(.years))
            AdaptiveStack(spacing: Spacing.md) {
                Picker("From", selection: Binding(
                    get: { model.filters.yearFrom ?? 0 },
                    set: { value in Task { await model.setYears(from: value == 0 ? nil : value, to: model.filters.yearTo) } }
                )) {
                    Text("Any year").tag(0)
                    ForEach(all, id: \.self) { Text(String($0)).tag($0) }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("From year")
                .accessibilityIdentifier("library-filter-year-from")
                Text("to")
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textSecondary)
                    .accessibilityHidden(true)
                Picker("To", selection: Binding(
                    get: { model.filters.yearTo ?? 0 },
                    set: { value in Task { await model.setYears(from: model.filters.yearFrom, to: value == 0 ? nil : value) } }
                )) {
                    Text("Any year").tag(0)
                    ForEach(all, id: \.self) { Text(String($0)).tag($0) }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("To year")
                .accessibilityIdentifier("library-filter-year-to")
            }
            .tint(theme.accentText)
        }
    }

    private func lettersGrid(_ letters: [LibraryLetter]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: model.rowLabel(.letters))
            LibraryLetterGrid(letters: letters, selected: model.filters.letter) { letter in
                Task { await model.setLetter(letter) }
            }
        }
    }
}

/// The A–Z thumb index: a letter with nothing under it cannot be chosen.
struct LibraryLetterGrid: View {
    @Environment(\.theme) private var theme

    let letters: [LibraryLetter]
    let selected: String?
    let onSelect: (String?) -> Void

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 40

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: max(side, Layout.touchTarget)), spacing: Spacing.xs)],
                  spacing: Spacing.xs) {
            ForEach(letters, id: \.letter) { item in
                let isSelected = selected == item.letter
                let weight: Font.Weight? = isSelected ? Font.Weight.bold : Font.Weight.medium
                Button {
                    onSelect(isSelected ? nil : item.letter)
                } label: {
                    Text(item.letter)
                        .font(.brand(.subheadline, weight: weight))
                        .foregroundStyle(isSelected ? theme.accentText : theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: Layout.touchTarget)
                        .background(isSelected ? theme.accentSoft : theme.surface2,
                                    in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(item.count == 0 && !isSelected)
                .opacity(item.count == 0 && !isSelected ? 0.4 : 1)
                .accessibilityLabel(item.letter == "#" ? "Other characters, \(item.count)" : "\(item.letter), \(item.count)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("library-letter-\(item.letter)")
            }
        }
    }
}

/// Chips that wrap onto as many lines as they need.
struct LibraryFlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                y += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
