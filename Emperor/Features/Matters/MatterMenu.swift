import SwiftUI

/// What a matter's menu offers (`ProjectMenu`, `ProjectCard.jsx`): Edit, Archive or Unarchive,
/// and Delete…. The same items sit in the workspace's bar (`MatterMenu`) and in a row's context
/// menu on All matters.
struct MatterMenuItems: View {
    let isArchived: Bool
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onEdit) {
            Label("Edit details", systemImage: "pencil")
        }
        .accessibilityIdentifier("matter-edit")
        Button(action: onArchive) {
            Label(isArchived ? "Unarchive" : "Archive", systemImage: isArchived ? "tray.and.arrow.up" : "archivebox")
        }
        .accessibilityIdentifier("matter-archive")
        Divider()
        Button(role: .destructive, action: onDelete) {
            Label("Delete…", systemImage: "trash")
        }
        .accessibilityIdentifier("matter-delete")
    }
}

/// The workspace bar's "…" menu.
struct MatterMenu: View {
    let isArchived: Bool
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            MatterMenuItems(isArchived: isArchived, onEdit: onEdit, onArchive: onArchive, onDelete: onDelete)
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(minWidth: Layout.touchTarget, minHeight: Layout.touchTarget)
        }
        .accessibilityLabel("Matter actions")
        .accessibilityIdentifier("matter-menu")
    }
}
