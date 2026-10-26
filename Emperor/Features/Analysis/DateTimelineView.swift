import SwiftUI

/// The colour each kind of entry is marked with: rules in the accent, our acts amber, third
/// parties green, the other side red — the web's chart tints.
@MainActor
enum DateChartTone {
    static func color(_ category: DateChart.Category, _ theme: Theme) -> Color {
        switch category {
        case .rules: return theme.accentText
        case .ours: return theme.warning
        case .others: return theme.success
        case .adverse: return theme.danger
        }
    }

    static func symbol(_ category: DateChart.Category) -> String {
        switch category {
        case .rules: return "scalemass"
        case .ours: return "sun.max"
        case .others: return "building.columns"
        case .adverse: return "exclamationmark.triangle"
        }
    }
}

/// The List of Dates' timeline (`ListOfDatesPage.jsx`, `Timeline`): upcoming dates first, then
/// newest first under a heading for each year. Picking one finds it in the chart.
struct DateTimelineView: View {
    let chart: DateChart
    let onPick: (String) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Timeline")
                    .font(.brand(.headline))
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("newest first · pick one to find it in the chart")
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textSecondary)
            }
            AnalysisFlow(spacing: Spacing.sm) {
                ForEach(DateChart.Category.allCases, id: \.self) { category in
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: DateChartTone.symbol(category))
                            .imageScale(.small)
                            .foregroundStyle(DateChartTone.color(category, theme))
                            .accessibilityHidden(true)
                        Text(chart.words(category).label)
                            .font(.brand(.caption))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(chart.timelineItems) { item in
                    if let entry = item.entry {
                        row(entry, next: item.next)
                    } else {
                        Text(item.year ?? "")
                            .font(.brand(.caption, weight: .bold))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 2)
                            .background(theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(theme.borderStrong, lineWidth: 1))
                            .padding(.top, Spacing.sm)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ld-timeline")
    }

    private func row(_ entry: DateChart.Entry, next: Bool) -> some View {
        let words = chart.words(entry.cat)
        let tint = DateChartTone.color(entry.cat, theme)
        return Button {
            onPick(entry.id)
        } label: {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(DateChart.timelineDate(entry, next: next))
                        .font(.brand(.footnote, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(next ? theme.accentText : theme.textPrimary)
                    if next {
                        Text(DateChart.yearOf(entry.day))
                            .font(.brand(.caption2, weight: .semibold))
                            .foregroundStyle(theme.accentText)
                    }
                }
                .frame(minWidth: 64, alignment: .leading)
                Image(systemName: DateChartTone.symbol(entry.cat))
                    .imageScale(.small)
                    .foregroundStyle(next ? theme.onAccent : tint)
                    .frame(width: 24, height: 24)
                    .background(next ? theme.accent : theme.surface2, in: Circle())
                    .overlay(Circle().strokeBorder(tint, lineWidth: 1.5))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.short)
                        .font(.brand(.subheadline, weight: next ? Font.Weight.bold : Font.Weight.medium))
                        .foregroundStyle(next ? theme.accentText : theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(words.label)
                        .font(.brand(.caption))
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Spacing.xs)
            .frame(minHeight: Layout.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(DateChart.fullDate(entry.day)): \(entry.short) (\(words.label)). Show in chart")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("ld-timeline-\(entry.id)")
    }
}
