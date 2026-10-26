import SwiftUI

/// The workspace's Court section — the web's `CourtSection` read-only: the linked case in
/// summary with a way to its own page, then its record by part — hearings, orders, applications,
/// parties by side, connected matters. A matter with no linked case says why: not linked, not
/// filed yet, or linked to a case this user can no longer see.
struct MatterCourtSection: View {
    @Environment(\.theme) private var theme

    let model: MatterWorkspaceViewModel
    let onOpenCase: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if let notice = model.courtNotice {
                noticePanel(notice)
            }
            if let linked = model.detail?.linkedCase, let heading = model.linkedCaseTitle {
                summary(linked, heading: heading)
                ForEach(model.courtGroups) { group in
                    courtGroup(group)
                }
                parties
            }
        }
    }

    private func noticePanel(_ notice: String) -> some View {
        let unavailable = !(model.project?.linkedCaseID ?? "").isEmpty
        return HStack(alignment: .top, spacing: Spacing.md) {
            IconTile(systemImage: unavailable ? "exclamationmark.triangle" : model.project?.isNotFiled == true
                     ? "clock.badge.questionmark" : "building.columns")
            Text(notice)
                .font(.brand(.subheadline))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.lg)
        .panel()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("matter-court-notice")
    }

    private func summary(_ linked: LinkedCase, heading: (number: String, title: String)) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.md) {
                IconTile(systemImage: "building.columns")
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text([linked.courtName ?? "", heading.number].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.brand(.body, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !heading.title.isEmpty {
                        Text(heading.title)
                            .font(.brand(.footnote))
                            .foregroundStyle(theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            let facts = model.linkedFacts
            ForEach(facts.indices, id: \.self) { index in
                ValueRow(facts[index].label, value: facts[index].value)
                    .font(.brand(.footnote))
            }
            Button {
                onOpenCase(linked.id)
            } label: {
                Label("Open the case record", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.compactSecondaryAction)
            .accessibilityIdentifier("matter-open-case")
        }
        .padding(Spacing.lg)
        .panel()
        .accessibilityIdentifier("matter-court-summary")
    }

    private func courtGroup(_ group: MatterWorkspaceViewModel.CourtGroup) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: group.title, detail: group.rows.isEmpty ? nil : "\(group.rows.count)")
            if group.rows.isEmpty {
                Text(group.empty)
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                RecordGroup {
                    ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { RecordDivider(inset: 14) }
                        courtRow(row)
                            .accessibilityIdentifier("matter-court-row-\(row.id)")
                    }
                }
            }
        }
    }

    private func courtRow(_ row: MatterWorkspaceViewModel.CourtRow) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                if !row.date.isEmpty {
                    Text(row.date)
                        .font(.brand(.caption, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                }
                if let rel = row.rel {
                    Text(rel)
                        .font(.brand(.caption, weight: .semibold))
                        .foregroundStyle(theme.accentText)
                }
                Spacer(minLength: 0)
                if let badge = row.badge {
                    StatusPill(text: badge, tone: Self.tone(row.badgeTone))
                }
            }
            Text(row.title)
                .font(.brand(.subheadline, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(row.lines, id: \.self) { line in
                Text(line)
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(row.rel != nil ? theme.accentSoft.opacity(0.5) : Color.clear)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var parties: some View {
        if let parties = model.courtParties {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: "Parties")
                side("Petitioner / Appellant side", names: parties.first, counsel: parties.firstCounsel)
                side("Respondent side", names: parties.second, counsel: parties.secondCounsel)
                if !parties.others.isEmpty {
                    side("Others", names: parties.others, counsel: [])
                }
            }
            .accessibilityIdentifier("matter-court-parties")
        }
    }

    private func side(_ title: String, names: [String], counsel: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .recordText(RecordTokens.Typography.label)
                .foregroundStyle(theme.textTertiary)
                .accessibilityAddTraits(.isHeader)
            if names.isEmpty, counsel.isEmpty {
                Text("Not on the record.")
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textFaint)
            }
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                Text("\(index + 1). \(name)")
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !counsel.isEmpty {
                Text("Counsel: \(counsel.joined(separator: ", "))")
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .panel()
    }

    static func tone(_ tone: MatterWorkspaceViewModel.BadgeTone) -> StatusPill.Tone {
        switch tone {
        case .neutral: return .neutral
        case .success: return .success
        case .warning: return .warning
        case .danger: return .danger
        }
    }
}
