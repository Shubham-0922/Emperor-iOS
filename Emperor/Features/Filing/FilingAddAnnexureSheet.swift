import SwiftUI

/// A PDF from My Files, added as the draft's next annexure. Only PDFs: an annexure's pages go
/// into the bundle as they are, or are retyped from its text.
struct FilingAddAnnexureSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    let model: FilingAssemblyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecordSheetHeader(title: "Add annexure from your files", onClose: { dismiss() })
            RecordSearchField(
                text: Binding(get: { model.fileQuery }, set: { model.fileQuery = $0 }),
                prompt: "Search your PDFs…")
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.sm)
            List {
                content
                if let notice = model.notice {
                    Text(notice)
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowBackground(theme.dangerBg)
                        .accessibilityIdentifier("filing-add-notice")
                }
                Section {
                } footer: {
                    Text(FilingAssemblyViewModel.addFootnote)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("filing-add-list")
        }
        .background(theme.groupedBackground.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Radius.sheet)
        .task { await model.loadFiles() }
    }

    @ViewBuilder
    private var content: some View {
        if model.pdfFiles.isEmpty, model.filesState == .idle || model.filesState.isLoading {
            HStack(spacing: Spacing.sm) {
                ProgressView()
                Text("Loading your files…")
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textSecondary)
            }
        } else if model.pdfFiles.isEmpty, let failure = model.filesState.failure {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(failure.message)
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                if failure.isRetryable {
                    Button("Retry") { Task { await model.loadFiles() } }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                }
            }
        } else if model.pdfFiles.isEmpty {
            Text(FilingAssemblyViewModel.noPDFs)
                .font(.brand(.subheadline))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if model.filteredFiles.isEmpty {
            Text("No PDFs match “\(model.fileQuery)”.")
                .font(.brand(.subheadline))
                .foregroundStyle(theme.textSecondary)
        } else {
            ForEach(model.filteredFiles, id: \.path) { file in
                HStack(spacing: Spacing.md) {
                    IconTile(systemImage: "doc.text", size: .small)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(file.name)
                            .font(.brand(.body, weight: .medium))
                            .foregroundStyle(theme.textPrimary)
                            .dynamicLineLimit(2)
                        Text(file.folderPath.isEmpty ? "My Files" : file.folderPath)
                            .font(.brand(.caption))
                            .foregroundStyle(theme.textTertiary)
                            .dynamicLineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: Spacing.sm)
                    Button {
                        Task {
                            if await model.add(file) { dismiss() }
                        }
                    } label: {
                        if model.isAdding {
                            ProgressView()
                        } else {
                            Text("Add")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
                    .disabled(model.isAdding)
                    .accessibilityLabel("Add \(file.name)")
                    .accessibilityIdentifier("filing-file-\(file.name)")
                }
            }
        }
    }
}
