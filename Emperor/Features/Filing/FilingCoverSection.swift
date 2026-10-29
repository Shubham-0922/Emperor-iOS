import SwiftUI

/// Step 3: the cover page's details, and Assemble.
///
/// The forum is free text with the web's suggestions beside it. Assemble stays off for a forum
/// the assembler cannot make a cover for, and says why.
struct FilingCoverSection: View {
    @Environment(\.theme) private var theme

    let model: FilingAssemblyViewModel

    var body: some View {
        Section {
            forumField
            field("Case type", prompt: "e.g. CP (IB)", text: binding(\.caseType), id: "filing-case-type")
            field("Case number", prompt: "e.g. 123/2026", text: binding(\.caseNumber), id: "filing-case-number")
            field(
                "Filing type", prompt: "e.g. Petition, Appeal, Reply", text: binding(\.filingType),
                id: "filing-filing-type")
            VStack(alignment: .leading, spacing: Spacing.xs) {
                fieldTitle("Parties", required: false)
                TextField(
                    "Parties",
                    text: binding(\.parties),
                    prompt: Text("e.g. ABC Pvt. Ltd. …Petitioner versus XYZ Ltd. …Respondent")
                        .foregroundStyle(theme.textTertiary),
                    axis: .vertical)
                    .lineLimit(2...6)
                    .font(.brand(.body))
                    .foregroundStyle(theme.textPrimary)
                    .disabled(model.isAssembling)
                    .accessibilityIdentifier("filing-parties")
            }
            .padding(.vertical, Spacing.xs)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Button {
                    Task { await model.assemble() }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        if model.isAssembling { ProgressView().tint(theme.onAccent) }
                        Text(model.isAssembling ? "Assembling… this can take a minute" : "Assemble bundle")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.canAssemble)
                .accessibilityIdentifier("filing-assemble")

                if let hint = model.assembleHint {
                    Text(hint)
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("filing-assemble-hint")
                }
                if let pending = model.pendingTypedText {
                    StatusPill(text: pending, tone: .warning, systemImage: "exclamationmark.shield")
                }
            }
            .padding(.vertical, Spacing.xs)
        } header: {
            SectionHeader(title: "\(model.coverStep) · Cover page details")
        } footer: {
            Text(FilingAssemblyViewModel.coverHint)
        }
    }

    private var forumField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            fieldTitle("Forum", required: true)
            HStack(spacing: Spacing.sm) {
                TextField(
                    "Forum", text: binding(\.forum),
                    prompt: Text("e.g. NCLT, High Court, Data Protection Board…")
                        .foregroundStyle(theme.textTertiary))
                    .font(.brand(.body))
                    .foregroundStyle(theme.textPrimary)
                    .autocorrectionDisabled()
                    .disabled(model.isAssembling)
                    .accessibilityIdentifier("filing-forum")
                Menu {
                    ForEach(FilingForum.suggestions, id: \.self) { suggestion in
                        Button(suggestion) { model.cover.forum = suggestion }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(theme.accentText)
                        .frame(minWidth: Layout.touchTarget, minHeight: Layout.touchTarget)
                        .contentShape(Rectangle())
                }
                .disabled(model.isAssembling)
                .accessibilityLabel("Forum suggestions")
                .accessibilityIdentifier("filing-forum-suggestions")
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private func field(
        _ title: String, prompt: String, text: Binding<String>, id: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            fieldTitle(title, required: false)
            TextField(title, text: text, prompt: Text(prompt).foregroundStyle(theme.textTertiary))
                .font(.brand(.body))
                .foregroundStyle(theme.textPrimary)
                .autocorrectionDisabled()
                .disabled(model.isAssembling)
                .accessibilityIdentifier(id)
        }
        .padding(.vertical, Spacing.xs)
    }

    private func fieldTitle(_ title: String, required: Bool) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(title)
                .font(.brand(.subheadline, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            if required {
                Text("Required")
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func binding(_ key: WritableKeyPath<FilingCover, String>) -> Binding<String> {
        Binding(
            get: { model.cover[keyPath: key] },
            set: { model.cover[keyPath: key] = $0 })
    }
}
