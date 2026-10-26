import SwiftUI

/// The workspace's People — the web's `PeopleSection` read-only: the client, the other side,
/// counsel on both sides, the bench and witnesses, by role, each with what a clerk reaches for —
/// a number that dials, an address that opens the mail, the postal address.
struct MatterPeopleSection: View {
    @Environment(\.theme) private var theme

    let model: MatterWorkspaceViewModel

    var body: some View {
        let groups = model.peopleByRole
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if groups.isEmpty {
                EmptyStateContent(
                    title: "No people on this matter yet", systemImage: "person.2",
                    message: "The client, the other side, counsel, the bench and witnesses added on the web appear here.",
                    tone: .neutral) {}
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SectionHeader(title: group.role.label, detail: "\(group.people.count)")
                    RecordGroup {
                        ForEach(Array(group.people.enumerated()), id: \.element.id) { index, person in
                            if index > 0 { RecordDivider(inset: 14) }
                            personRow(person)
                                .accessibilityIdentifier("matter-person-\(person.id)")
                        }
                    }
                }
            }
        }
    }

    private func personRow(_ person: ProjectPerson) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text((person.name ?? "").isEmpty ? "Unnamed" : person.name!)
                .font(.brand(.body, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let tel = MatterWorkspaceViewModel.telLink(person.phone), let url = URL(string: tel) {
                Link(destination: url) {
                    Label(MatterWorkspaceViewModel.phoneShown(person.phone), systemImage: "phone")
                }
                .font(.brand(.subheadline))
                .foregroundStyle(theme.accentText)
                .frame(minHeight: Layout.touchTarget)
                .accessibilityHint("Calls this number")
            }
            if let mail = MatterWorkspaceViewModel.mailLink(person.email), let url = URL(string: mail) {
                Link(destination: url) {
                    Label(person.email ?? "", systemImage: "envelope")
                }
                .font(.brand(.subheadline))
                .foregroundStyle(theme.accentText)
                .frame(minHeight: Layout.touchTarget)
                .accessibilityHint("Writes an email")
            } else if let email = person.email, !email.isEmpty {
                Label(email, systemImage: "envelope")
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textSecondary)
            }
            if let address = person.address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty {
                Label(address, systemImage: "mappin.and.ellipse")
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notes = person.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                Text(notes)
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
