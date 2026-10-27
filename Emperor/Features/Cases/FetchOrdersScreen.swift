import SwiftUI

/// Fetch Orders: a case's orders, hearings and parties read from the court's own records, with
/// nothing saved — and Add to Matters for a case worth keeping.
///
/// The search is the court search every other screen uses, its result offered as "Fetch this
/// case". Every rule and sentence lives in `FetchOrdersViewModel`; this lays it out.
struct FetchOrdersScreen: View {
    static let isReady = true

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session

    @State private var model: FetchOrdersViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(theme.groupedBackground)
            .navigationTitle(FetchOrdersViewModel.Copy.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                guard model == nil else { return }
                model = FetchOrdersViewModel(
                    service: session.fetchOrders,
                    matters: session.matterCreation,
                    history: session.lookupHistory)
            }
        }
        // A court read that is still running when the screen closes is abandoned.
        .onDisappear { model?.cancel() }
    }

    @ViewBuilder
    private func content(_ model: FetchOrdersViewModel) -> some View {
        switch model.phase {
        case .search:
            searchView(model)
        case .loading:
            loadingView(model)
        case .failed(_, let failure):
            failedView(model, failure: failure)
        case .record(_, let record, _):
            LookupDossierView(model: model, record: record, onMatterOpened: { dismiss() })
        }
    }

    // MARK: - Search

    private func searchView(_ model: FetchOrdersViewModel) -> some View {
        let leading = AnyView(headerSection)
        let trailing = AnyView(guideSections(model))
        return CourtSearchView(
            onSaved: {},
            onPick: { result in model.fetch(result) },
            pickLabel: FetchOrdersViewModel.Copy.pickLabel,
            embedded: true,
            leadingSections: leading,
            trailingSections: trailing)
    }

    private var headerSection: some View {
        Section {
            SerifHeader(
                eyebrow: FetchOrdersViewModel.Copy.title,
                title: FetchOrdersViewModel.Copy.headline,
                subtitle: FetchOrdersViewModel.Copy.blurb)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: Spacing.sm, leading: 0, bottom: Spacing.sm, trailing: 0))
                .accessibilityIdentifier("fetch-orders-header")
        }
    }

    @ViewBuilder
    private func guideSections(_ model: FetchOrdersViewModel) -> some View {
        Section {
            ForEach(Array(FetchOrdersViewModel.Copy.steps.enumerated()), id: \.offset) { pair in
                stepRow(index: pair.offset, step: pair.element)
            }
        } header: {
            SectionHeader(title: "How it works")
        }
        .listRowBackground(theme.surface)

        if !model.shownRecent.isEmpty {
            Section {
                ForEach(Array(model.shownRecent.enumerated()), id: \.element.id) { pair in
                    recentRow(model, entry: pair.element, index: pair.offset)
                }
            } header: {
                SectionHeader(title: FetchOrdersViewModel.Copy.recentTitle)
            }
            .listRowBackground(theme.surface)
        }
    }

    private func stepRow(index: Int, step: (title: String, text: String, symbol: String)) -> some View {
        let number: Int = index + 1
        let title: String = "\(number). \(step.title)"
        return HStack(alignment: .top, spacing: Spacing.md) {
            IconTile(systemImage: step.symbol)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.brand(.subheadline, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(step.text)
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private func recentRow(
        _ model: FetchOrdersViewModel, entry: LookupHistory.Entry, index: Int
    ) -> some View {
        Button {
            model.open(entry)
        } label: {
            HStack(spacing: Spacing.md) {
                IconTile(systemImage: "building.columns")
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(entry.displayTitle)
                        .font(.brand(.subheadline, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .dynamicLineLimit(1)
                    Text(entry.detail)
                        .font(.brand(.caption))
                        .foregroundStyle(theme.textTertiary)
                        .dynamicLineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RowChevron()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("fetch-recent-\(index)")
    }

    // MARK: - Loading and failure

    private func loadingView(_ model: FetchOrdersViewModel) -> some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                ProgressView()
                    .controlSize(.large)
                Text(model.loadingText)
                    .font(.display(size: 22, relativeTo: .title2))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("fetch-loading")
                Text(FetchOrdersViewModel.Copy.slow)
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Stop") { model.reset() }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("fetch-stop")
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.xxxl)
            .frame(maxWidth: .infinity)
        }
    }

    private func failedView(_ model: FetchOrdersViewModel, failure: LookupFailure) -> some View {
        EmptyStateView(
            failure.title, systemImage: "exclamationmark.triangle",
            message: failure.message, tone: .danger
        ) {
            if failure.retryable {
                Button(FetchOrdersViewModel.Copy.tryAgain) { model.retry() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("fetch-retry")
            }
            Button(FetchOrdersViewModel.Copy.searchAgain) { model.reset() }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("fetch-search-again")
        }
        .onAppear { VoiceOver.announce(failure.title) }
    }
}
