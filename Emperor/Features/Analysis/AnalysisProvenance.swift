import SwiftUI

/// What sits above every result: where it came from when it came from History
/// (`AnalysisHistory.jsx`, `HistoryBanner`), and what was read (`AnalysisKit.jsx`, `Provenance`).
struct AnalysisResultHeader: View {
    let model: AnalysisRunModel
    let outcome: AnalysisOutcome

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let stored = outcome.fromHistory {
                historyBanner(stored)
            }
            AnalysisProvenance(fileNames: outcome.fileNames, reference: outcome.reference)
        }
    }

    private func historyBanner(_ stored: AnalysisRunSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: "clock")
                    .foregroundStyle(theme.accentText)
                    .accessibilityHidden(true)
                Text("From your history · \(AnalysisHistoryFormat.fullDate(stored.createdAt))")
                    .font(.brand(.footnote, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                model.startOver()
            } label: {
                Label("Run again with new documents", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(QuietButtonStyle())
            .padding(.leading, -Spacing.md)
            .accessibilityIdentifier("analysis-run-again-new")
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The card's own surface with the accent's hairline: the accent's words, as on the
        // button here, are not legible enough on the accent wash in dark.
        .background(theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(theme.accentLine, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("analysis-history-banner")
    }
}

/// "Read 3 documents: a.pdf, b.pdf and 1 more · with your reference note".
struct AnalysisProvenance: View {
    let fileNames: [String]
    let reference: String

    @Environment(\.theme) private var theme

    var body: some View {
        let note = AnalysisJS.trim(reference).isEmpty ? "" : " \(AnalysisHistoryFormat.withReference)"
        Text(AnalysisHistoryFormat.provenance(fileNames) + note)
            .font(.brand(.footnote))
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("analysis-provenance")
    }
}
