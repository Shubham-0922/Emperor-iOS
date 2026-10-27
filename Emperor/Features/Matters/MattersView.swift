import SwiftUI

/// The Matters tab: the next sitting, what is upcoming, and every matter.
///
/// The first two are the cause list (`MattersOverview`), each hearing led by its item number in
/// the serif and opening its sheet — the web's Cause list column. The third is the web's Matters
/// column: the user's matters (`MattersListViewModel`, each opening its workspace), then the
/// tracked cases no matter holds (`CaseListViewModel`, with its own sort and filters, each pushing
/// its case page). One search field narrows both; New matter makes a matter, and a row's context
/// menu edits, archives or deletes it. `+` adds a matter through the court lookup, and
/// the Calendar button in the bar switches to the Calendar tab. Pull to refresh checks
/// the cause lists again, and says so when it is done.
///
/// - Important: what is listed here is the user's own matters by hearing date, not the court's
///   published list. Every empty state ends with `CauseListViewModel.Copy.confirmWithCourt`.
struct MattersView: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.navigator) private var navigator
    @Environment(\.horizontalSizeClass) private var sizeClass

    enum Segment: Hashable { case next, upcoming, all }

    @State private var path: [MattersRoute] = []
    @State private var causeList: CauseListViewModel?
    @State private var cases: CaseListViewModel?
    @State private var matters: MattersListViewModel?
    @State private var segment: Segment = .next
    @State private var openHearing: CauseListing?
    @State private var isAddingMatter = false
    @State private var isArranging = false
    @State private var toast: String?
    @State private var matterSheet: MatterListSheet?
    /// A matter made in the New matter sheet, opened once the sheet has gone.
    @State private var createdMatter: String?
    @State private var matterFailure: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let overview {
                        Text(overview.subtitle(trackedMatters: cases.map { $0.cases.count }))
                            .font(.brand(.subheadline))
                            .foregroundStyle(theme.textFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    RecordSegmentedControl(
                        label: "Show",
                        options: [
                            (value: Segment.next, title: nextLabel),
                            (value: Segment.upcoming, title: "Upcoming"),
                            (value: Segment.all, title: "All matters"),
                        ],
                        selection: $segment)
                        .padding(.top, Spacing.lg)

                    if let failure = causeList?.state.failure, segment != .all {
                        refreshFailed(failure)
                            .padding(.top, Spacing.md)
                    }

                    Group {
                        switch segment {
                        case .next: nextSittingList
                        case .upcoming: upcomingList
                        case .all: allMattersList
                        }
                    }
                    .padding(.top, 14)

                    if segment != .all {
                        Text("Court and item numbers come from the published cause list, for your own matters. \(CauseListViewModel.Copy.confirmWithCourt)")
                            .font(.brand(size: 12.5, relativeTo: .caption))
                            .foregroundStyle(theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Spacing.md)
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, Spacing.xxxl)
                .frame(maxWidth: ReadableWidth.cap(for: sizeClass))
                .frame(maxWidth: .infinity)
            }
            .refreshable { await refresh() }
            .background(theme.canvas)
            .navigationTitle("Matters")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbar }
            .navigationDestination(for: MattersRoute.self) { route in
                switch route {
                case .legalCase(let caseRoute):
                    CaseDetailView(caseID: caseRoute.caseID)
                        .toolbar(.hidden, for: .tabBar)
                case .matter(let matterRoute):
                    MatterWorkspaceView(
                        route: matterRoute,
                        fileCount: matters?.projects.first(where: { $0.id == matterRoute.projectID })?.fileCount,
                        onOpenCase: { path.append(.legalCase(CaseRoute(caseID: $0))) },
                        onChanged: { message in
                            if let message { toast = message }
                            reloadMatters()
                        })
                        .toolbar(.hidden, for: .tabBar)
                case .matterChat(let chat):
                    // A matter's conversation: every turn carries the matter, and it is not
                    // listed in History.
                    ChatThreadView(chatID: chat.chatID, projectID: chat.projectID)
                        .toolbar(.hidden, for: .tabBar)
                }
            }
            .sheet(item: $openHearing) { listing in
                HearingSheet(
                    listing: listing,
                    allListings: causeList?.listings ?? [],
                    onOpenMatter: { path = [.legalCase(CaseRoute(caseID: $0))] },
                    onAsk: { navigator.ask($0) })
            }
            .sheet(isPresented: $isAddingMatter) {
                CourtSearchView {
                    let cases = self.cases
                    Task { await cases?.load() }
                }
                .pageSizedSheet()
            }
            .sheet(item: $matterSheet, onDismiss: { openCreatedMatter() }) { which in
                matterSheetView(which)
            }
            .alert("That did not go through", isPresented: Binding(
                get: { matterFailure != nil }, set: { if !$0 { matterFailure = nil } })) {
                Button("OK", role: .cancel) { matterFailure = nil }
            } message: {
                Text(matterFailure ?? "")
            }
            .sheet(isPresented: $isArranging) {
                if let cases {
                    CaseArrangementSheet(model: cases)
                        .pageSizedSheet()
                }
            }
        }
        .recordToast($toast)
        .task { await loadOnce() }
        // A matter or a docket reload asked for from elsewhere. Both, because either can be
        // first: a tab never shown before is created by the switch the request causes.
        .onAppear {
            openRequestedCase()
            openRequestedMatter()
            openRequestedDocketRefresh()
        }
        .onChange(of: navigator.pendingCase) { _, _ in
            openRequestedCase()
        }
        .onChange(of: navigator.pendingMatter) { _, _ in
            openRequestedMatter()
        }
        .onChange(of: navigator.docketRefreshRequest) { _, _ in openRequestedDocketRefresh() }
    }

    private var overview: MattersOverview? {
        causeList.map { MattersOverview(listings: $0.listings, todayKey: $0.todayKey) }
    }

    /// The first segment is named for its day: "Today", "Mon 12 Oct".
    private var nextLabel: String {
        guard let overview, let day = overview.nextSitting else { return "Next sitting" }
        return overview.dayLabel(day.key)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                navigator.selectedTab = .calendar
            } label: {
                Image(systemName: "calendar")
            }
            .accessibilityLabel("Calendar")
            .accessibilityHint("Your hearings day by day, and your diary")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if segment == .all, let cases {
                Button {
                    isArranging = true
                } label: {
                    Image(systemName: cases.filters.isEmpty
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel(CaseListViewModel.Copy.arrange)
                .accessibilityValue(cases.filterSummary)
            }
            Button {
                isAddingMatter = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add a matter")
            .accessibilityHint("Finds a case at its court and adds it to your matters")
        }
    }

    // MARK: - Next sitting

    @ViewBuilder
    private var nextSittingList: some View {
        if let overview, let day = overview.nextSitting {
            hearingGroup(day.listings)
        } else if causeList?.listings.isEmpty ?? true, causeList?.state.isLoading ?? true {
            loading
        } else {
            EmptyStateContent(
                title: causeList?.hasAnyListings == true ? "Nothing listed ahead" : CauseListViewModel.Copy.nothingAtAll,
                systemImage: "calendar.badge.checkmark",
                message: causeList?.hasAnyListings == true
                    ? "None of your matters has a hearing coming up. \(CauseListViewModel.Copy.confirmWithCourt)"
                    : "\(CauseListViewModel.Copy.nothingAtAllDetail) \(CauseListViewModel.Copy.confirmWithCourt)"
            ) {
                Button {
                    isAddingMatter = true
                } label: {
                    Label("Add a matter", systemImage: "plus")
                }
                .buttonStyle(.primaryAction)
            }
        }
    }

    private func hearingGroup(_ listings: [CauseListing]) -> some View {
        RecordGroup {
            ForEach(Array(listings.enumerated()), id: \.element.id) { index, listing in
                if index > 0 { RecordDivider(inset: 0) }
                Button {
                    openHearing = listing
                } label: {
                    HearingRow(listing: listing)
                }
                .buttonStyle(.recordRow)
                .accessibilityHint("Shows the hearing")
            }
        }
    }

    // MARK: - Upcoming

    @ViewBuilder
    private var upcomingList: some View {
        if let overview, !overview.upcoming.isEmpty {
            RecordGroup {
                ForEach(Array(allUpcoming(overview).enumerated()), id: \.offset) { index, entry in
                    if index > 0 { RecordDivider(inset: 0) }
                    Button {
                        openHearing = entry.listing
                    } label: {
                        UpcomingRow(dayKey: entry.day, listing: entry.listing)
                    }
                    .buttonStyle(.recordRow)
                }
            }
        } else if causeList?.listings.isEmpty ?? true, causeList?.state.isLoading ?? true {
            loading
        } else {
            EmptyStateContent(
                title: "Nothing further listed",
                systemImage: "calendar",
                message: "Nothing of yours is listed after the next sitting. \(CauseListViewModel.Copy.confirmWithCourt)"
            ) {
                Button("Open the Calendar") { navigator.selectedTab = .calendar }
                    .buttonStyle(.secondaryAction)
            }
        }
    }

    private func allUpcoming(_ overview: MattersOverview) -> [(day: String, listing: CauseListing)] {
        overview.upcoming.flatMap { day in day.listings.map { (day: day.key, listing: $0) } }
    }

    // MARK: - All matters

    @ViewBuilder
    private var allMattersList: some View {
        if let cases {
            let hasMatters = !(matters?.projects.isEmpty ?? true)
            VStack(alignment: .leading, spacing: Spacing.md) {
                // One query for both lists: the matters and the tracked cases under them.
                RecordSearchField(
                    text: Binding(
                        get: { cases.query },
                        set: { query in
                            cases.query = query
                            matters?.query = query
                        }),
                    prompt: CaseListViewModel.Copy.searchPrompt)

                if let matters {
                    MattersSectionList(
                        model: matters,
                        onOpen: { project in path.append(.matter(MatterRoute(projectID: project.id))) },
                        onNew: { matterSheet = .new },
                        onAction: { project, action in rowAction(project, action) })
                }

                if hasMatters {
                    RecordSectionLabel(title: "Tracked cases")
                        .padding(.top, -Spacing.md)
                }

                if !cases.filterChips.isEmpty {
                    FilterChipBar(
                        chips: cases.filterChips,
                        remove: { cases.remove($0) },
                        clearAll: { cases.clearFilters() })
                }

                if cases.cases.isEmpty, cases.state.isLoading {
                    loading
                } else if cases.docketCases.isEmpty, hasMatters {
                    Text(cases.cases.isEmpty ? "No tracked cases yet. Add a matter to follow a case from the court." : "Every case you track is filed under one of your matters.")
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if cases.docketCases.isEmpty {
                    EmptyStateContent(
                        title: CaseListViewModel.Copy.noMattersTitle,
                        systemImage: "briefcase",
                        message: CaseListViewModel.Copy.noMattersMessage
                    ) {
                        Button {
                            isAddingMatter = true
                        } label: {
                            Label("Add a matter", systemImage: "plus")
                        }
                        .buttonStyle(.primaryAction)
                        Button {
                            matterSheet = .new
                        } label: {
                            Label("New matter", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.secondaryAction)
                    }
                } else if let noMatches = cases.noMatches {
                    EmptyStateContent(
                        title: noMatches.title,
                        systemImage: "line.3.horizontal.decrease.circle",
                        message: noMatches.message
                    ) {
                        Button(noMatches.action) { cases.clearSearchAndFilters() }
                            .buttonStyle(.secondaryAction)
                    }
                } else {
                    ForEach(cases.groups) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            RecordSectionLabel(title: "\(group.title) · \(group.cases.count)")
                                .padding(.top, -Spacing.sm)
                            RecordGroup {
                                ForEach(Array(group.cases.enumerated()), id: \.element.id) { index, legalCase in
                                    if index > 0 { RecordDivider() }
                                    Button {
                                        path.append(.legalCase(CaseRoute(caseID: legalCase.id)))
                                    } label: {
                                        DocketRow(legalCase: legalCase)
                                    }
                                    .buttonStyle(.recordRow)
                                    .accessibilityIdentifier("case-row-\(legalCase.id)")
                                }
                            }
                        }
                    }
                }
            }
        } else {
            loading
        }
    }

    // MARK: - Writing matters

    @ViewBuilder
    private func matterSheetView(_ which: MatterListSheet) -> some View {
        switch which {
        case .new:
            NewMatterSheet(existing: matters?.projects ?? []) { id, existed in
                toast = NewMatterViewModel.createdMessage(existed: existed)
                createdMatter = id
                reloadMatters()
            }
        case .edit(let project):
            MatterDetailsSheet(project: project) { message in
                toast = message
                reloadMatters()
            }
            .pageSizedSheet()
        case .delete(let project):
            DeleteMatterSheet(project: project) { message in
                toast = message
                reloadMatters()
            }
        }
    }

    private func rowAction(_ project: Project, _ action: MattersSectionList.RowAction) {
        switch action {
        case .edit: matterSheet = .edit(project)
        case .delete: matterSheet = .delete(project)
        case .archive:
            let quick = MatterQuickActions(projectID: project.id, writes: session.projectWrites)
            let archiving = !project.isArchived
            Task {
                if await quick.setArchived(archiving) {
                    toast = archiving ? "Matter archived" : "Matter restored to active"
                    reloadMatters()
                } else if let error = quick.error {
                    matterFailure = error
                }
            }
        }
    }

    /// The matter just made, opened over All matters once its sheet has gone.
    private func openCreatedMatter() {
        guard let id = createdMatter else { return }
        createdMatter = nil
        segment = .all
        path = [.matter(MatterRoute(projectID: id))]
    }

    private func reloadMatters() {
        let matters = self.matters
        let cases = self.cases
        Task { await loadMatters(matters, cases: cases) }
    }

    // MARK: - States

    private var loading: some View {
        ProgressView()
            .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func refreshFailed(_ failure: LoadFailure) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("The cause lists couldn't be checked. \(causeList?.listings.isEmpty == false ? "This is what was last loaded." : "")")
                    .foregroundStyle(theme.textPrimary)
                Text(failure.message)
                    .foregroundStyle(theme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if failure.isRetryable {
                Button("Retry") {
                    Task { await refresh() }
                }
                .buttonStyle(.quietAction)
            }
        }
        .font(.brand(.footnote))
        .foregroundStyle(theme.warning)
        .padding(Spacing.md)
        .background(Color(theme.palette.bannerWash), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: - Loading and requests

    private func loadOnce() async {
        if causeList == nil {
            causeList = CauseListViewModel(service: session.cases, cache: session.cache)
        }
        if cases == nil {
            cases = CaseListViewModel(
                service: session.cases, cache: session.cache, store: Self.docketPreferences)
        }
        if matters == nil {
            matters = MattersListViewModel(service: session.projects)
        }
        let causeList = self.causeList
        let cases = self.cases
        let matters = self.matters
        await causeList?.load()
        await cases?.load()
        await loadMatters(matters, cases: cases)
    }

    /// The matters, then the docket told which cases they hold — a case a matter links is shown
    /// as that matter, not again as a tracked case.
    private func loadMatters(_ matters: MattersListViewModel?, cases: CaseListViewModel?) async {
        guard let matters else { return }
        await matters.load()
        cases?.hiddenCaseIDs = matters.linkedCaseIDs
    }

    /// Where the docket's sort, grouping and filters are remembered between launches.
    static var docketPreferences: any PreferenceStore {
        #if DEBUG
        if UITestSupport.isActive { return uiTestDocketPreferences }
        #endif
        return Preferences()
    }

    #if DEBUG
    /// `UserDefaults` outlives a UI-test launch — the trap `EmperorApp` documents for the
    /// disclaimer — so a test that filtered the docket would hand its filter to every test after
    /// it, and a case those tests open would simply not be there. Under test the layout is
    /// remembered for one launch; across launches it is `CaseListOrganisationTests`' to prove.
    private static let uiTestDocketPreferences = InMemoryPreferenceStore()
    #endif

    /// Pull to refresh: the cause lists and the docket, then a word on how it went.
    private func refresh() async {
        let causeList = self.causeList
        let cases = self.cases
        let matters = self.matters
        await causeList?.load()
        await cases?.load()
        await loadMatters(matters, cases: cases)
        if causeList?.state.failure == nil {
            toast = "Cause lists checked"
        }
    }

    /// A case asked for from elsewhere. A case one of the user's matters links opens as that
    /// matter, on its Court section — the web's `/cases/<id>`; any other opens its own page.
    private func openRequestedCase() {
        guard let stack = navigator.takePendingCaseStack() else { return }
        segment = .all
        let projects = matters?.projects ?? []
        if let last = stack.last,
           let projectID = CaseToMatter.matterID(forCase: last.caseID, in: projects) {
            path = [.matter(MatterRoute(projectID: projectID, section: CaseToMatter.section, request: last.request))]
            return
        }
        path = stack.map { MattersRoute.legalCase($0) }
    }

    /// A matter asked for from elsewhere: All matters, with its workspace on top.
    private func openRequestedMatter() {
        guard let route = navigator.takePendingMatter() else { return }
        segment = .all
        path = [.matter(route)]
    }

    /// A matter pinned from Home's court lookup: the docket behind this screen is kept across
    /// the session, so it reloads rather than missing the matter that was just added.
    private func openRequestedDocketRefresh() {
        guard navigator.takeDocketRefreshRequest() else { return }
        let cases = self.cases
        Task { await cases?.load() }
    }
}

/// An upcoming hearing: its day as a calendar block, then the matter and where it is listed.
private struct UpcomingRow: View {
    @Environment(\.theme) private var theme
    let dayKey: String
    let listing: CauseListing

    @ScaledMetric(relativeTo: .title2) private var blockWidth: CGFloat = 52

    var body: some View {
        let display = listing.display
        let block = MattersOverview.calendarBlock(dayKey)
        let place = [MattersOverview.courtShortName(listing.courtName), display.room, display.item.map { "Item \($0)" }]
            .compactMap { $0 }.joined(separator: " · ")
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(spacing: 2) {
                Text(block.day)
                    .font(.display(size: 24, relativeTo: .title2))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                Text(block.month)
                    .font(.brand(size: 9.5, weight: .bold, relativeTo: .caption2))
                    .tracking(0.6)
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.vertical, Spacing.sm)
            .frame(width: min(blockWidth, 84))
            .frame(maxHeight: .infinity)
            .background(theme.surface2, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(theme.separator, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(display.reference ?? listing.displayTitle)
                    .font(.brand(.body, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .dynamicLineLimit(1)
                if display.reference != nil {
                    Text(listing.displayTitle)
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !place.isEmpty {
                    StatusPill(text: place)
                        .padding(.top, Spacing.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(DisplayText.longDay(dayKey)). \(display.spoken(listing))")
    }
}

/// A tracked case in the docket: its title, its reference and court, and its next hearing.
private struct DocketRow: View {
    @Environment(\.theme) private var theme
    let legalCase: LegalCase

    var body: some View {
        let next = legalCase.nextHearingDate.map { "Next date " + MattersOverview.shortDay(WireDate.dayKey($0)) }
        let subtitle = [legalCase.caseReference, legalCase.courtName, next]
            .compactMap { $0 }.joined(separator: " · ")
        RecordRow(
            title: legalCase.displayTitle,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            // The whole title, however long: a matter is known by its parties, and the audit
            // found a title limited to two lines cut short at a larger text size.
            titleLines: nil
        ) {
            IconTile(systemImage: legalCase.isCourtSynced ? "building.columns" : "scalemass")
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(legalCase.isCourtSynced ? "From court" : "")
    }
}

/// A sheet over All matters.
enum MatterListSheet: Identifiable {
    case new
    case edit(Project)
    case delete(Project)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let p): return "edit-\(p.id)"
        case .delete(let p): return "delete-\(p.id)"
        }
    }
}

/// What the Matters tab's stack can hold: a tracked case's page, a matter's workspace, or one of
/// a matter's conversations.
enum MattersRoute: Hashable {
    case legalCase(CaseRoute)
    case matter(MatterRoute)
    case matterChat(MatterChatRoute)
}
