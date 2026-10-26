import SwiftUI

/// The past runs of one tool (`AnalysisHistory.jsx`): newest first, a search once there are more
/// than eight, Open and Delete. The list is asked for again each time the sheet opens, with what
/// was already known kept on screen meanwhile.
struct AnalysisHistorySheet: View {
    let history: AnalysisHistoryModel
    /// Called with the stored run once it has been fetched; the sheet closes itself.
    let onOpen: @MainActor (AnalysisRun) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: AnalysisRunSummary?

    var body: some View {
        VStack(spacing: 0) {
            RecordSheetHeader(title: "History", subtitle: history.kind.historySubtitle) { dismiss() }
            if history.offersSearch {
                RecordSearchField(
                    text: Binding(get: { history.query }, set: { history.query = $0 }),
                    prompt: "Search by title or file name")
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.bottom, Spacing.sm)
                    .accessibilityIdentifier("analysis-history-search")
            }
            if let error = history.openError {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .accessibilityHidden(true)
                    Text(error)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .font(.brand(.footnote))
                .foregroundStyle(theme.danger)
                .padding(Spacing.md)
                .background(theme.dangerBg, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, Spacing.sm)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("analysis-history-error")
            }
            content
        }
        .background(theme.groupedBackground)
        .task { await history.refresh(silent: true) }
        .onDisappear { history.clearOpenError() }
        .confirmationDialog(
            "Delete this run?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { run in
            Button("Delete", role: .destructive) {
                Task { await history.remove(run.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { run in
            Text(run.displayTitle)
        }
        .accessibilityIdentifier("analysis-history-sheet")
    }

    @ViewBuilder
    private var content: some View {
        switch history.status {
        case .loading where history.runs.isEmpty:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading your history")
        case .failed(let message) where history.runs.isEmpty:
            EmptyStateView("Could not load", systemImage: "exclamationmark.triangle", message: message, tone: .warning) {
                Button("Try again") { Task { await history.refresh() } }
                    .buttonStyle(PrimaryButtonStyle())
            }
        case .ready where history.runs.isEmpty:
            EmptyStateView(
                "Nothing yet", systemImage: "clock",
                message: "Nothing yet — your finished runs appear here", tone: .neutral)
                .accessibilityIdentifier("analysis-history-empty")
        default:
            list
        }
    }

    private var list: some View {
        List {
            if history.filtered.isEmpty {
                Text("No runs match “\(AnalysisJS.trim(history.query))”.")
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
            ForEach(history.filtered) { run in
                row(run)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleting = run
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await history.refresh() }
    }

    private func row(_ run: AnalysisRunSummary) -> some View {
        let opening = history.opening == run.id
        let names = run.fileNames ?? []
        let when = AnalysisHistoryFormat.ago(run.createdAt)
        let detail = [when, names.isEmpty ? "" : AnalysisHistoryFormat.fileLine(names)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(run.displayTitle)
                    .font(.brand(.body, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .dynamicLineLimit(2)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textSecondary)
                        .dynamicLineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
            AdaptiveStack(spacing: Spacing.sm) {
                Button {
                    Task {
                        if let stored = await history.open(run.id) {
                            onOpen(stored)
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        if opening { ProgressView() }
                        Text(opening ? "Opening…" : "Open")
                    }
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .disabled(history.opening != nil)
                .accessibilityLabel("Open \(run.displayTitle)")
                .accessibilityIdentifier("analysis-history-open-\(run.id)")
                Spacer(minLength: 0)
                Button {
                    deleting = run
                } label: {
                    Image(systemName: "trash")
                        .frame(minWidth: Layout.touchTarget, minHeight: Layout.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.textSecondary)
                .disabled(history.opening != nil)
                .accessibilityLabel("Delete \(run.displayTitle)")
                .accessibilityIdentifier("analysis-history-delete-\(run.id)")
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("analysis-history-row-\(run.id)")
    }
}
