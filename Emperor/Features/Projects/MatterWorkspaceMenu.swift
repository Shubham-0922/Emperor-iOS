import SwiftUI

/// The "More" menu in a matter workspace's bar, beside Add — the web's matter menu: Edit details,
/// Archive or Restore, and Delete. Every rule is `ProjectDetailViewModel`'s (`setArchived`,
/// `archiveActionTitle`, `deleteMatter`); this lays the three out.
struct MatterWorkspaceMenu: View {
    let model: ProjectDetailViewModel
    /// Opens Edit details for the matter as it was last read.
    let onEdit: (Project) -> Void
    /// Opens the typed-name confirmation (`MatterDeleteSheet`).
    let onDelete: () -> Void
    /// Told after an archive or a restore went through, so the list behind can read it again.
    let onChanged: () -> Void

    var body: some View {
        Menu {
            if let project = model.project {
                Button {
                    onEdit(project)
                } label: {
                    Label("Edit details", systemImage: "pencil")
                }
                .accessibilityIdentifier("matter-edit")
            }
            archiveButton
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete matter…", systemImage: "trash")
            }
            .accessibilityIdentifier("matter-delete")
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("matter-menu")
        .disabled(model.isWriting || model.project == nil)
    }

    private var archiveButton: some View {
        let archiving = !model.isArchived
        let symbol = archiving ? "archivebox" : "tray.and.arrow.up"
        return Button {
            Task {
                if await model.setArchived(archiving) { onChanged() }
            }
        } label: {
            Label(model.archiveActionTitle, systemImage: symbol)
        }
        .accessibilityIdentifier("matter-archive")
    }
}

/// Edit details, opened from `MatterWorkspaceMenu` — the same `EditMatterSheet` the matter list
/// opens from a row's long press, followed by a re-read of the workspace.
struct MatterEditPresenter: ViewModifier {
    let model: ProjectDetailViewModel
    @Binding var editing: Project?
    @Binding var toast: String?
    let onChanged: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $editing) { project in
                EditMatterSheet(project: project) { _, message in
                    toast = message
                    Task { await model.load() }
                    onChanged()
                }
                .pageSizedSheet()
            }
    }
}
