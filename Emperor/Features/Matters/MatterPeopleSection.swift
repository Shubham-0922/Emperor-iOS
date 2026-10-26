import SwiftUI

/// The workspace's People — the web's `PeopleSection`: the client, the other side, counsel on both
/// sides, the bench and witnesses, by role, each with what a clerk reaches for — a number that
/// dials, an address that opens the mail, the postal address. Each role adds its own; each person
/// can be edited or removed.
struct MatterPeopleSection: View {
    @Environment(\.theme) private var theme

    let model: MatterWorkspaceViewModel
    var edit: MatterEditActions? = nil

    var body: some View {
        let groups = model.peopleByRole
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if let edit {
                Button {
                    edit.open(.person(nil, role: groups.isEmpty ? "client" : "other",
                                      name: groups.isEmpty ? (model.project?.client ?? "") : ""))
                } label: {
                    Label("Add a person", systemImage: "plus")
                }
                .buttonStyle(.compactSecondaryAction)
                .accessibilityIdentifier("people-add")
            }
            if groups.isEmpty {
                EmptyStateContent(
                    title: "No people on this matter yet", systemImage: "person.2",
                    message: "Start with your client and the opposite party, then counsel on both sides, the bench and any witnesses. The client’s address goes on the fee receipt.",
                    tone: .neutral) {
                    if let edit {
                        Button("Add the opposite party") {
                            edit.open(.person(nil, role: "opposite_party", name: model.project?.oppositeParty ?? ""))
                        }
                        .buttonStyle(.secondaryAction)
                    }
                }
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        SectionHeader(title: group.role.label, detail: "\(group.people.count)")
                        if let edit {
                            Button {
                                edit.open(.person(nil, role: group.role.rawValue, name: ""))
                            } label: {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 18))
                                    .frame(minWidth: Layout.touchTarget, minHeight: Layout.touchTarget)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(theme.accentText)
                            .accessibilityLabel("Add \(group.role.label.lowercased())")
                            .accessibilityIdentifier("people-add-\(group.role.rawValue)")
                        }
                    }
                    RecordGroup {
                        ForEach(Array(group.people.enumerated()), id: \.element.id) { index, person in
                            if index > 0 { RecordDivider(inset: 14) }
                            HStack(alignment: .top, spacing: 0) {
                                personRow(person)
                                if let edit {
                                    MatterRowMenu(
                                        name: (person.name ?? "").isEmpty ? "Unnamed" : person.name!,
                                        identifier: "person-menu-\(person.id)", deleteTitle: "Remove",
                                        onEdit: { edit.open(.person(person, role: person.role ?? "other", name: "")) },
                                        onDelete: {
                                            edit.run("Removed", { await edit.quick.deletePerson(person.id) },
                                                     error: { edit.quick.error })
                                        })
                                        .padding(.trailing, Spacing.xs)
                                }
                            }
                            .accessibilityElement(children: .contain)
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
        // A container, so the row carries its identifier and each link stays its own control.
        .accessibilityElement(children: .contain)
    }
}
