import SwiftUI

/// Liquidation e-auction notices from IBBI.
///
/// The screen the `auction` notification has never had. Its link — `/auction-notices/<id>` — is
/// an API path with no route on the web either, so until now tapping one of those updates did
/// nothing at all (`NotificationModels.destination`).
///
/// Unlike every other list in this app, these are not the user's own matters: the feed is public
/// market data, global and unscoped. That is why the only personal state here is a watchlist.
struct AuctionListView: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session

    @State private var model: AuctionListViewModel?
    @State private var isShowingWatchlist = false

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(AuctionListViewModel.Copy.title)
            .navigationDestination(for: String.self) { noticeID in
                AuctionDetailView(noticeID: noticeID)
            }
            .task {
                guard model == nil else { return }
                let created = AuctionListViewModel(service: session.auctions)
                model = created
                await created.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: AuctionListViewModel) -> some View {
        @Bindable var bindable = model

        ListStateView(presentation: model.presentation, retry: { await model.load() }) {
            List {
                Section {
                    ForEach(model.notices) { notice in
                        NavigationLink(value: notice.id) {
                            row(notice, model)
                        }
                        .onAppear {
                            // Paging is server-side and offset-based; the last row asks for more.
                            if notice.id == model.notices.last?.id {
                                Task { await model.loadMore() }
                            }
                        }
                    }
                    if model.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } header: {
                    SectionHeader(
                        title: AuctionListViewModel.Copy.subtitle,
                        detail: model.resultSummary)
                } footer: {
                    // On the content state as well as the empty one. Every figure above was
                    // parsed out of a PDF by a scraper, and the notice is the only authority.
                    Text(AuctionListViewModel.Copy.confirmWithNotice)
                        .font(.caption2)
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.canvas)
        } empty: {
            ContentUnavailableView {
                Label(model.emptyTitle, systemImage: "hammer")
            } description: {
                Text(model.emptyDetail)
            } actions: {
                if model.upcomingOnly {
                    Button("Include past auctions") {
                        model.upcomingOnly = false
                        Task { await model.load() }
                    }
                    .buttonStyle(.primaryAction)
                }
            }
        }
        .searchable(text: $bindable.query, prompt: "Company or asset type")
        .onSubmit(of: .search) { Task { await model.load() } }
        .refreshable { await model.load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                filterMenu(model)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isShowingWatchlist = true
                } label: {
                    Label("Watching", systemImage: "eye")
                }
                .accessibilityLabel(
                    model.watchlists.isEmpty
                        ? "Watchlist" : "Watchlist, \(model.watchlists.count) watches")
            }
        }
        .sheet(isPresented: $isShowingWatchlist) {
            AuctionWatchlistSheet(model: model)
        }
        // One alert, not two: SwiftUI presents a single alert per view, so a separate error
        // alert and confirmation alert would leave one of them permanently silent.
        .alert(model.announcementTitle, isPresented: Binding(
            get: { model.isShowingAnnouncement },
            set: { if !$0 { model.dismissAnnouncement() } }
        )) {
            Button("OK") { model.dismissAnnouncement() }
        } message: {
            Text(model.announcementMessage)
        }
    }

    private func filterMenu(_ model: AuctionListViewModel) -> some View {
        Menu {
            Toggle("Upcoming only", isOn: Binding(
                get: { model.upcomingOnly },
                set: { model.upcomingOnly = $0; Task { await model.load() } }))

            Picker("Sort", selection: Binding(
                get: { model.sort },
                set: { model.sort = $0; Task { await model.load() } }
            )) {
                ForEach(AuctionSort.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }

            // Driven by `/auction-notices/facets` rather than a hardcoded list, because the
            // filter compares for exact equality — a value this app invented would match nothing
            // and look like an empty feed.
            if !model.facets.types.isEmpty {
                Picker("Notice type", selection: Binding(
                    get: { model.selectedType },
                    set: { model.selectedType = $0; Task { await model.load() } }
                )) {
                    Text("All types").tag(String?.none)
                    ForEach(model.facets.types) { facet in
                        Text(facet.displayValue).tag(String?.some(facet.id))
                    }
                }
            }

            if !model.facets.platforms.isEmpty {
                Picker("Platform", selection: Binding(
                    get: { model.selectedPlatform },
                    set: { model.selectedPlatform = $0; Task { await model.load() } }
                )) {
                    // The facet list is the top twenty by count, not every platform in the
                    // table, so this menu narrows rather than enumerates.
                    Text("All platforms").tag(String?.none)
                    ForEach(model.facets.platforms) { facet in
                        Text(facet.displayValue).tag(String?.some(facet.id))
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    private func row(_ notice: AuctionNotice, _ model: AuctionListViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(notice.displayDebtor)
                .font(.headline)
                .lineLimit(2)

            if let assets = notice.natureOfAssets, !assets.isEmpty {
                Text(assets)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                // The reserve price is the number this screen exists for, so it is never
                // silently omitted — its absence is stated.
                if let reserve = notice.reservePriceText {
                    Label(reserve, systemImage: "indianrupeesign.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                } else {
                    Text("Reserve price not published")
                        .font(.caption)
                        .foregroundStyle(theme.textTertiary)
                }
            }

            HStack(spacing: 8) {
                if let day = notice.auctionDayKey {
                    Label(DisplayText.longDay(day), systemImage: "calendar")
                }
                if let platform = notice.auctionPlatform, !platform.isEmpty {
                    Text("·")
                    Text(platform).lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(theme.textTertiary)

            HStack(spacing: 6) {
                statusPill(model.status(of: notice))
                if notice.amendsAnEarlierNotice {
                    StatusPill(text: notice.type.label, tone: .warning, systemImage: "pencil")
                }
                if notice.isFallback {
                    // Says the row is thin before the reader assumes the blanks mean zero.
                    StatusPill(
                        text: "Listing only", tone: .neutral, systemImage: "doc.badge.ellipsis")
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func statusPill(_ status: AuctionStatus) -> some View {
        let tone: StatusPill.Tone
        switch status {
        case .today: tone = .danger
        case .upcoming: tone = .success
        case .closed: tone = .neutral
        case .undated: tone = .warning
        }
        return StatusPill(text: status.label, tone: tone)
    }
}

/// The standing watches: a company by CIN, or a keyword over the debtor name and the asset
/// description. A match creates the `auction` notification this whole feature hangs off.
private struct AuctionWatchlistSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    let model: AuctionListViewModel
    @State private var keyword = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Keyword — a sector, an asset type, a company name", text: $keyword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Watch this keyword") {
                        let entered = keyword
                        keyword = ""
                        Task { await model.watch(keyword: entered) }
                    }
                    .disabled(
                        keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || model.isWorking)
                } header: {
                    SectionHeader(title: "Add a watch")
                } footer: {
                    Text("Matched against the corporate debtor and the nature of the assets on every new notice.")
                        .font(.caption2)
                }

                if !model.watchlists.isEmpty {
                    Section {
                        ForEach(model.watchlists) { watch in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(watch.displayLabel)
                                    .font(.subheadline)
                                Text(watch.kindLabel)
                                    .font(.caption2)
                                    .foregroundStyle(theme.textTertiary)
                            }
                            .swipeActions {
                                Button("Stop watching", role: .destructive) {
                                    Task { await model.unwatch(watch) }
                                }
                            }
                        }
                    } header: {
                        SectionHeader(title: "Watching")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.canvas)
            .navigationTitle("Watchlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await model.reloadWatchlists() }
        }
    }
}
