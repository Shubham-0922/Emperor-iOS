import SwiftUI

/// Step 2: the draft's annexures, in binding order — each with its mark, its source, original
/// pages or a typed copy, and the human check a typed copy needs. Marks are the server's and are
/// never renumbered; a binding order that departs from them is said out loud.
struct FilingAnnexureSection: View {
    @Environment(\.theme) private var theme

    let model: FilingAssemblyViewModel
    let isEditing: Bool
    let onToggleEditing: () -> Void
    let onAdd: () -> Void

    /// Asks for a new title; the parent holds the alert.
    let onRename: (FilingAnnexure) -> Void
    /// Asks before removing; the parent holds the confirmation.
    let onRemove: (FilingAnnexure) -> Void

    var body: some View {
        Section {
            content
            if let notice = model.notice {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .accessibilityHidden(true)
                    Text(notice)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.brand(.footnote))
                .foregroundStyle(theme.danger)
                .listRowBackground(theme.dangerBg)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("filing-notice")
            }
            Button(action: onAdd) {
                Label("Add annexure", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle(compact: true))
            .disabled(model.isAdding)
            .accessibilityIdentifier("filing-add-annexure")
        } header: {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "\(model.annexuresStep) · Annexures")
                Spacer(minLength: Spacing.sm)
                if model.canReorder, model.annexures.count > 1 {
                    Button(isEditing ? "Done reordering" : "Reorder", action: onToggleEditing)
                        .font(.brand(.footnote, weight: .semibold))
                        .foregroundStyle(theme.accentText)
                        .textCase(nil)
                        .accessibilityIdentifier("filing-reorder")
                }
            }
        } footer: {
            Text(FilingAssemblyViewModel.annexuresHint)
        }
    }

    /// Dragging into order, where the order can be changed.
    private var moveAction: ((IndexSet, Int) -> Void)? {
        guard model.canReorder else { return nil }
        let model = self.model
        return { source, destination in
            Task { await model.move(fromOffsets: source, toOffset: destination) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.annexures.isEmpty, model.annexState == .idle || model.annexState.isLoading {
            HStack(spacing: Spacing.sm) {
                ProgressView()
                Text("Loading annexures…")
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textSecondary)
            }
        } else if model.annexures.isEmpty, let failure = model.annexState.failure {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(failure.message)
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                if failure.isRetryable {
                    Button("Retry") { Task { await model.reloadAnnexures() } }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                }
            }
            .padding(.vertical, Spacing.xs)
        } else if model.annexures.isEmpty {
            Text(FilingAssemblyViewModel.noAnnexures)
                .font(.brand(.subheadline))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("filing-no-annexures")
        } else {
            if let warning = model.orderWarning {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .accessibilityHidden(true)
                    Text(warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.brand(.footnote))
                .foregroundStyle(theme.warning)
                .listRowBackground(theme.warnBg)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("filing-order-warning")
            }
            ForEach(model.annexures) { annexure in
                row(annexure)
            }
            .onMove(perform: moveAction)
        }
    }

    private func row(_ annexure: FilingAnnexure) -> some View {
        let index = model.annexures.firstIndex { $0.id == annexure.id } ?? 0
        let isFirst = index == 0
        let isLast = index == model.annexures.count - 1
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                StatusPill(text: annexure.mark, tone: .accent)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(annexure.title.isEmpty ? annexure.fileName : annexure.title)
                        .font(.brand(.body, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(annexure.caption)
                        .font(.brand(.caption))
                        .foregroundStyle(theme.textTertiary)
                        .dynamicLineLimit(2)
                    if let first = annexure.duplicateOf {
                        Text("Same pages as \(first)")
                            .font(.brand(.caption))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("filing-annexure-\(annexure.id)")

            if !isEditing {
                AdaptiveStack(spacing: Spacing.sm) {
                    RecordSegmentedControl(
                        label: "Treatment of \(annexure.mark)",
                        options: [
                            (value: FilingTreatment.append, title: FilingTreatment.append.title),
                            (value: FilingTreatment.typed, title: FilingTreatment.typed.title),
                        ],
                        selection: Binding(
                            get: { annexure.isTyped ? FilingTreatment.typed : FilingTreatment.append },
                            set: { treatment in
                                Task { await model.setTreatment(annexure, treatment) }
                            }))
                        .disabled(model.isMutating)
                        .accessibilityIdentifier("filing-treatment-\(annexure.id)")
                    if annexure.isTyped {
                        Button {
                            Task { await model.toggleVerify(annexure) }
                        } label: {
                            StatusPill(
                                text: annexure.isVerified ? "Verified" : "Verify pending",
                                tone: annexure.isVerified ? .success : .warning,
                                systemImage: annexure.isVerified
                                    ? "checkmark.shield" : "exclamationmark.shield")
                                .frame(minHeight: Layout.touchTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isMutating)
                        .accessibilityLabel(
                            annexure.isVerified
                                ? "\(annexure.mark) verified against the original"
                                : "\(annexure.mark) verify pending")
                        .accessibilityHint(
                            annexure.isVerified
                                ? "Reopens the check"
                                : "Marks this typed copy as checked against the original")
                        .accessibilityIdentifier("filing-verify-\(annexure.id)")
                    }
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .contextMenu {
            Button {
                onRename(annexure)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            if model.canReorder {
                Button {
                    Task { await model.moveUp(annexure) }
                } label: {
                    Label("Move up", systemImage: "arrow.up")
                }
                .disabled(isFirst)
                Button {
                    Task { await model.moveDown(annexure) }
                } label: {
                    Label("Move down", systemImage: "arrow.down")
                }
                .disabled(isLast)
            }
            Button(role: .destructive) {
                onRemove(annexure)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                onRemove(annexure)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}
