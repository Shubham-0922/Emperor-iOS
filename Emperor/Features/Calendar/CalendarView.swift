import SwiftUI

/// The Calendar tab: both calendars, behind one switch — **My calendar**, the user's matters day
/// by day with their diary, and **Corporate calendar**, the statutory deadlines
/// (`ComplianceCalendarView`, embedded without its own sheet chrome).
///
/// ## A day
///
/// Selecting a day in the month shows the matters listed on it — from the cause list, topped up
/// from the docket's next hearing dates — **in the order the day will run**: by sitting time,
/// then the listings whose list printed no time, by courtroom and item. Each row is the one Home
/// draws (`CauseListingRow`), led by its time. Tapping one opens that case on the **Matters** tab,
/// on its overview: the case belongs to the docket, and a second copy of its screen inside this
/// tab would be a second place to look for the same matter. The day's diary entries follow as
/// their own section. The rules are `CalendarListings` and `CalendarViewModel`.
///
/// Every date is a day in India (README trap 9); the grid and "today" are pinned to it.
///
/// ## Opened on a day from outside
///
/// A tapped hearing reminder, the Today widget and the app's `emperor://calendar?day=` link all
/// ask `AppNavigator` for a day (`openCalendar(on:)`, which switches to this tab). This takes it
/// the way the Matters tab takes a case — when it appears, or when the request arrives while it
/// is already alive — selects the day, and scrolls
/// back to the month so the day's listings are what is on screen. A request that arrives before
/// the screen has made its model is taken as the model is made, before the first load. A day
/// asked for while Corporate calendar is showing switches back to My calendar first.
///
/// ## Subscribing from the Calendar app
///
/// **Subscribe** opens `CalendarSubscriptionSheet`: the user's private feed link, handed to the
/// iOS Calendar app as `webcal://`, copyable for Google or Outlook, and resettable. It was
/// withheld while the feed could not be issued as a secret the user can revoke; the platform
/// now issues one (`/calendar/feed-url`), with a reset that kills the old link.
///
/// ## What this screen deliberately does not offer
///
/// **No reminder picker.** `remind_days` is written, returned and rendered by the web client —
/// and read by nothing. There is no scheduler, the `reminder` notification type has no
/// producer, and the ICS feed emits no `VALARM` — so a subscribed calendar does not alert
/// either. On the one screen whose purpose is not missing a limitation date, a reminder control
/// would be the worst possible place to make a promise the product cannot keep.
struct CalendarView: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.navigator) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Which of the tab's two calendars is showing.
    enum Scope: Hashable { case mine, corporate }

    @State private var model: CalendarViewModel?
    @State private var scope: Scope = .mine
    @State private var isAddingEvent = false
    @State private var isSubscribing = false
    /// Counts days opened from outside, each of which scrolls back up to the month.
    @State private var openedDays = 0

    /// The month grid's row, which a day opened from outside scrolls to.
    private static let monthRowID = "calendar-month"

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                RecordSegmentedControl(
                    label: "Calendar",
                    options: [(value: Scope.mine, title: "My calendar"),
                              (value: Scope.corporate, title: "Corporate calendar")],
                    selection: $scope)
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.top, Spacing.xs)
                    .padding(.bottom, Spacing.sm)

                if scope == .corporate {
                    ComplianceCalendarView(embedded: true)
                } else if let model {
                    content(model)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Calendar")
            // On the root rather than inside `content`, so subscribing does not wait on — or
            // depend on — the calendar having loaded: the link is a separate request. Leading,
            // because a tab root has no Done to sit there and the trailing side holds "+".
            // Corporate calendar has nothing to subscribe to.
            .toolbar {
                if scope == .mine {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Subscribe") { isSubscribing = true }
                            .accessibilityHint("Adds your hearings and diary to the Calendar app")
                    }
                }
            }
            .sheet(isPresented: $isSubscribing) {
                CalendarSubscriptionSheet()
            }
            .task {
                guard model == nil else { return }
                let created = CalendarViewModel(
                    calendar: session.calendar,
                    caseService: session.cases,
                    cache: session.cache)
                // A day asked for before this screen existed — the tap that launched the app.
                if let day = navigator.takePendingDay() { created.select(day: day) }
                model = created
                await created.load()
            }
        }
        // Both, as the Matters tab does: a tab never shown before is created by the switch the
        // request causes, and one already alive sees the request change instead. The request
        // counter is observed too, so asking for the day already showing is still a change.
        .onAppear { openRequestedDay() }
        .onChange(of: navigator.pendingDay) { _, _ in openRequestedDay() }
        .onChange(of: navigator.calendarRequest) { _, _ in openRequestedDay() }
    }

    /// Selects a day asked for from outside. The request itself is taken whether it carried a
    /// day or not; left waiting until the model exists — the `.task` above takes it then, so
    /// this must not consume the day while the model is still nil.
    /// A day is always a My calendar concern, so Corporate gives the tab back first.
    private func openRequestedDay() {
        _ = navigator.takeCalendarRequest()
        guard let model, let day = navigator.takePendingDay() else { return }
        if scope != .mine {
            withAnimation(Motion.easeOut(Motion.Duration.fade)) { scope = .mine }
        }
        model.select(day: day)
        openedDays += 1
    }

    @ViewBuilder
    private func content(_ model: CalendarViewModel) -> some View {
        ListStateView(presentation: model.presentation, retry: { await model.load() }) {
            ScrollViewReader { proxy in
                List {
                    MonthGrid(
                        state: MonthGridState(
                            month: model.month,
                            selectedDay: model.selectedDay,
                            todayKey: model.todayKey,
                            marks: model.marks,
                            select: { model.select(day: $0) },
                            goToToday: { model.goToToday() },
                            step: { model.step(months: $0) }),
                        legend: [
                            MonthGrid.LegendItem(mark: .listed, text: "Matters listed"),
                            MonthGrid.LegendItem(mark: .diary, text: "Diary"),
                        ],
                        legendSpoken:
                            "A dot marks a day with matters listed; a ring, a day with only diary entries.",
                        rowID: Self.monthRowID)

                    // Read once: it filters the diary for the day.
                    let day = model.selectedCalendarDay
                    listingsSection(day, model)
                    if !day.events.isEmpty {
                        Section {
                            ForEach(day.events) { event in
                                eventRow(event, model)
                            }
                        } header: {
                            SectionHeader(title: "Diary", detail: "\(day.events.count)")
                        }
                        .listRowBackground(theme.surface)
                    }

                    if !model.overdue.isEmpty {
                        Section {
                            ForEach(model.overdue) { event in
                                eventRow(event, model)
                            }
                        } header: {
                            SectionHeader(
                                title: "Past due", detail: "\(model.overdue.count) open")
                        }
                        .listRowBackground(theme.surface)
                    }

                    // The selected day is listed in full directly above, so the agenda leaves it
                    // out rather than printing the same day twice on one screen.
                    ForEach(model.upcoming(excluding: model.selectedDay)) { upcoming in
                        Section {
                            ForEach(upcoming.listings) { listing in
                                listingButton(listing)
                            }
                            ForEach(upcoming.events) { event in
                                eventRow(event, model)
                            }
                        } header: {
                            SectionHeader(title: DisplayText.longDay(upcoming.key))
                        }
                        .listRowBackground(theme.surface)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(theme.groupedBackground)
                .refreshable { await model.load() }
                // A day opened from outside: back up to the month, the day just below it.
                .onChange(of: openedDays) { _, _ in
                    withAnimation(reduceMotion ? nil : Animation.default) {
                        proxy.scrollTo(Self.monthRowID, anchor: .top)
                    }
                }
            }
        } empty: {
            // Should be unreachable: `presentation` reports empty only before the first load
            // returns, and that shows a spinner or a failure instead. Left as something legible
            // rather than an `EmptyView`, so that if the reasoning is ever wrong the screen says
            // what it means — going blank is the bug this grid was built to end.
            EmptyStateView(
                "Nothing scheduled",
                systemImage: "calendar",
                message: "Hearings on your matters, and anything you add here, appear together.")
        }
        // The conversation's measure on an iPad, so the month is a grid the eye takes in at once
        // rather than seven columns spread across the display, and a listing reads as one line.
        .readableColumn()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingEvent = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingEvent) {
            ComplianceEventSheet(day: model.selectedDay) { draft in
                await model.save(draft)
            }
        }
        .alert("Could not save", isPresented: Binding(
            get: { model.writeError != nil },
            set: { if !$0 { model.writeError = nil } }
        )) {
            Button("OK") { model.writeError = nil }
        } message: {
            Text(model.writeError ?? "")
        }
    }

    // MARK: - The selected day

    /// The matters listed on the selected day, in the order it will run — and when there are
    /// none, which kind of nothing it is. The footer says whose cases these are and to confirm
    /// with the court, on every state: an empty day must never read as a free one.
    private func listingsSection(_ day: CalendarDay, _ model: CalendarViewModel) -> some View {
        Section {
            if day.listings.isEmpty {
                Text(model.selectedDayEmptyText)
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textSecondary)
            } else {
                ForEach(day.listings) { listing in
                    listingButton(listing)
                }
            }
        } header: {
            SectionHeader(
                title: DisplayText.longDay(day.key),
                detail: day.listings.isEmpty ? nil : "\(day.listings.count) listed")
        } footer: {
            Text(CalendarViewModel.Copy.listingsFooter)
                .font(.brand(.caption))
                .foregroundStyle(theme.textTertiary)
        }
        .listRowBackground(theme.surface)
    }

    /// A listing, which opens its case on the Matters tab — see the type's documentation for why
    /// it is not pushed here. A button with a chevron rather than a `NavigationLink`, because it
    /// leaves this tab; it still looks like every other row that leads somewhere.
    private func listingButton(_ listing: CauseListing) -> some View {
        Button {
            navigator.openCase(listing.caseID)
        } label: {
            HStack(spacing: Spacing.sm) {
                CauseListingRow(listing: listing, leadsWithTime: true)
                Spacer(minLength: 0)
                RowChevron()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(listing.display.spokenLeadingWithTime(listing))
        .accessibilityHint("Opens the case on the Matters tab")
        .accessibilityIdentifier("calendar-listing-\(listing.caseID)")
    }

    // MARK: - Diary entries

    private func eventRow(_ event: ComplianceEvent, _ model: CalendarViewModel) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Button {
                Task { await model.toggleDone(event) }
            } label: {
                Image(systemName: event.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.brand(.title3))
                    .foregroundStyle(event.isDone ? theme.accentText : theme.textTertiary)
                    // A fingertip's worth, though the mark itself is small.
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(event.isDone ? "Mark not done" : "Mark done")

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "—")
                    .font(.brand(.subheadline, weight: .medium))
                    .strikethrough(event.isDone)
                    .foregroundStyle(event.isDone ? theme.textSecondary : theme.textPrimary)
                    .dynamicLineLimit(2)
                // Kind and date one over the other at the accessibility sizes. Not combined into
                // one element: the tests find an entry by its title's text.
                AdaptiveStack(spacing: 5) {
                    Label(event.kind.label, systemImage: event.kind.systemImage)
                    if let due = event.dayKey {
                        if !dynamicTypeSize.isAccessibilitySize {
                            SeparatorDot()
                        }
                        Text(DisplayText.longDay(due))
                    }
                }
                .font(.brand(.caption2))
                .foregroundStyle(theme.textTertiary)
                if let notes = event.notes, !notes.isEmpty {
                    Text(notes).font(.brand(.caption)).foregroundStyle(theme.textSecondary)
                        .dynamicLineLimit(2)
                }
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                Task { await model.delete(event) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// Creating an obligation.
private struct ComplianceEventSheet: View {
    let day: String
    let onSave: (ComplianceDraft) async -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var kind: ComplianceKind = .task
    @State private var dueDate = Date()
    @State private var notes = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What is due", text: $title)
                    Picker("Type", selection: $kind) {
                        ForEach(ComplianceKind.selectable, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                } footer: {
                    // Said out loud rather than silently omitting the control: a practitioner
                    // who expects a reminder and does not get one is worse off than one who
                    // knows to set their own.
                    Text("Emperor does not send reminders for diary entries yet. Set your own alert if this date matters.")
                        .font(.brand(.caption))
                        .foregroundStyle(theme.textSecondary)
                }
                .listRowBackground(theme.surface)
            }
            .font(.brand(.body))
            .scrollContentBackground(.hidden)
            .background(theme.groupedBackground)
            .navigationTitle("Add to diary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            await onSave(ComplianceDraft(
                                id: nil,
                                title: title,
                                kind: kind,
                                dueDate: dueDate,
                                notes: notes.isEmpty ? nil : notes,
                                caseID: nil))
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let parsed = WireDate.parseDay(day) { dueDate = parsed }
            }
        }
    }
}
