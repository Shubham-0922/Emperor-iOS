import SwiftUI

/// One document of a Doc Index in full (`DocIndexPage.jsx`, `Detail`): its name, every long
/// column as a paragraph, every tag column, and the remaining facts.
struct DocIndexDetailSheet: View {
    let index: DocIndex
    let row: DocIndex.Row

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let strong = index.strongColumn
        let long = index.columns.filter { $0.type == .long }
        let tags = index.columns.filter { $0.type == .tags }
        let skipped: [DocIndex.ColumnType] = [.long, .tags, .number]
        let facts = index.columns.filter { !skipped.contains($0.type) && $0.key != strong.key }
        VStack(spacing: 0) {
            RecordSheetHeader(title: DocIndex.cellText(strong, row).isEmpty ? "Document" : DocIndex.cellText(strong, row)) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text(DocIndex.cellText(strong, row))
                        .font(.display(size: 22, relativeTo: .title2))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(long) { column in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(column.label)
                                .recordText(RecordTokens.Typography.label)
                                .foregroundStyle(theme.textTertiary)
                                .accessibilityAddTraits(.isHeader)
                            let text = DocIndex.cellText(column, row)
                            Text(text.isEmpty ? "Nothing noted." : text)
                                .font(.brand(.body))
                                .foregroundStyle(text.isEmpty ? theme.textSecondary : theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    ForEach(tags) { column in
                        let values = tagValues(column)
                        if !values.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(column.label)
                                    .recordText(RecordTokens.Typography.label)
                                    .foregroundStyle(theme.textTertiary)
                                    .accessibilityAddTraits(.isHeader)
                                AnalysisFlow(spacing: Spacing.xs) {
                                    ForEach(Array(values.enumerated()), id: \.offset) { _, tag in
                                        StatusPill(text: tag, tone: .neutral)
                                    }
                                }
                            }
                        }
                    }
                    if !facts.isEmpty {
                        RecordGroup {
                            ForEach(Array(facts.enumerated()), id: \.element.id) { offset, column in
                                if offset > 0 { RecordDivider(inset: 14) }
                                ValueRow(column.label, value: value(column))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(theme.groupedBackground)
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("di-detail")
    }

    private func tagValues(_ column: DocIndex.Column) -> [String] {
        if case .tags(let values)? = row[column.key] { return values }
        return []
    }

    private func value(_ column: DocIndex.Column) -> String {
        let text = DocIndex.cellText(column, row)
        return text.isEmpty ? "—" : text
    }
}
