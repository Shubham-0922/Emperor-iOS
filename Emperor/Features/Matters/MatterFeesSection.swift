import SwiftUI

/// The workspace's Fees — the web's `FeesSection` read-only: billed, received, outstanding (or
/// the advance held, when the client has paid ahead) and spent; then the three lists — fees
/// billed, payments received, expenses — the expenses narrowed by category when there are
/// several.
struct MatterFeesSection: View {
    @Environment(\.theme) private var theme

    let model: MatterWorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.md, alignment: .top)],
                      alignment: .leading, spacing: Spacing.md) {
                ForEach(model.feeTiles) { tile in
                    tileView(tile)
                }
            }
            .accessibilityIdentifier("matter-fee-totals")
            ForEach(model.feeColumns) { column in
                columnView(column)
            }
        }
    }

    private func tileView(_ tile: MatterWorkspaceViewModel.FeeTile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(tile.label)
                .recordText(RecordTokens.Typography.label)
                .foregroundStyle(theme.textTertiary)
            Text(tile.value)
                .font(.brand(.title3, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tile.tone == .warning ? theme.warning : theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(tile.detail)
                .font(.brand(.caption))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .overlay(alignment: .leading) {
            if let edge = edgeColor(tile.tone) {
                Rectangle()
                    .fill(edge)
                    .frame(width: 3)
                    .padding(.vertical, Spacing.sm)
                    .accessibilityHidden(true)
            }
        }
        .panel()
        .accessibilityElement(children: .combine)
    }

    private func edgeColor(_ tone: MatterWorkspaceViewModel.FeeTile.Tone) -> Color? {
        switch tone {
        case .plain: return nil
        case .success: return theme.success
        case .warning: return theme.warning
        case .accent: return theme.accent
        }
    }

    private func columnView(_ column: MatterWorkspaceViewModel.FeeColumn) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: column.title, detail: "\(column.count) · \(column.total)")
            if column.kind == "expense", model.feeCategories.count > 1 {
                categoryChips
            }
            if column.count == 0 {
                Text(column.empty)
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                RecordGroup {
                    ForEach(Array(column.entries.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { RecordDivider(inset: 14) }
                        entryRow(row)
                            .accessibilityIdentifier("matter-fee-\(row.id)")
                    }
                }
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(model.feeCategories, id: \.key) { category in
                    let isSelected = model.activeFeeCategory == category.key
                    Button {
                        model.feeCategory = isSelected ? nil : category.key
                    } label: {
                        ChipLabel(title: "\(category.label) · \(Ledger.rupees(Double(category.paise) / 100))",
                                  isSelected: isSelected)
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: isSelected))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func entryRow(_ row: MatterWorkspaceViewModel.FeeRow) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(row.title)
                    .font(.brand(.body, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.sm)
                Text(row.amount)
                    .font(.brand(.body, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize()
            }
            HStack(spacing: Spacing.sm) {
                Text(row.date)
                    .font(.brand(.caption))
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
                if let badge = row.badge {
                    StatusPill(text: badge, tone: .accent)
                }
                if let reference = row.reference {
                    Text(reference)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .dynamicLineLimit(1)
                }
            }
            if let receipt = row.receipt {
                Label(receipt, systemImage: "paperclip")
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notes = row.notes {
                Text(notes)
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}
