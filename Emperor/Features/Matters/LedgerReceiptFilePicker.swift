import SwiftUI

/// The receipt or challan a payment or expense points to — one of the matter's own files, Receipts
/// first (the web's `projectFileList`). Picking one stores its path on the entry; "None" clears it.
struct LedgerReceiptFilePicker: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let projectID: String
    /// The path stored now, "" for none.
    let current: String
    let onPick: (String) -> Void

    @State private var choices: [Ledger.ProjectFileRef]?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onPick("")
                        dismiss()
                    } label: {
                        row(title: "None", detail: nil, isOn: current.isEmpty)
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(theme.surface)

                Section {
                    if let failure {
                        Text(failure)
                            .font(.brand(.footnote))
                            .foregroundStyle(theme.danger)
                    } else if let choices {
                        if choices.isEmpty {
                            Text("This matter has no files yet. Attach the receipt from My Files in Files, then pick it here.")
                                .font(.brand(.footnote))
                                .foregroundStyle(theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(choices, id: \.path) { file in
                            Button {
                                onPick(file.path)
                                dismiss()
                            } label: {
                                row(title: DisplayText.fileName(file.name),
                                    detail: file.folder.isEmpty ? nil : MatterFilesViewModel.folderLabel(file.folder),
                                    isOn: file.path == current)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        ProgressView()
                    }
                } header: {
                    Text("This matter’s files")
                }
                .listRowBackground(theme.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.groupedBackground)
            .navigationTitle("Receipt or challan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            guard choices == nil else { return }
            do {
                choices = try await session.matterFiles.listing(projectID: projectID).receiptChoices
            } catch {
                failure = DisplayText.message(for: error)
            }
        }
    }

    private func row(title: String, detail: String?, isOn: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.brand(.body))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.brand(.caption))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
            if isOn {
                Image(systemName: "checkmark")
                    .foregroundStyle(theme.accentText)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: Layout.touchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
