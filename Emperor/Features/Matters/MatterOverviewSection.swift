import SwiftUI

/// The workspace's Overview — the web's `OverviewSection` read-only: what is left to set up,
/// where things stand, the To do, Fees and Latest order tiles, and the timeline of what has
/// happened, newest first.
struct MatterOverviewSection: View {
    @Environment(\.theme) private var theme

    let model: MatterWorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if model.setupPercent < 100 {
                setup
            }
            if let standing = model.standing {
                standingPanel(standing)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Spacing.md, alignment: .top)],
                      alignment: .leading, spacing: Spacing.md) {
                todoTile
                feesTile
                orderTile
            }
            timeline
        }
    }

    // MARK: - Setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Setting up", detail: "\(model.setupPercent)% done")
            MeterBar(fraction: Double(model.setupPercent) / 100, color: theme.success)
                .accessibilityHidden(true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.sm, alignment: .leading)],
                      alignment: .leading, spacing: Spacing.sm) {
                ForEach(model.setupSteps) { step in
                    StatusPill(
                        text: step.label,
                        tone: step.done == true ? .success : .neutral,
                        systemImage: step.done == true ? "checkmark" : step.done == false ? "circle" : "ellipsis")
                        .accessibilityLabel("\(step.label): \(step.done == true ? "done" : step.done == false ? step.hint : "not known yet")")
                }
            }
        }
        .accessibilityIdentifier("matter-setup")
    }

    // MARK: - Where things stand

    private func standingPanel(_ standing: MatterWorkspaceViewModel.Standing) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Where things stand")
                .recordText(RecordTokens.Typography.label)
                .foregroundStyle(theme.textTertiary)
                .accessibilityAddTraits(.isHeader)
            Text(standing.headline)
                .font(.display(size: 22, relativeTo: .title2))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(standing.detail)
                .font(.brand(.subheadline))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .panel()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("matter-standing")
    }

    // MARK: - Tiles

    private func tile<Content: View>(
        _ title: String, systemImage: String, action: String?, to section: MatterVocabulary.MatterSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            AdaptiveStack(spacing: Spacing.sm) {
                Label(title, systemImage: systemImage)
                    .font(.brand(.subheadline, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if let action {
                    Button(action) { model.section = section }
                        .font(.brand(.footnote, weight: .semibold))
                        .foregroundStyle(theme.accentText)
                        .frame(minWidth: Layout.touchTarget, minHeight: Layout.touchTarget)
                        .accessibilityLabel("\(action): \(section.label)")
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(Spacing.md)
        .panel()
    }

    private var todoTile: some View {
        let todo = model.todo
        return tile("To do", systemImage: "checklist", action: todo.open > 0 ? "All" : nil, to: .tasks) {
            if todo.open == 0 {
                Text("Nothing due")
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textFaint)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text("\(todo.open)")
                        .font(.display(size: 30, relativeTo: .title))
                        .foregroundStyle(theme.textPrimary)
                    Text("open")
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textFaint)
                    Spacer(minLength: 0)
                    if todo.overdue > 0 {
                        StatusPill(text: "\(todo.overdue) late", tone: .danger)
                    }
                }
                .accessibilityElement(children: .combine)
                ForEach(todo.rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(row.title)
                            .font(.brand(.footnote, weight: row.isHigh ? Font.Weight.bold : Font.Weight.medium))
                            .foregroundStyle(theme.textPrimary)
                            .dynamicLineLimit(2)
                        Spacer(minLength: Spacing.xs)
                        Text(row.dueText)
                            .font(.brand(.caption, weight: .semibold))
                            .foregroundStyle(color(row.tone))
                            .fixedSize()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityIdentifier("matter-todo")
    }

    private var feesTile: some View {
        let fees = model.feesSummary
        return tile("Fees", systemImage: "indianrupeesign", action: fees.isEmpty ? nil : "Details", to: .fees) {
            if fees.isEmpty {
                Text("No fees yet")
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textFaint)
            } else {
                if let percent = fees.percent {
                    MeterBar(fraction: Double(percent) / 100, color: theme.success)
                        .accessibilityLabel("\(percent)% of the fee received")
                }
                ValueRow("Paid", value: Ledger.rupees(fees.paid))
                ValueRow("Still due", value: Ledger.rupees(fees.stillDue))
                if fees.billed > 0 { ValueRow("Total fee", value: Ledger.rupees(fees.billed)) }
                if fees.spent > 0 { ValueRow("Spent", value: Ledger.rupees(fees.spent)) }
            }
        }
        .font(.brand(.footnote))
        .accessibilityIdentifier("matter-fees-tile")
    }

    private var orderTile: some View {
        let order = model.latestOrder
        let action: String? = order.map { $0.fromCourt && $0.count > 1 ? "All \($0.count)" : "More" }
        return tile("Latest order", systemImage: "doc.text", action: action,
                    to: order?.fromCourt == false ? .chronology : .court) {
            if let order {
                Text(order.title)
                    .font(.brand(.subheadline, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .dynamicLineLimit(2)
                Text(order.when)
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textTertiary)
            } else {
                Text(model.latestOrderEmpty)
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textFaint)
            }
        }
        .accessibilityIdentifier("matter-order-tile")
    }

    // MARK: - Timeline

    @ViewBuilder
    private var timeline: some View {
        let entries = model.timeline
        let upcoming = model.nextHearing.flatMap { ($0.days ?? -1) >= 0 ? $0 : nil }
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Timeline", detail: entries.isEmpty ? nil : "Newest first")
            if entries.isEmpty, upcoming == nil {
                Text("Nothing here yet. Dates from the court and the ones you add appear here.")
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                RecordGroup {
                    if let upcoming {
                        timelineRow(
                            date: MatterRecord.fmtDay(upcoming.day), title: "Next hearing",
                            detail: Self.away(upcoming.days ?? 0), emphasised: true)
                        if !entries.isEmpty { RecordDivider(inset: 14) }
                    }
                    ForEach(Array(entries.enumerated()), id: \.element.key) { index, entry in
                        if index > 0 { RecordDivider(inset: 14) }
                        let text = MatterWorkspaceViewModel.entryText(entry)
                        let kind = MatterRecord.kindLabel(entry.kind)
                        timelineRow(date: MatterRecord.fmtDay(entry.day), title: text,
                                    detail: text == kind ? "" : kind, emphasised: false)
                    }
                }
            }
        }
        .accessibilityIdentifier("matter-timeline")
    }

    private func timelineRow(date: String, title: String, detail: String, emphasised: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Text(date)
                .font(.brand(.caption, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(emphasised ? theme.accentText : theme.textTertiary)
                .frame(minWidth: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.brand(.subheadline, weight: emphasised ? Font.Weight.semibold : Font.Weight.regular))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.brand(.caption))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private static func away(_ days: Int) -> String {
        days == 0 ? "Today" : days == 1 ? "Tomorrow" : "in \(days) days"
    }

    private func color(_ tone: MatterDates.Tone) -> Color {
        switch tone {
        case .danger: return theme.danger
        case .warn: return theme.warning
        case .mute: return theme.textTertiary
        }
    }
}
