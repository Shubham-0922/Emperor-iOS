import SwiftUI

/// One matter on the Matters list — the web's card (`ProjectCard.jsx`) as a row: the banner as a
/// tile, the name, its practice area, who we act for, the court and case number, the next
/// hearing and the next task due, the counts the server sent, a High flag and the status.
///
/// Read as one sentence (`MattersListViewModel.Card.spoken`).
struct MatterRow: View {
    @Environment(\.theme) private var theme

    let card: MattersListViewModel.Card
    let preset: MatterVocabulary.BannerPreset
    var imageData: Data?

    @ScaledMetric(relativeTo: .body) private var tileSide: CGFloat = 44

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            MatterBannerView(preset: preset, imageData: imageData)
                .frame(width: min(tileSide, 64), height: min(tileSide, 64))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(card.name)
                    .font(.brand(.body, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .dynamicLineLimit(3)
                if !card.area.isEmpty {
                    Text(card.area)
                        .font(.brand(.caption, weight: .semibold))
                        .foregroundStyle(theme.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !card.description.isEmpty {
                    Text(card.description)
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textFaint)
                        .dynamicLineLimit(2)
                }
                if !card.client.isEmpty {
                    fact(card.client, systemImage: "person")
                }
                if !card.court.isEmpty {
                    fact(card.court, systemImage: "building.columns")
                }
                if card.hearing != nil || card.taskDue != nil {
                    chips
                        .padding(.top, Spacing.xs)
                }
                footer
                    .padding(.top, Spacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RowChevron()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: Layout.listRow)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.spoken)
    }

    private func fact(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .imageScale(.small)
        }
        .font(.brand(.footnote))
        .foregroundStyle(theme.textSecondary)
    }

    private var chips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) { chipViews }
            VStack(alignment: .leading, spacing: Spacing.xs) { chipViews }
        }
    }

    @ViewBuilder
    private var chipViews: some View {
        if let hearing = card.hearing {
            StatusPill(text: "Next hearing \(hearing.text)", tone: Self.tone(hearing.tone), systemImage: "calendar")
        }
        if let due = card.taskDue {
            StatusPill(text: "Task due \(due.text)", tone: Self.tone(due.tone), systemImage: "checklist")
        }
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            if !card.counts.isEmpty {
                Text(card.counts)
                    .font(.brand(.caption))
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if card.isHigh {
                StatusPill(text: "High", tone: .danger, systemImage: "flag.fill")
            }
            StatusPill(text: card.status.label, tone: Self.statusTone(card.status))
        }
    }

    static func tone(_ tone: MattersListViewModel.Card.Tone) -> StatusPill.Tone {
        switch tone {
        case .danger: return .danger
        case .warn: return .warning
        case .accent: return .accent
        case .mute: return .neutral
        }
    }

    static func statusTone(_ status: MatterVocabulary.ProjectStatus) -> StatusPill.Tone {
        switch status {
        case .active: return .success
        case .onHold: return .warning
        case .disposed, .archived: return .neutral
        }
    }
}
