import SwiftUI

/// The Doc Index (`DocIndexPage.jsx`, `Result`): a table whose columns the AI chose. A summary
/// strip, the columns it chose and why, a search over every column, the filter chips, sort,
/// column and density menus, then the rows — cards on a phone, a table on an iPad — each opening
/// its full detail.
struct DocIndexView: View {
    let model: AnalysisRunModel
    let outcome: AnalysisOutcome
    let index: DocIndex
    @Binding var state: DocIndexViewState

    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var detail: DocIndex.Row?

    var body: some View {
        let rows = state.rows(index)
        let columns = state.columns(index)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                AnalysisResultHeader(model: model, outcome: outcome)
                strip
                controls
                if rows.isEmpty {
                    emptyTable
                } else if sizeClass == .regular {
                    table(rows: rows, columns: columns)
                } else {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(rows) { row in
                            card(row)
                        }
                    }
                }
                footer(rows: rows)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.lg)
            .frame(maxWidth: sizeClass == .regular ? 1100 : 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $detail) { row in
            DocIndexDetailSheet(index: index, row: row)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("di-table")
    }

    // MARK: - Summary

    private var strip: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            AnalysisFlow(spacing: Spacing.lg) {
                stat("\(index.rows.count)", "documents")
                if let pages = index.allPages {
                    stat(AnalysisJS.string(pages), "pages in all")
                }
                if let flagged = index.flaggedCount, let flag = index.flag {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        stat("\(flagged)", flag.label ?? "")
                        if flagged > 0 {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(theme.warning)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            Text("Columns chosen by the AI for this bundle:")
                .font(.brand(.footnote, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            AnalysisFlow(spacing: Spacing.xs) {
                ForEach(index.columns) { column in
                    StatusPill(text: column.label, tone: .neutral)
                        .accessibilityHint(column.description)
                }
            }
            if !index.rationale.isEmpty {
                Text(index.rationale)
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let focus = AnalysisJS.trim(outcome.reference)
            if !focus.isEmpty {
                Text("Focus you asked for: “\(AnalysisJS.prefix(focus, 140))”")
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(value)
                .font(.display(size: 22, relativeTo: .title2))
                .monospacedDigit()
                .foregroundStyle(theme.textPrimary)
            Text(label)
                .font(.brand(.footnote))
                .foregroundStyle(theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            RecordSearchField(
                text: Binding(get: { state.query }, set: { state.query = $0 }),
                prompt: "Search every column")
                .accessibilityIdentifier("di-search")
            let counts = index.filterCounts
            if !counts.isEmpty {
                AnalysisFlow(spacing: Spacing.xs) {
                    Text(index.filterLabel)
                        .font(.brand(.footnote, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(minHeight: Layout.touchTarget)
                    Button {
                        state.toggleFilter(nil)
                    } label: {
                        ChipLabel(title: "All", count: index.rows.count, isSelected: state.filter == nil)
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: state.filter == nil))
                    .accessibilityIdentifier("di-filter-all")
                    ForEach(counts, id: \.value) { item in
                        Button {
                            state.toggleFilter(item.value)
                        } label: {
                            ChipLabel(title: item.value, count: item.count, isSelected: state.filter == item.value)
                        }
                        .buttonStyle(ChipButtonStyle(isSelected: state.filter == item.value))
                        .accessibilityIdentifier("di-filter-\(item.value)")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Filter by \(index.filterLabel.lowercased())")
            }
            AnalysisFlow(spacing: Spacing.sm) {
                sortMenu
                columnsMenu
                densityMenu
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Button {
                state.sort(nil, descending: false)
            } label: {
                if state.sortKey == nil { Label("No sort", systemImage: "checkmark") } else { Text("No sort") }
            }
            ForEach(index.columns) { column in
                Menu(column.label) {
                    Button {
                        state.sort(column.key, descending: false)
                    } label: {
                        if state.sortKey == column.key, !state.descending {
                            Label("Ascending", systemImage: "checkmark")
                        } else {
                            Text("Ascending")
                        }
                    }
                    Button {
                        state.sort(column.key, descending: true)
                    } label: {
                        if state.sortKey == column.key, state.descending {
                            Label("Descending", systemImage: "checkmark")
                        } else {
                            Text("Descending")
                        }
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .buttonStyle(SecondaryButtonStyle(compact: true))
        .accessibilityIdentifier("di-sort")
    }

    private var columnsMenu: some View {
        Menu {
            ForEach(index.columns) { column in
                Button {
                    state.toggleColumn(column.key, in: index)
                } label: {
                    if state.hidden.contains(column.key) {
                        Text(column.label)
                    } else {
                        Label(column.label, systemImage: "checkmark")
                    }
                }
            }
            if !state.hidden.isEmpty {
                Divider()
                Button("Show all columns") { state.hidden = [] }
            }
        } label: {
            Label("Columns \(index.columns.count - state.hidden.count)/\(index.columns.count)", systemImage: "rectangle.split.3x1")
        }
        .buttonStyle(SecondaryButtonStyle(compact: true))
        .accessibilityIdentifier("di-columns")
    }

    private var densityMenu: some View {
        Menu {
            Button {
                state.compact = false
            } label: {
                if state.compact { Text("Comfortable") } else { Label("Comfortable", systemImage: "checkmark") }
            }
            Button {
                state.compact = true
            } label: {
                if state.compact { Label("Compact", systemImage: "checkmark") } else { Text("Compact") }
            }
        } label: {
            Label(state.compact ? "Compact" : "Comfortable", systemImage: "line.3.horizontal")
        }
        .buttonStyle(SecondaryButtonStyle(compact: true))
        .accessibilityIdentifier("di-density")
    }

    // MARK: - Cards (compact width)

    private func card(_ row: DocIndex.Row) -> some View {
        let strong = index.strongColumn
        let visible = state.columns(index)
        let badges = visible.filter { $0.type == .badge && $0.key != strong.key && row[$0.key] != nil }
        let facts = visible
            .filter { ![DocIndex.ColumnType.badge, .long, .tags].contains($0.type) && $0.key != strong.key && row[$0.key] != nil }
            .prefix(state.compact ? 1 : 3)
        let flagged = index.isFlagged(row)
        return Button {
            detail = row
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(DocIndex.cellText(strong, row).isEmpty ? "—" : DocIndex.cellText(strong, row))
                        .font(.brand(.body, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if flagged {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(theme.warning)
                            .accessibilityLabel(index.flag?.label ?? "Flagged")
                    }
                }
                if !badges.isEmpty {
                    AnalysisFlow(spacing: Spacing.xs) {
                        ForEach(badges) { column in
                            badge(column, row)
                        }
                    }
                }
                ForEach(Array(facts)) { column in
                    ValueRow(column.label, value: DocIndex.cellText(column, row))
                        .font(.brand(.footnote))
                }
            }
            .padding(state.compact ? Spacing.md : Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("di-row-\(row.id)")
    }

    private func badge(_ column: DocIndex.Column, _ row: DocIndex.Row) -> some View {
        let value = DocIndex.cellText(column, row)
        return StatusPill(text: value, tone: Self.tone(DocIndex.tone(column, value)))
            .accessibilityLabel("\(column.label): \(value)")
    }

    static func tone(_ name: String) -> StatusPill.Tone {
        switch name {
        case "accent": return .accent
        case "info": return .info
        case "ok", "success": return .success
        case "warn", "warning": return .warning
        case "danger": return .danger
        default: return .neutral
        }
    }

    // MARK: - Table (regular width)

    private func table(rows: [DocIndex.Row], columns: [DocIndex.Column]) -> some View {
        ScrollView(.horizontal) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                        Button {
                            detail = row
                        } label: {
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(columns) { column in
                                    tableCell(column, row)
                                        .frame(width: column.width, alignment: column.type.isNumeric ? .trailing : .leading)
                                }
                            }
                            .padding(.vertical, state.compact ? 6 : 12)
                            .background(offset % 2 == 1 ? theme.surface2 : theme.surface)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("di-row-\(row.id)")
                    }
                } header: {
                    HStack(spacing: 0) {
                        ForEach(columns) { column in
                            Button {
                                state.toggleSort(column.key)
                            } label: {
                                HStack(spacing: Spacing.xs) {
                                    Text(column.label)
                                        .recordText(RecordTokens.Typography.label)
                                        .foregroundStyle(theme.textTertiary)
                                        .multilineTextAlignment(.leading)
                                    Image(systemName: sortSymbol(column))
                                        .imageScale(.small)
                                        .foregroundStyle(theme.textTertiary)
                                        .accessibilityHidden(true)
                                }
                                .padding(.horizontal, Spacing.md)
                                .frame(width: column.width, alignment: column.type.isNumeric ? .trailing : .leading)
                                .frame(minHeight: Layout.touchTarget)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Sort by \(column.label)")
                            .accessibilityValue(sortValue(column))
                            .accessibilityHint(column.description)
                        }
                    }
                    .background(theme.surface2)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(theme.separator, lineWidth: 1))
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func sortSymbol(_ column: DocIndex.Column) -> String {
        guard state.sortKey == column.key else { return "chevron.up.chevron.down" }
        return state.descending ? "chevron.down" : "chevron.up"
    }

    private func sortValue(_ column: DocIndex.Column) -> String {
        guard state.sortKey == column.key else { return "Not sorted" }
        return state.descending ? "High to low" : "Low to high"
    }

    @ViewBuilder
    private func tableCell(_ column: DocIndex.Column, _ row: DocIndex.Row) -> some View {
        Group {
            if row[column.key] == nil {
                Text("—")
                    .foregroundStyle(theme.textTertiary)
                    .accessibilityLabel("nothing")
            } else if column.type == .badge {
                badge(column, row)
            } else {
                let weight: Font.Weight? = column.strong ? Font.Weight.semibold : nil
                Text(DocIndex.cellText(column, row))
                    .font(.brand(.subheadline, weight: weight))
                    .foregroundStyle(column.strong || column.type == .amount ? theme.textPrimary : theme.textSecondary)
                    .monospacedDigit()
                    .dynamicLineLimit(state.compact ? 1 : 3)
                    .multilineTextAlignment(column.type.isNumeric ? .trailing : .leading)
            }
        }
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Empty and footer

    private var emptyTable: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(theme.textTertiary)
                .accessibilityHidden(true)
            Text(index.emptyTitle(query: state.query))
                .font(.brand(.headline))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
            if !index.rows.isEmpty {
                Text(DocIndex.emptyHint)
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Clear search and filters") { state.clearSearchAndFilters() }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
        .panel()
        .accessibilityIdentifier("di-empty")
    }

    private func footer(rows: [DocIndex.Row]) -> some View {
        let totals = index.totals(shown: rows, hidden: state.hidden).map { DocIndex.totalText($0.column, $0.sum) }
        let sortColumn = index.columns.first { $0.key == state.sortKey }
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(([state.showingLine(index)] + totals).joined(separator: " · "))
                .font(.brand(.footnote, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("di-showing")
            Text(DocIndex.sortLine(sortColumn, descending: state.descending))
                .font(.brand(.footnote))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if state.isFiltered, !rows.isEmpty {
                Button("Clear filters") { state.clearSearchAndFilters() }
                    .buttonStyle(QuietButtonStyle())
                    .padding(.leading, -Spacing.md)
            }
        }
    }
}

/// Lays its views out in lines, wrapping to the next line when one is full — chips, badges,
/// figures.
struct AnalysisFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            let w = min(size.width, width)
            if x > 0, x + w > width {
                y += line + spacing
                x = 0
                line = 0
            }
            x += w + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: width.isFinite ? width : widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            let w = min(size.width, width)
            if x > 0, x + w > width {
                y += line + spacing
                x = 0
                line = 0
            }
            view.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading,
                proposal: ProposedViewSize(width: w, height: size.height))
            x += w + spacing
            line = max(line, size.height)
        }
    }
}
