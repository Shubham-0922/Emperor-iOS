import SwiftUI

/// The intake: documents picked from My Files, an optional note, and the one button
/// (`AnalysisKit.jsx`, `Intake`). Tools never take uploads — a document is read and indexed in
/// My Files first, and picked there.
struct AnalysisIntakeView: View {
    let model: AnalysisRunModel

    @Environment(\.theme) private var theme
    @State private var isPicking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SerifHeader(
                eyebrow: model.kind.aka.map { "Also called \($0)" },
                title: model.kind.title,
                subtitle: model.kind.tagline)
            documentsStep
            referenceStep
            runButton
        }
        .sheet(isPresented: $isPicking) {
            FileLibraryView(alreadyAttached: model.files) { chosen in
                model.setFiles(chosen)
            }
        }
    }

    // MARK: - Step 1

    private var documentsStep: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            AnalysisStepHeading(number: 1, title: "Choose your documents", optional: false)
            RecordGroup {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        IconTile(systemImage: "folder")
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Pick them from My Files")
                                .font(.brand(.subheadline, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)
                            Text("Documents are read and indexed in My Files first, so tools never take uploads directly.")
                                .font(.brand(.footnote))
                                .foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    chooseButton
                }
                .padding(14)
            }
            if !model.files.isEmpty {
                RecordGroup {
                    ForEach(Array(model.files.enumerated()), id: \.element) { index, file in
                        if index > 0 { RecordDivider() }
                        chosenRow(file)
                    }
                }
            }
            if !model.refusedFiles.isEmpty {
                refusedList
            }
        }
    }

    @ViewBuilder
    private var chooseButton: some View {
        let button = Button {
            isPicking = true
        } label: {
            Label("Choose from My Files", systemImage: "folder")
                .frame(maxWidth: .infinity)
        }
        .disabled(model.isRunning)
        .accessibilityIdentifier("analysis-choose-files")
        // The primary action until documents are chosen; then the run is.
        if model.files.isEmpty {
            button.buttonStyle(PrimaryButtonStyle())
        } else {
            button.buttonStyle(SecondaryButtonStyle())
        }
    }

    private func chosenRow(_ file: ChatAttachment) -> some View {
        RecordRow(
            title: DisplayText.attachmentTitle(file),
            subtitle: file.folderName.map { "In \($0)" },
            leading: { DocumentTile(kind: (file.name as NSString).pathExtension.isEmpty ? "DOC" : (file.name as NSString).pathExtension) },
            trailing: {
                Button {
                    model.remove(file)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.textTertiary)
                        .frame(minWidth: Layout.touchTarget, minHeight: Layout.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(file.name)")
                .accessibilityIdentifier("analysis-remove-\(file.name)")
            })
    }

    private var refusedList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(model.refusedFiles) { refused in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(theme.warning)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DisplayText.attachmentTitle(refused.file))
                            .font(.brand(.footnote, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text(refused.reason)
                            .font(.brand(.footnote))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.warnBg, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityIdentifier("analysis-refused-files")
    }

    // MARK: - Step 2

    private var referenceStep: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            AnalysisStepHeading(number: 2, title: model.kind.referenceLabel, optional: true)
            TextField(
                model.kind.referencePlaceholder,
                text: Binding(get: { model.reference }, set: { model.reference = $0 }),
                prompt: Text(model.kind.referencePlaceholder).foregroundStyle(theme.textTertiary),
                axis: .vertical)
                .lineLimit(3...8)
                .font(.brand(.body))
                .foregroundStyle(theme.textPrimary)
                .padding(12)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(theme.borderStrong, lineWidth: 1))
                .disabled(model.isRunning)
                .accessibilityLabel(model.kind.referenceLabel)
                .accessibilityIdentifier("analysis-reference")
            HStack(alignment: .firstTextBaseline) {
                Text(model.kind.referenceHint)
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.sm)
                if let counter = AnalysisInput.referenceCounter(model.reference) {
                    Text(counter)
                        .font(.brand(.caption, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(AnalysisInput.isReferenceTooLong(model.reference) ? theme.danger : theme.textSecondary)
                }
            }
        }
    }

    // MARK: - The button

    private var runButton: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                model.run()
            } label: {
                Label(model.kind.cta, systemImage: model.kind.systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.canRun)
            .accessibilityIdentifier("analysis-run")
            Text(model.ctaNote)
                .font(.brand(.footnote))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("analysis-cta-note")
        }
    }
}

/// "① Choose your documents", with "optional" beside a step that is.
struct AnalysisStepHeading: View {
    let number: Int
    let title: String
    let optional: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text("\(number)")
                .font(.brand(.caption, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .frame(minWidth: 22, minHeight: 22)
                .background(theme.accentSoft, in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.brand(.headline))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if optional {
                Text("optional")
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Step \(number): \(title)\(optional ? ", optional" : "")")
    }
}
