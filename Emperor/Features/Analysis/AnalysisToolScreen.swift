import SwiftUI

/// Devil's Advocate, Doc Index and List of Dates: the analysis tools run over the reader's
/// documents in My Files, one screen for the three (`src/pages/analysis/*`).
///
/// The run itself — start, poll, cancel, failure, History — is `AnalysisRunModel`'s; this lays
/// out the intake, the running state, the failure and each tool's result, with History and the
/// downloads in the bar.
struct AnalysisToolScreen: View {
    static let isReady = true

    let kind: AnalysisToolKind

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session

    @State private var model: AnalysisRunModel?
    @State private var showsHistory = false
    @State private var docIndexState = DocIndexViewState()
    @State private var dateChartState = DateChartViewState()
    @State private var toast: String?

    init(kind: AnalysisToolKind) {
        self.kind = kind
    }

    /// How often a running job is asked about. Quicker against the UI tests' stub server.
    private static var pollInterval: Duration {
        #if DEBUG
        if UITestSupport.isActive { return .milliseconds(300) }
        #endif
        return .seconds(2)
    }

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
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let model {
                        if let outcome = model.outcome {
                            AnalysisExportMenu(
                                outcome: outcome, docIndexState: docIndexState,
                                dateChartState: dateChartState, toast: $toast)
                            Button {
                                model.startOver()
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .accessibilityLabel("Start over")
                            .accessibilityIdentifier("analysis-toolbar-start-over")
                        }
                        Button {
                            showsHistory = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .accessibilityLabel(model.history.buttonLabel)
                        .accessibilityIdentifier("analysis-history")
                    }
                }
            }
            .sheet(isPresented: $showsHistory) {
                if let model {
                    AnalysisHistorySheet(history: model.history) { run in
                        model.show(run: run)
                    }
                    .pageSizedSheet()
                }
            }
            .recordToast($toast)
            .task {
                guard model == nil else { return }
                let service = session.analysis
                let history = AnalysisHistoryModel(kind: kind, service: service)
                model = AnalysisRunModel(
                    kind: kind, service: service, history: history, pollInterval: Self.pollInterval)
                await history.refresh()
            }
            .onChange(of: model?.phase) { _, _ in
                // A new result starts with nothing searched, filtered or hidden.
                if model?.outcome != nil { return }
                docIndexState = DocIndexViewState()
                dateChartState = DateChartViewState()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: AnalysisRunModel) -> some View {
        switch model.phase {
        case .intake:
            page { AnalysisIntakeView(model: model) }
        case .running(let stage, let progress, let startedAt):
            page {
                AnalysisRunningView(model: model, stage: stage, progress: progress, startedAt: startedAt)
            }
        case .failed(let failure):
            page { AnalysisFailureView(model: model, failure: failure) }
        case .done(let outcome):
            switch outcome.result {
            case .devilsAdvocate(let report):
                DevilsAdvocateReportView(model: model, outcome: outcome, report: report)
                    .id(outcome.fromHistory?.id ?? "fresh-\(outcome.madeOn.timeIntervalSince1970)")
            case .docIndex(let index):
                DocIndexView(model: model, outcome: outcome, index: index, state: $docIndexState)
            case .listOfDates(let chart):
                DateChartView(
                    model: model, outcome: outcome, chart: chart, state: $dateChartState, toast: $toast)
            }
        }
    }

    /// The intake, the running state and a failure: one readable column that scrolls.
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.lg)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("analysis-screen-\(kind.rawValue)")
    }
}
