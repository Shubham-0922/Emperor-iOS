import SwiftUI

/// A run that did not finish. A refusal about the plan or the account is said calmly, as a
/// refusal, with no "Try again" — another try is refused the same way (`analysisKit.js`,
/// `isPlanError`). Anything else says what happened and offers the run again.
struct AnalysisFailureView: View {
    let model: AnalysisRunModel
    let failure: AnalysisFailure

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if let refusal = failure.refusal, !failure.canRetry {
                Text(model.kind.failureTitle)
                    .font(.display(size: 22, relativeTo: .title2))
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                RefusalCard(refusal: refusal)
                Button("Start over") { model.startOver() }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("analysis-start-over")
            } else {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    IconCircle(systemImage: "exclamationmark.triangle", tone: .warning)
                    Text(model.kind.failureTitle)
                        .font(.display(size: 22, relativeTo: .title2))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(model.failureMessage ?? failure.message)
                        .font(.brand(.body))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("analysis-error-message")
                    AdaptiveStack(spacing: Spacing.sm) {
                        Button {
                            Task { await model.retry() }
                        } label: {
                            Label("Try again", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(PrimaryButtonStyle(compact: true))
                        .accessibilityIdentifier("analysis-retry")
                        Button("Start over") { model.startOver() }
                            .buttonStyle(QuietButtonStyle())
                            .accessibilityIdentifier("analysis-start-over")
                    }
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("analysis-error")
    }
}
