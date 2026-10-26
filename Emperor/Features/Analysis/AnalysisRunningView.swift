import SwiftUI

/// A run in progress (`AnalysisKit.jsx`, `LiveLoader`): the server's own line about what it is
/// doing, how long it has been going, a bar that fills as the server reports progress
/// (indeterminate until it does), the documents being read, and Cancel.
struct AnalysisRunningView: View {
    let model: AnalysisRunModel
    let stage: String
    let progress: Double
    let startedAt: Date

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: Spacing.sm) {
                SerifHeader(title: model.kind.runningTitle)
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Text(AnalysisRunModel.clock(context.date.timeIntervalSince(startedAt)))
                        .font(.brand(.subheadline, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.accentText)
                        .accessibilityLabel("Running for \(AnalysisRunModel.clock(context.date.timeIntervalSince(startedAt)))")
                }
            }
            if progress > 0 {
                ProgressView(value: min(1, max(0, progress)))
                    .tint(theme.accent)
                    .accessibilityLabel("Progress")
                    .accessibilityValue("\(Int((min(1, max(0, progress)) * 100).rounded())) percent")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Working")
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: "hourglass")
                    .foregroundStyle(theme.accentText)
                    .accessibilityHidden(true)
                Text(stage.isEmpty ? "Working…" : stage)
                    .font(.brand(.body, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("analysis-stage")
            }
            Text("Long documents can take a few minutes. If you close this, the finished run will appear in History.")
                .font(.brand(.footnote))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !model.files.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(model.files.prefix(4), id: \.self) { file in
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(theme.textTertiary)
                                .accessibilityHidden(true)
                            Text(DisplayText.attachmentTitle(file))
                                .font(.brand(.footnote))
                                .foregroundStyle(theme.textSecondary)
                                .dynamicLineLimit(1)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Button("Cancel") { model.cancel() }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("analysis-cancel")
        }
        .padding(Spacing.lg)
        .panel()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("analysis-running")
    }
}
