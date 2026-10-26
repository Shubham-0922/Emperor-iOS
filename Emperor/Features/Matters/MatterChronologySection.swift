import SwiftUI

/// The workspace's Chronology — the web's `ChronologySection` read-only: the matter's own record
/// and the linked case's hearings and orders as one list (a court fact the server copied into the
/// record is not shown twice), each entry badged with who put it there: You, the Court or AI.
struct MatterChronologySection: View {
    @Environment(\.theme) private var theme

    let model: MatterWorkspaceViewModel

    var body: some View {
        @Bindable var bindable = model
        let entries = model.chronology(newestFirst: model.newestFirst)
        VStack(alignment: .leading, spacing: Spacing.md) {
            RecordSegmentedControl(
                label: "Order",
                options: [(value: true, title: "Newest first"), (value: false, title: "Oldest first")],
                selection: $bindable.newestFirst)

            if entries.isEmpty {
                EmptyStateContent(
                    title: "Nothing on the record yet", systemImage: "clock",
                    message: "Hearings and orders from the court, and the dates added on the web, appear here.",
                    tone: .neutral) {}
            } else {
                RecordGroup {
                    ForEach(Array(entries.enumerated()), id: \.element.key) { index, entry in
                        if index > 0 { RecordDivider(inset: 14) }
                        row(entry)
                            .accessibilityIdentifier("matter-entry-\(entry.key)")
                    }
                }
            }
        }
    }

    private func row(_ entry: MatterRecord.Entry) -> some View {
        let kind = MatterRecord.kindLabel(entry.kind)
        let title = entry.title.isEmpty ? kind : entry.title
        let source = MatterWorkspaceViewModel.sourceLabel(entry)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(entry.day.isEmpty ? "No date" : MatterRecord.fmtDay(entry.day))
                    .font(.brand(.caption, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
                Spacer(minLength: 0)
                StatusPill(text: kind)
                StatusPill(text: source, tone: Self.tone(entry.src))
            }
            Text(title)
                .font(.brand(.body, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !entry.body.isEmpty {
                Text(entry.body)
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !entry.sourceRef.isEmpty {
                Label(entry.sourceRef, systemImage: "doc")
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// You plain, the Court in the record's accent, AI in its informational tone.
    static func tone(_ source: MatterRecord.Source) -> StatusPill.Tone {
        switch source {
        case .manual: return .neutral
        case .court: return .accent
        case .ai: return .info
        }
    }
}
