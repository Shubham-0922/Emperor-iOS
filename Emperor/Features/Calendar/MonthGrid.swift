import SwiftUI

/// What the month grid reads from — and writes back to — the calendar that owns it.
///
/// A value with three callbacks rather than a protocol: the grid is stateless, the screen's view
/// model holds every fact, and this is rebuilt each render. `todayKey` is a day in India
/// (`WireDate.dayKey`), never the device zone.
struct MonthGridState {
    /// The month being shown — whichever one holds `selectedDay`.
    let month: CalendarMonth?
    let selectedDay: String
    let todayKey: String
    /// Each marked cell's mark, keyed by `YYYY-MM-DD`.
    let marks: [String: CalendarDayMark]

    let select: (String) -> Void
    let goToToday: () -> Void
    let step: (Int) -> Void

    var isShowingToday: Bool { selectedDay == todayKey }
}

/// The month as a grid of whole weeks, with a mark on every day that has something on it —
/// shared by **My calendar** (`CalendarView`) and the **Corporate calendar**
/// (`ComplianceCalendarView`), so both screens draw one calendar the same way.
///
/// A mark rather than a count: the grid answers "which days", and the section beneath it answers
/// "what". A number in a cell this size is unreadable and, at a glance, is easily taken for the
/// date. Two shapes rather than two colours, so the difference does not depend on seeing colour.
struct MonthGrid: View {
    /// One line of the legend: the mark and the words beside it.
    struct LegendItem {
        let mark: CalendarDayMark
        let text: String
    }

    @Environment(\.theme) private var theme
    /// The month steps, scaled with the heading they sit beside.
    @ScaledMetric(relativeTo: .footnote) private var stepSide: CGFloat = 32

    let state: MonthGridState
    let legend: [LegendItem]
    /// The legend as a single sentence for VoiceOver, which also hears each day's own mark.
    let legendSpoken: String
    /// The row's identity, for a screen that scrolls back to the month (My calendar, when a day
    /// is opened from outside).
    var rowID: String?

    var body: some View {
        grid
    }

    @ViewBuilder
    private var grid: some View {
        let section = Section {
            VStack(spacing: Spacing.xs) {
                weekdayRow
                weeks
                legendRow
            }
            .padding(.vertical, Spacing.xxs)
            .listRowInsets(EdgeInsets(top: 12, leading: 10, bottom: 10, trailing: 10))
        } header: {
            monthHeader
        }
        .listRowBackground(theme.surface)
        if let rowID {
            section.id(rowID)
        } else {
            section
        }
    }

    // MARK: - The grid

    private var weekdayRow: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(Array(CalendarMonth.weekdayInitials.enumerated()), id: \.offset) {
                _, initial in
                Text(initial)
                    .font(.brand(.caption2, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, Spacing.xxs)
        // One element for the row, saying what it is — each day cell already names its
        // own weekday, so seven single letters read aloud would only be noise; but text
        // on screen with nothing behind it reads to the audit as text VoiceOver cannot
        // reach.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sunday to Saturday")
        // Text, not a control: without the trait an element built from children is judged
        // as one, and its 14-point height as a target too small to hit.
        .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder
    private var weeks: some View {
        if let month = state.month {
            // Keyed by position: a week has no identity of its own, and the days inside
            // it carry real dates that do.
            ForEach(Array(month.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: Spacing.xs) {
                    ForEach(week) { day in
                        dayCell(day, mark: state.marks[day.key] ?? CalendarDayMark.clear)
                    }
                }
            }
        }
    }

    /// What the marks mean — said once, as a sentence, to VoiceOver, which also hears each
    /// day's own mark as words.
    private var legendRow: some View {
        HStack(spacing: 14) {
            ForEach(Array(legend.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    marker(item.mark, isSelected: false)
                    Text(item.text)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.brand(.caption2))
        .foregroundStyle(theme.textTertiary)
        .padding(.top, Spacing.sm)
        .padding(.leading, Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(legendSpoken)
        // Text, not a control — see the weekday row above.
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: - The month's name and its controls

    /// The month's name, as the heading of its own card, with the way back to today and the
    /// two steps beside it — round, as Home's day steps are.
    private var monthHeader: some View {
        // The month over its controls at the accessibility sizes, where beside them its name
        // would be cut to a word.
        AdaptiveStack(spacing: Spacing.sm) {
            Text(state.month?.title ?? "")
                .font(.brand(.headline, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.sm)
            HStack(spacing: Spacing.sm) {
                // Only once there is somewhere to come back from. The capsule inside the label,
                // with a 44-point frame round it, so all of it takes the tap — not the word alone.
                if !state.isShowingToday {
                    Button {
                        state.goToToday()
                        VoiceOver.announce(state.month?.title ?? "")
                    } label: {
                        Text("Today")
                            .font(.brand(.caption, weight: .semibold))
                            .foregroundStyle(theme.accentText)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 6)
                            .background(theme.accentWash, in: Capsule())
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                monthStep("chevron.left", label: "Previous month") { change(by: -1) }
                monthStep("chevron.right", label: "Next month") { change(by: 1) }
            }
        }
        .textCase(nil)
        .padding(.bottom, Spacing.xs)
    }

    private func monthStep(
        _ systemImage: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.brand(.footnote, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .frame(width: min(stepSide, 48), height: min(stepSide, 48))
                .background(theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(theme.separator, lineWidth: 1))
                // The circle is drawn at its size; the target is at least 44 points.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// The month changes above the control VoiceOver is on, so its name is said as well.
    private func change(by months: Int) {
        state.step(months)
        VoiceOver.announce(state.month?.title ?? "")
    }

    // MARK: - One day

    private func dayCell(_ day: CalendarMonth.Day, mark: CalendarDayMark) -> some View {
        let isSelected = day.key == state.selectedDay
        let isToday = day.key == state.todayKey
        // Spelled out rather than implicit members either side of the ternary: `brand(_:weight:)`
        // takes an `Optional`, which is the shape `-parse` accepts and the type checker rejects.
        let weight: Font.Weight? = isToday ? Font.Weight.bold : Font.Weight.regular
        let foreground: Color =
            isSelected ? theme.onAccent : (day.isInMonth ? theme.textPrimary : theme.textTertiary)

        return Button {
            state.select(day.key)
        } label: {
            VStack(spacing: 3) {
                Text("\(day.number)")
                    .font(.brand(.subheadline, weight: weight).monospacedDigit())
                marker(mark, isSelected: isSelected)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                isSelected ? theme.accent : Color.clear,
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(
                        isToday && !isSelected ? theme.accentText : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Today is ringed for the eye; to VoiceOver it is said.
        .accessibilityLabel(
            isToday ? "Today, \(DisplayText.longDay(day.key))" : DisplayText.longDay(day.key))
        .accessibilityValue(mark.spoken)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A filled dot for a marked day, nothing for a clear one — at a fixed size, so every cell
    /// is the same height whatever is on it. (My calendar uses the ring for a diary-only day;
    /// a statutory deadline and a listed matter both read as a dot, told apart by the legend.)
    @ViewBuilder
    private func marker(_ mark: CalendarDayMark, isSelected: Bool) -> some View {
        switch mark {
        case .listed, .deadline:
            Circle()
                .fill(isSelected ? theme.onAccent : theme.accent)
                .frame(width: 6, height: 6)
        case .diary:
            Circle()
                .strokeBorder(isSelected ? theme.onAccent : theme.textTertiary, lineWidth: 1)
                .frame(width: 6, height: 6)
        case .clear:
            Color.clear
                .frame(width: 6, height: 6)
        }
    }
}
