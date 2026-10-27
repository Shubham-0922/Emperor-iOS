import SwiftUI

/// What an assembly run came to: the bundle with its index, page ranges and checklist, or every
/// problem that stopped it — the assembler fails closed and lists them all at once.
struct FilingResultView: View {
    /// The result's row, scrolled to when a run ends: it lands below Assemble, often below the
    /// screen's edge, where a failure would otherwise go unseen.
    static let anchor = "filing-result-anchor"

    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass

    let model: FilingAssemblyViewModel
    let result: FilingAssemblyResult
    let onOpen: (FilingBundle) -> Void

    var body: some View {
        Section {
            Group {
                if result.success {
                    success
                } else {
                    failure
                }
            }
            .id(Self.anchor)
        } header: {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Result")
                Spacer(minLength: Spacing.sm)
                Button {
                    model.dismissOutcome()
                } label: {
                    Image(systemName: "xmark")
                        .font(.brand(.footnote, weight: .bold))
                        .foregroundStyle(theme.textFaint)
                        .frame(minWidth: Layout.touchTarget, minHeight: Layout.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
            }
        }
    }

    // MARK: - Failure

    private var failure: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.danger)
                    .accessibilityHidden(true)
                Text(FilingAssemblyViewModel.failureTitle)
                    .font(.brand(.headline))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("filing-result-failed")
            }
            Text(FilingAssemblyViewModel.failureHint)
                .font(.brand(.footnote))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(result.errorLines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text(line)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .font(.brand(.footnote))
                .foregroundStyle(theme.danger)
                .padding(Spacing.sm)
                .background(
                    theme.dangerBg,
                    in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("filing-error-\(index)")
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Success

    private var success: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.success)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(result.successTitle)
                        .font(.brand(.headline))
                        .foregroundStyle(theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("filing-result-ok")
                    if let line = result.verifyLine {
                        Text(line)
                            .font(.brand(.caption))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let id = result.bundleId {
                Button {
                    onOpen(FilingBundle(
                        id: id, draftID: model.draft?.id ?? "", pageCount: result.pageCount,
                        status: "ok"))
                } label: {
                    Label("Open bundle", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("filing-open-bundle")
            }

            ForEach(Array((result.warnings ?? []).enumerated()), id: \.offset) { _, warning in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .accessibilityHidden(true)
                    Text(warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .font(.brand(.footnote))
                .foregroundStyle(theme.warning)
                .padding(Spacing.sm)
                .background(
                    theme.warnBg,
                    in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .accessibilityElement(children: .combine)
            }

            if sizeClass == .regular {
                HStack(alignment: .top, spacing: Spacing.xl) {
                    indexColumn.frame(maxWidth: .infinity, alignment: .leading)
                    checklistColumn.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                indexColumn
                checklistColumn
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var indexColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Index")
            let rows = result.index ?? []
            if rows.isEmpty {
                Text("No index entries returned.")
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textSecondary)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(row.label)
                        .font(.brand(.subheadline))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Spacing.sm)
                    Text("\(row.folio)")
                        .font(.brand(.subheadline))
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }

            let ranges = result.annexures ?? []
            if !ranges.isEmpty {
                SectionHeader(title: "Annexure page ranges")
                    .padding(.top, Spacing.sm)
                ForEach(Array(ranges.enumerated()), id: \.offset) { _, range in
                    HStack(spacing: Spacing.sm) {
                        StatusPill(text: range.mark, tone: .accent)
                        Text("pp. \(range.from)–\(range.to)")
                            .font(.brand(.subheadline))
                            .monospacedDigit()
                            .foregroundStyle(theme.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private var checklistColumn: some View {
        if let checklist = result.checklist {
            FilingChecklistList(checklist: checklist)
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: "Before you can file")
                Text("No checklist returned.")
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }
}

/// A forum's checklist under the page's three headings, each item with its status.
struct FilingChecklistList: View {
    @Environment(\.theme) private var theme

    let checklist: FilingChecklist

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Before you can file · \(checklist.forum)")
                .font(.brand(.subheadline, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if checklist.items.isEmpty {
                Text("No checklist returned.")
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textSecondary)
            }
            ForEach(checklist.groups) { group in
                SectionHeader(title: group.title)
                    .padding(.top, Spacing.xs)
                ForEach(group.items) { item in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(item.label)
                                .font(.brand(.subheadline))
                                .foregroundStyle(theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let note = item.note, !note.isEmpty {
                                Text(note)
                                    .font(.brand(.caption))
                                    .foregroundStyle(theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: Spacing.sm)
                        StatusPill(text: item.status, tone: Self.tone(for: item.status))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("filing-checklist-\(item.id)")
                }
            }
        }
    }

    static func tone(for status: String) -> StatusPill.Tone {
        switch FilingChecklistTone.tone(for: status) {
        case .success: return .success
        case .danger: return .danger
        case .warn: return .warning
        case .neutral: return .neutral
        }
    }
}
