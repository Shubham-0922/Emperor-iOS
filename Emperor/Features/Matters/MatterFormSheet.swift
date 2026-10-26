import SwiftUI

/// The frame every matter form sits in: the sheet's head with its ×, the form, the error the form
/// refused with, and Cancel beside the form's one action at the foot. The action shows its wait
/// and is disabled while it runs, so a second tap cannot send the same write twice; the sheet
/// cannot be swiped away mid-save either, so nobody is left unsure whether it happened.
struct MatterFormSheet<Content: View>: View {
    @Environment(\.theme) private var theme

    let title: String
    var subtitle: String?
    let actionTitle: String
    /// The action's identifier, for UI tests.
    let actionID: String
    var isSaving = false
    /// What the save is doing now — "Uploading the banner…".
    var busy: String?
    var error: String?
    var destructive = false
    var actionDisabled = false
    let onCancel: () -> Void
    let onAction: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            RecordSheetHeader(title: title, subtitle: subtitle, onClose: onCancel)
            Form {
                content()
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.brand(.footnote))
                            .foregroundStyle(theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("matter-form-error")
                    }
                    .listRowBackground(theme.surface)
                }
            }
            .font(.brand(.body))
            .scrollContentBackground(.hidden)
            footer
        }
        .background(theme.groupedBackground.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Radius.sheet)
        .interactiveDismissDisabled(isSaving)
        .onChange(of: error) { _, message in
            if let message { VoiceOver.announce(message) }
        }
    }

    private var footer: some View {
        VStack(spacing: Spacing.xs) {
            if let busy {
                Text(busy)
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            HStack(spacing: Spacing.sm) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.secondaryAction)
                    .disabled(isSaving)
                actionButton
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.md)
        .background(theme.chrome)
    }

    @ViewBuilder
    private var actionButton: some View {
        let button = Button(action: onAction) {
            HStack(spacing: Spacing.sm) {
                if isSaving {
                    ProgressView().controlSize(.small)
                }
                Text(actionTitle)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(isSaving || actionDisabled)
        .accessibilityIdentifier(actionID)
        if destructive {
            button.buttonStyle(DestructiveButtonStyle())
        } else {
            button.buttonStyle(PrimaryButtonStyle())
        }
    }
}

/// A row's label over its field, as the form rows read: the caption above, the control under it.
struct MatterField<Field: View>: View {
    @Environment(\.theme) private var theme

    let label: String
    @ViewBuilder var field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .recordText(RecordTokens.Typography.label)
                .foregroundStyle(theme.textTertiary)
                .accessibilityHidden(true)
            field()
                .accessibilityLabel(label)
        }
        .padding(.vertical, 2)
    }
}

/// A day picked or cleared: "No date" with Set, or a date picker with Clear. The value is the
/// `YYYY-MM-DD` key the server takes, in India — never the device's zone.
struct MatterDayField: View {
    @Environment(\.theme) private var theme

    let label: String
    @Binding var day: String
    var allowsClear = true

    var body: some View {
        if let date = WireDate.parseDay(day) {
            HStack {
                DatePicker(label, selection: Binding(
                    get: { date },
                    set: { day = WireDate.dayKey($0) }), displayedComponents: .date)
                    .environment(\.timeZone, TimeZone(identifier: "Asia/Kolkata") ?? .current)
                if allowsClear {
                    Button("Clear") { day = "" }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Clear \(label.lowercased())")
                }
            }
        } else {
            HStack {
                Text(label)
                Spacer()
                Button("Set date") { day = WireDate.dayKey(Date()) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Set \(label.lowercased())")
            }
        }
    }
}
