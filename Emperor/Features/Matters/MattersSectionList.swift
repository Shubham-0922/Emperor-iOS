import SwiftUI

/// The matters at the head of Matters → All matters — the web's Matters column
/// (`src/pages/Projects.jsx`): a heading with the count in scope, the Status, Practice area and
/// Sort menus, the "hearings in the next 7 days" shortcut, then one row per matter. The search
/// field above it is shared with the tracked cases below, so one query narrows both.
///
/// While the user has no matters it draws only the way to make the first one, so an account with
/// only tracked cases sees the docket as before. A row's context menu edits, archives or deletes
/// its matter.
struct MattersSectionList: View {
    @Environment(\.theme) private var theme

    /// What a row's context menu asks for.
    enum RowAction { case edit, archive, delete }

    let model: MattersListViewModel
    let onOpen: (Project) -> Void
    /// New matter; nil leaves the button out.
    var onNew: (() -> Void)? = nil
    /// A row's context menu; nil leaves the menu out.
    var onAction: ((Project, RowAction) -> Void)? = nil

    var body: some View {
        if model.projects.isEmpty {
            if let failure = model.state.failure {
                failureLine(failure)
            } else if onNew != nil, model.state.hasLoaded {
                firstMatter
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: Spacing.sm) {
                    SectionHeader(title: "Matters", detail: model.summary)
                        .accessibilityIdentifier("matters-summary")
                    newButton
                }
                controls
                if let failure = model.state.failure {
                    failureLine(failure)
                }
                if let none = model.noMatches {
                    noMatches(none)
                } else {
                    rows
                }
            }
        }
    }

    // MARK: - New matter

    @ViewBuilder
    private var newButton: some View {
        if let onNew {
            Button(action: onNew) {
                Label("New matter", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
            .fixedSize()
            .accessibilityIdentifier("matters-new")
        }
    }

    /// No matters yet: what one is, and the button to make it.
    private var firstMatter: some View {
        AdaptiveStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Matters")
                    .font(.brand(.headline))
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("A matter keeps a case's record, tasks, fees and people in one place.")
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            newButton
        }
        .padding(Spacing.md)
        .panel()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("matters-first")
    }

    // MARK: - Controls

    private var controls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                statusMenu
                areaMenu
                sortMenu
                if model.hearingsThisWeek > 0 {
                    Button {
                        model.sort = .hearing
                    } label: {
                        ChipLabel(title: model.hearingsThisWeekText, systemImage: "calendar.badge.clock",
                                  isSelected: model.sort == .hearing)
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: model.sort == .hearing))
                    .accessibilityHint("Sorts by next hearing")
                    .accessibilityIdentifier("matters-hearings-week")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var statusMenu: some View {
        Menu {
            Picker("Status", selection: Binding(get: { model.status }, set: { model.status = $0 })) {
                ForEach(MattersListViewModel.StatusScope.allCases, id: \.self) { scope in
                    Text(model.statusLabel(scope)).tag(scope)
                }
            }
        } label: {
            MenuChip(title: model.statusLabel(model.status), systemImage: "circle.dashed",
                     isSelected: model.status != .active)
        }
        .accessibilityLabel("Status")
        .accessibilityValue(model.statusLabel(model.status))
        .accessibilityIdentifier("matters-status")
    }

    private var areaMenu: some View {
        Menu {
            Picker("Practice area", selection: Binding(get: { model.area }, set: { model.area = $0 })) {
                ForEach(model.areaOptions) { option in
                    Text(option.label).tag(option.key)
                }
            }
        } label: {
            MenuChip(title: model.areaLabel, systemImage: "tag", isSelected: model.area != nil)
        }
        .accessibilityLabel("Practice area")
        .accessibilityValue(model.areaLabel)
        .accessibilityIdentifier("matters-area")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: Binding(get: { model.sort }, set: { model.sort = $0 })) {
                ForEach(MattersListViewModel.Sort.allCases, id: \.self) { sort in
                    Text(sort.label).tag(sort)
                }
            }
        } label: {
            MenuChip(title: model.sort.label, systemImage: "arrow.up.arrow.down", isSelected: false)
        }
        .accessibilityLabel("Sort")
        .accessibilityValue(model.sort.label)
        .accessibilityIdentifier("matters-sort")
    }

    // MARK: - Rows

    private var rows: some View {
        RecordGroup {
            ForEach(Array(model.visible.enumerated()), id: \.element.id) { index, project in
                if index > 0 { RecordDivider(inset: 72) }
                Button {
                    onOpen(project)
                } label: {
                    MatterRow(
                        card: model.card(project), preset: project.bannerPreset,
                        imageData: model.bannerImage(for: project))
                }
                .buttonStyle(.recordRow)
                .contextMenu {
                    if let onAction {
                        MatterMenuItems(
                            isArchived: project.isArchived,
                            onEdit: { onAction(project, .edit) },
                            onArchive: { onAction(project, .archive) },
                            onDelete: { onAction(project, .delete) })
                    }
                }
                .accessibilityIdentifier("matter-\(project.id)")
                .accessibilityHint("Opens the matter")
                .task(id: MattersListViewModel.bannerKey(project)) {
                    await model.loadBanner(for: project)
                }
            }
        }
    }

    private func noMatches(_ none: MattersListViewModel.NoMatches) -> some View {
        EmptyStateContent(title: none.title, systemImage: "magnifyingglass", message: none.message, tone: .neutral) {
            if let clear = none.clearTitle {
                Button(clear) { model.clearFilters() }
                    .buttonStyle(.secondaryAction)
            }
            if let showAll = none.showAllTitle {
                Button(showAll) { model.showAllStatuses() }
                    .buttonStyle(.quietAction)
            }
        }
    }

    private func failureLine(_ failure: LoadFailure) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .accessibilityHidden(true)
            Text("Could not load your matters — \(failure.message)")
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if failure.isRetryable {
                Button("Try again") {
                    Task { await model.load() }
                }
                .buttonStyle(.quietAction)
            }
        }
        .font(.brand(.footnote))
        .foregroundStyle(theme.warning)
        .padding(Spacing.md)
        .background(Color(theme.palette.bannerWash), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// A menu's label drawn as a Record chip — the look of `ChipButtonStyle`, for a `Menu`, which
/// does not take a button style of its own.
private struct MenuChip: View {
    @Environment(\.theme) private var theme

    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        let weight: Font.Weight? = isSelected ? Font.Weight.semibold : Font.Weight.medium
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(theme.accentText)
                .accessibilityHidden(true)
            Text(title)
            Image(systemName: "chevron.down")
                .imageScale(.small)
                .accessibilityHidden(true)
        }
        .lineLimit(1)
        .font(.brand(.subheadline, weight: weight))
        .foregroundStyle(isSelected ? theme.accentText : theme.textSecondary)
        .padding(.horizontal, 14)
        .frame(minHeight: Layout.compactButtonHeight)
        .background(isSelected ? theme.accentSoft : theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(isSelected ? theme.accentLine : theme.borderStrong, lineWidth: 1))
        .frame(minHeight: Layout.touchTarget)
        .contentShape(Rectangle())
    }
}
