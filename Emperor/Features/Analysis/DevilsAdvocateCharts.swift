import SwiftUI
import Charts

/// The colour a weak spot's severity is drawn in, and its pill's tone.
@MainActor
enum DevilsAdvocateTone {
    static func color(_ severity: DevilsAdvocateReport.Severity, _ theme: Theme) -> Color {
        switch severity {
        case .serious: return theme.danger
        case .moderate: return theme.warning
        case .minor: return theme.accent
        }
    }

    static func pill(_ severity: DevilsAdvocateReport.Severity) -> StatusPill.Tone {
        switch severity {
        case .serious: return .danger
        case .moderate: return .warning
        case .minor: return .info
        }
    }

    static func symbol(_ severity: DevilsAdvocateReport.Severity) -> String {
        switch severity {
        case .serious: return "exclamationmark.octagon"
        case .moderate: return "exclamationmark.triangle"
        case .minor: return "info.circle"
        }
    }

    static func pill(_ readiness: DevilsAdvocateReport.Readiness) -> StatusPill.Tone {
        switch readiness {
        case .ready: return .success
        case .work: return .warning
        case .gap: return .danger
        }
    }
}

/// "How serious": the spots by severity, as a ring with the count in its middle.
struct DevilsAdvocateSeverityDonut: View {
    let report: DevilsAdvocateReport

    @Environment(\.theme) private var theme

    private struct Slice: Identifiable {
        let severity: DevilsAdvocateReport.Severity
        let count: Int
        let color: Color
        var id: String { severity.rawValue }
    }

    var body: some View {
        let counts = report.countBySeverity
        let total = report.weakSpots.count
        let inset: CGFloat = total > 1 ? 1.5 : 0
        let slices: [Slice] = DevilsAdvocateReport.Severity.allCases
            .map { Slice(severity: $0, count: counts[$0], color: DevilsAdvocateTone.color($0, theme)) }
            .filter { $0.count > 0 }
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("How serious")
                .font(.brand(.headline))
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("\(total == 1 ? "The weak spot" : "The \(total) weak spots"), by how badly each could hurt.")
                .font(.brand(.footnote))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            AdaptiveStack(spacing: Spacing.lg) {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Spots", slice.count),
                        innerRadius: .ratio(0.62),
                        angularInset: inset)
                        .foregroundStyle(slice.color)
                }
                .chartLegend(.hidden)
                .frame(width: 132, height: 132)
                .overlay {
                    VStack(spacing: 0) {
                        Text("\(total)")
                            .font(.display(size: 26, relativeTo: .title))
                            .foregroundStyle(theme.textPrimary)
                        Text(total == 1 ? "weak spot" : "weak spots")
                            .font(.brand(.caption2))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(counts.serious) serious, \(counts.moderate) moderate, \(counts.minor) minor")
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(DevilsAdvocateReport.Severity.allCases, id: \.self) { severity in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(DevilsAdvocateTone.color(severity, theme))
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(severity.label) \(counts[severity])")
                                    .font(.brand(.subheadline, weight: .semibold))
                                    .foregroundStyle(theme.textPrimary)
                                Text(severity.hint)
                                    .font(.brand(.caption))
                                    .foregroundStyle(theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}

/// "Where the weak spots sit": one bar per category, heavier severities weighing more.
struct DevilsAdvocateCategoryBars: View {
    let report: DevilsAdvocateReport

    @Environment(\.theme) private var theme

    private struct Piece: Identifiable {
        let category: String
        let severity: DevilsAdvocateReport.Severity
        let weight: Int
        let color: Color
        var id: String { "\(category)-\(severity.rawValue)" }
    }

    var body: some View {
        let rows = report.categoryRows
        let chartHeight: CGFloat = CGFloat(max(rows.count, 1) * 34 + 8)
        let pieces: [Piece] = rows.flatMap { row in
            DevilsAdvocateReport.Severity.allCases.compactMap { severity -> Piece? in
                let n = row.by[severity]
                return n > 0 ? Piece(
                    category: row.label, severity: severity, weight: n * severity.weight,
                    color: DevilsAdvocateTone.color(severity, theme)) : nil
            }
        }
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Where the weak spots sit")
                .font(.brand(.headline))
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("A longer bar means more risk in that area. Serious spots weigh more than minor ones.")
                .font(.brand(.footnote))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Chart(pieces) { piece in
                BarMark(
                    x: .value("Weight", piece.weight),
                    y: .value("Category", piece.category))
                    .foregroundStyle(piece.color)
            }
            .chartXAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: chartHeight)
            .accessibilityHidden(true)
            // The bars' content, said in words: the chart's own reading of them is numbers only.
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(rows) { row in
                    Text("\(row.label): \(row.count) — \(row.by.serious) serious, \(row.by.moderate) moderate, \(row.by.minor) minor")
                        .font(.brand(.caption))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}

/// "How hard they will push": likelihood against impact, each spot a numbered pin that jumps to
/// its card.
struct DevilsAdvocatePushMatrix: View {
    let report: DevilsAdvocateReport
    let onPick: (Int) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        let cells = report.matrixCells
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("How hard they will push")
                .font(.brand(.headline))
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Each numbered dot is a weak spot below. Further right means they are more likely to raise it. Higher up means it hurts more if they do. Tap a dot to jump to it.")
                .font(.brand(.footnote))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .center, spacing: Spacing.xs) {
                Text("Impact if raised")
                    .font(.brand(.caption2, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { row in
                        HStack(spacing: 3) {
                            ForEach(0..<5, id: \.self) { column in
                                cell(cells[row * 5 + column])
                            }
                        }
                    }
                    HStack(spacing: 3) {
                        ForEach(1...5, id: \.self) { n in
                            Text("\(n)")
                                .font(.brand(.caption2))
                                .foregroundStyle(theme.textSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .accessibilityHidden(true)
                    HStack {
                        Text("Unlikely")
                        Spacer(minLength: Spacing.xs)
                        Text("Likelihood they raise it")
                        Spacer(minLength: Spacing.xs)
                        Text("Near certain")
                    }
                    .font(.brand(.caption2, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                    .accessibilityHidden(true)
                }
            }
            AdaptiveStack(spacing: Spacing.md) {
                key(theme.dangerBg, edge: theme.danger, "Expect a hard push")
                key(theme.warnBg, edge: theme.warning, "Likely to come up")
                key(theme.surface2, edge: theme.borderStrong, "Low pressure")
            }
            .accessibilityHidden(true)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Likelihood against impact grid")
    }

    private func wash(_ score: Int) -> Color {
        score >= 16 ? theme.dangerBg : score >= 9 ? theme.warnBg : theme.surface2
    }

    private func cell(_ cell: DevilsAdvocateReport.MatrixCell) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Layout.touchTarget), spacing: 0)], spacing: 0) {
            ForEach(cell.spots) { spot in
                Button {
                    onPick(spot.id)
                } label: {
                    Text("\(spot.id)")
                        .font(.brand(.caption, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(DevilsAdvocateTone.color(spot.severity, theme), lineWidth: 2))
                        .frame(minWidth: Layout.touchTarget, minHeight: Layout.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Weak spot \(spot.id): \(spot.title). Likelihood \(spot.likelihood) of 5, impact \(spot.impact) of 5")
                .accessibilityIdentifier("da-pin-\(spot.id)")
            }
        }
        .frame(maxWidth: .infinity, minHeight: Layout.touchTarget)
        .background(wash(cell.score), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func key(_ fill: Color, edge: Color, _ text: String) -> some View {
        HStack(spacing: Spacing.xs) {
            RoundedRectangle(cornerRadius: 3)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(edge, lineWidth: 1))
                .frame(width: 10, height: 10)
            Text(text)
                .font(.brand(.caption))
                .foregroundStyle(theme.textSecondary)
        }
    }
}
