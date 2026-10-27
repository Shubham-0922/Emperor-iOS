import SwiftUI

/// The workspace's Chronology — the web's `ChronologySection`: the matter's own record and the
/// linked case's hearings and orders as one list (a court fact the server copied into the record
/// is not shown twice), each entry badged with who put it there: You, the Court or AI. The user's
/// own entries can be edited and deleted; the court's are read-only. The list goes out as a List
/// of Dates.
struct MatterChronologySection: View {
    @Environment(\.theme) private var theme

    let model: MatterWorkspaceViewModel
    var edit: MatterEditActions? = nil

    @State private var isBuilding = false

    var body: some View {
        @Bindable var bindable = model
        let entries = model.chronology(newestFirst: model.newestFirst)
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let edit {
                HStack(spacing: Spacing.sm) {
                    Button {
                        edit.open(.entry(nil))
                    } label: {
                        Label("Add entry", systemImage: "plus")
                    }
                    .buttonStyle(.compactSecondaryAction)
                    .accessibilityIdentifier("chronology-add")
                    if !entries.isEmpty {
                        Button {
                            edit.open(.listOfDates)
                        } label: {
                            Label("List of Dates", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.quietAction)
                        .accessibilityHint("A PDF of the dates and events, to share or print")
                        .accessibilityIdentifier("chronology-list-of-dates")
                    }
                }
                // Its own line: three actions do not fit beside each other on a phone.
                Button {
                    isBuilding = true
                } label: {
                    Label("Build from documents", systemImage: "sparkles")
                }
                .buttonStyle(.quietAction)
                .accessibilityHint("Emperor reads this matter’s documents and proposes the dated events in them")
                .accessibilityIdentifier("chronology-build")
            }
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
                        HStack(alignment: .top, spacing: 0) {
                            row(entry)
                            if let edit, entry.own {
                                MatterRowMenu(
                                    name: entry.title.isEmpty ? MatterRecord.kindLabel(entry.kind) : entry.title,
                                    identifier: "entry-menu-\(entry.id)",
                                    onEdit: { edit.open(.entry(entry)) },
                                    onDelete: {
                                        edit.run("Entry deleted", { await edit.quick.deleteUpdate(entry.id) },
                                                 error: { edit.quick.error })
                                    })
                                    .padding(.trailing, Spacing.xs)
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("matter-entry-\(entry.key)")
                    }
                }
            }
        }
        .sheet(isPresented: $isBuilding) {
            ChronologyExtractSheet(projectID: model.projectID, existing: entries) { message in
                edit?.done(message)
                Task { await edit?.reload() }
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
