import SwiftUI
import UIKit

/// The List of Dates (`ListOfDatesPage.jsx`, `Result`): a summary strip with the limitation
/// watch, a search and the category chips, then the event chart — one row per year, rules on one
/// side and events on the other — and the timeline. On a phone the chart and the timeline share a
/// switch; on an iPad they sit side by side.
struct DateChartView: View {
    let model: AnalysisRunModel
    let outcome: AnalysisOutcome
    let chart: DateChart
    @Binding var state: DateChartViewState
    @Binding var toast: String?

    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showsTimeline = false
    @State private var showsLimitationNote = false
    @State private var pendingYear: String?
    @State private var highlightedYear: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    AnalysisResultHeader(model: model, outcome: outcome)
                    if chart.entries.isEmpty {
                        Text(DateChart.noDates)
                            .font(.brand(.body))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(Spacing.lg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .panel()
                            .accessibilityIdentifier("ld-no-dates")
                    } else {
                        summaryStrip
                        controls
                        if sizeClass == .regular {
                            HStack(alignment: .top, spacing: Spacing.lg) {
                                eventChart
                                    .frame(maxWidth: .infinity)
                                DateTimelineView(chart: chart) { pick($0) }
                                    .frame(width: 320)
                            }
                        } else {
                            RecordSegmentedControl(
                                label: "Show",
                                options: [(value: false, title: "Chart"), (value: true, title: "Timeline")],
                                selection: $showsTimeline)
                                .accessibilityIdentifier("ld-view-switch")
                            if showsTimeline {
                                DateTimelineView(chart: chart) { pick($0) }
                            } else {
                                eventChart
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.lg)
                .frame(maxWidth: sizeClass == .regular ? 1100 : 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: pendingYear) { _, year in
                guard let year else { return }
                withAnimation(Motion.easeOut(0.3)) { proxy.scrollTo("ld-year-\(year)", anchor: .top) }
                highlightedYear = year
                pendingYear = nil
            }
        }
        .task(id: highlightedYear) {
            guard highlightedYear != nil else { return }
            try? await Task.sleep(for: .milliseconds(1400))
            withAnimation(Motion.easeOut(0.3)) { highlightedYear = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ld-chart")
    }

    /// A timeline pick: shown in the chart, with the chips and search cleared if they hide it.
    private func pick(_ id: String) {
        state.reveal(id, in: chart)
        showsTimeline = false
        pendingYear = DateChartViewState.year(of: id, in: chart)
    }

    // MARK: - Summary

    private var summaryStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            AnalysisFlow(spacing: Spacing.md) {
                fact("\(chart.sum.total)", "events", nil)
                fact("\(chart.sum.rules)", "rules & orders", .rules)
                if let span = chart.spanLine {
                    Text(span)
                        .font(.brand(.subheadline, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                }
                fact("\(chart.sum.ours)", chart.oursLine, .ours)
                fact("\(chart.sum.others)", "third parties", .others)
                fact("\(chart.sum.adverse)", "adverse", .adverse)
            }
            if let limitation = chart.limitation {
                Button {
                    showsLimitationNote.toggle()
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                            Image(systemName: "hourglass")
                                .foregroundStyle(theme.warning)
                                .accessibilityHidden(true)
                            watchLine(limitation)
                                .font(.brand(.footnote))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if showsLimitationNote, !limitation.note.isEmpty {
                            Text(limitation.note)
                                .font(.brand(.footnote))
                                .foregroundStyle(theme.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.warnBg, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint(limitation.note.isEmpty ? "" : "Shows the note")
                .accessibilityIdentifier("ld-limitation")
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func watchLine(_ l: DateChart.Limitation) -> Text {
        let lead: Text = Text("Limitation watch").bold().foregroundStyle(theme.warning)
        let mid: Text = Text(" · \(l.headline) ").foregroundStyle(theme.textPrimary)
        let tail: Text = Text("(check with your advocate)").foregroundStyle(theme.textSecondary)
        return lead + mid + tail
    }

    private func fact(_ value: String, _ label: String, _ category: DateChart.Category?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            if let category {
                Circle()
                    .fill(DateChartTone.color(category, theme))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            Text(value)
                .font(.brand(.subheadline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(theme.textPrimary)
            Text(label)
                .font(.brand(.subheadline))
                .foregroundStyle(theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                RecordSearchField(
                    text: Binding(get: { state.query }, set: { state.query = $0 }),
                    prompt: "Search dates, clauses, events")
                    .accessibilityIdentifier("ld-search")
                Text(state.countLine(chart))
                    .font(.brand(.caption, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize()
                    .accessibilityIdentifier("ld-count")
            }
            AnalysisFlow(spacing: Spacing.xs) {
                chip(nil, title: "All")
                ForEach(DateChart.Category.allCases, id: \.self) { category in
                    chip(category, title: chart.words(category).chip)
                }
                Button {
                    UIPasteboard.general.string = chart.asPlainText(state.shown(chart))
                    toast = "Copied"
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .accessibilityLabel("Copy as text")
                .accessibilityIdentifier("ld-copy")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Show entries by")
        }
    }

    private func chip(_ category: DateChart.Category?, title: String) -> some View {
        let selected = state.category == category
        return Button {
            state.category = category
        } label: {
            ChipLabel(title: title, count: DateChartViewState.count(category, in: chart), isSelected: selected)
        }
        .buttonStyle(ChipButtonStyle(isSelected: selected))
        .accessibilityIdentifier("ld-filter-\(category?.rawValue ?? "all")")
    }

    // MARK: - The event chart

    private var eventChart: some View {
        let shown = state.shown(chart)
        let years = DateChart.byYear(shown)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if !chart.matterLine.isEmpty {
                    Text(chart.matterLine)
                        .font(.brand(.caption))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(chart.title)
                    .font(.brand(.footnote, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            if years.isEmpty {
                Text("Nothing matches “\(state.query)”. Try a different word, or choose All.")
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl)
            }
            ForEach(years) { row in
                yearRow(row)
                    .id("ld-year-\(row.year)")
            }
            keyAndSum
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func yearRow(_ row: DateChart.YearRow) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(row.year)
                .font(.brand(.footnote, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(theme.onInverse)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 3)
                .background(theme.inverse, in: Capsule())
                .accessibilityAddTraits(.isHeader)
            if !row.rules.isEmpty {
                group(chart.words(.rules).who, row.rules)
            }
            if !row.events.isEmpty {
                group("Events (\(chart.eventsHead))", row.events)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            highlightedYear == row.year ? theme.accentSoft : Color.clear,
            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private func group(_ caption: String, _ entries: [DateChart.Entry]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(caption)
                .recordText(RecordTokens.Typography.label)
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(entries) { entry in
                entryRow(entry)
            }
        }
    }

    private func entryRow(_ entry: DateChart.Entry) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            RoundedRectangle(cornerRadius: 2)
                .fill(DateChartTone.color(entry.cat, theme))
                .frame(width: 4)
                .accessibilityHidden(true)
            (Text("\(entry.dateLabel): ").bold() + Self.rich(entry.text))
                .font(.brand(.subheadline))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityValue(chart.words(entry.cat).label)
        .accessibilityIdentifier("ld-entry-\(entry.id)")
    }

    private var keyAndSum: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            AnalysisFlow(spacing: Spacing.md) {
                Text("Key:")
                    .font(.brand(.caption, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                ForEach(DateChart.Category.allCases, id: \.self) { category in
                    HStack(spacing: Spacing.xs) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DateChartTone.color(category, theme))
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(chart.words(category).label)
                            .font(.brand(.caption))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            if !chart.inSum.isEmpty {
                (Text("In sum: ").bold() + Self.rich(chart.inSum))
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ld-in-sum")
            }
        }
        .padding(.top, Spacing.sm)
    }

    /// `**bold**` as bold runs, never as markup.
    static func rich(_ text: String) -> Text {
        DateChart.parseRich(text).reduce(Text("")) { result, run in
            result + (run.bold ? Text(run.text).bold() : Text(run.text))
        }
    }
}
