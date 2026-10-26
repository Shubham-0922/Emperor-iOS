import SwiftUI

/// A sheet the workspace can open over a matter.
enum MatterSheet: Identifiable {
    /// Edit details, the cursor in `focus` (`client`, `side`, `practiceArea`…).
    case details(focus: String?)
    case delete
    /// A chronology entry: nil adds one.
    case entry(MatterRecord.Entry?)
    case task(ProjectTask?, kind: String)
    case ledger(LedgerEntry?, kind: String)
    case person(ProjectPerson?, role: String, name: String)
    case receipt(LedgerEntry)
    case listOfDates
    /// The court lookup, to link the case it finds.
    case linkCase

    var id: String {
        switch self {
        case .details(let focus): return "details-\(focus ?? "")"
        case .delete: return "delete"
        case .entry(let e): return "entry-\(e?.key ?? "new")"
        case .task(let t, let kind): return "task-\(t?.id ?? "new-\(kind)")"
        case .ledger(let e, let kind): return "ledger-\(e?.id ?? "new-\(kind)")"
        case .person(let p, let role, _): return "person-\(p?.id ?? "new-\(role)")"
        case .receipt(let e): return "receipt-\(e.id)"
        case .listOfDates: return "list-of-dates"
        case .linkCase: return "link-case"
        }
    }
}

/// What the sections need to change the matter: open a form, the one-tap writes, the court
/// actions, and a way to fetch the matter again and say how it went. Nil on a section draws it
/// read-only.
@MainActor
struct MatterEditActions {
    let open: @MainActor (MatterSheet) -> Void
    let quick: MatterQuickActions
    let court: MatterCourtActions
    /// Fetches the matter again after a write.
    let reload: @MainActor () async -> Void
    /// A confirmation for the toast.
    let done: @MainActor (String) -> Void
    /// A failure, for the alert.
    let failed: @MainActor (String) -> Void

    /// Runs a one-tap write, then reloads on success or reports why not.
    func run(
        _ success: String?, _ write: @escaping @MainActor () async -> Bool,
        error: @escaping @MainActor () -> String?
    ) {
        Task {
            if await write() {
                if let success { done(success) }
                await reload()
            } else if let message = error() {
                failed(message)
            }
        }
    }
}

/// A row's "…" — Edit and Delete — beside a combined row, so the row reads as one element and
/// its actions stay controls of their own. Delete asks first.
struct MatterRowMenu: View {
    @Environment(\.theme) private var theme

    /// What the row is, for the menu's spoken name: "Actions for File the rejoinder".
    let name: String
    let identifier: String
    var deleteTitle = "Delete"
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var confirming = false

    var body: some View {
        Menu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                confirming = true
            } label: {
                Label(deleteTitle, systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
                .frame(minWidth: Layout.touchTarget, minHeight: Layout.touchTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Actions for \(name)")
        .accessibilityIdentifier(identifier)
        .confirmationDialog("\(deleteTitle) “\(name)”?", isPresented: $confirming, titleVisibility: .visible) {
            Button(deleteTitle, role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        }
    }
}
