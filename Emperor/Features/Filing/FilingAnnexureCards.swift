import SwiftUI

/// The List of Annexures under a drafted document in a conversation — every annexure the draft
/// cites, read from the register — each card opening that one annexure (`ToolWorkspace.jsx`,
/// `AnnexuresCard`). Nothing is drawn when the conversation has none, or the register cannot be
/// read.
struct FilingAnnexureCards: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session

    let chatID: String

    @State private var model: FilingAnnexureCardsModel?
    @State private var opened: FilingAnnexure?

    var body: some View {
        // A stack, not a `Group`: a group hands its modifiers to its children, and with nothing
        // loaded yet it has none, so the `.task` that loads the cards would never run.
        VStack(alignment: .leading, spacing: 0) {
            if let model, !model.rows.isEmpty {
                cards(model.rows)
            }
        }
        .task(id: chatID) {
            let created = FilingAnnexureCardsModel(service: session.filing, chatID: chatID)
            await created.load()
            model = created
        }
        .sheet(item: $opened) { annexure in
            FilingAnnexureViewer(chatID: chatID, annexure: annexure)
        }
    }

    private func cards(_ rows: [FilingAnnexure]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(FilingAnnexureCardsModel.title)
                .font(.brand(.subheadline, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(FilingAnnexureCardsModel.caption)
                .font(.brand(.caption))
                .foregroundStyle(theme.accentText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.accentWash, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            RecordGroup {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, annexure in
                    if index > 0 {
                        RecordDivider(inset: 14)
                    }
                    card(annexure)
                }
            }
        }
        // A container of its own: an identifier on a plain stack is handed down to its
        // children, and would replace each card's `filing-annexure-card-<mark>`.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filing-annexure-cards")
    }

    private func card(_ annexure: FilingAnnexure) -> some View {
        let parts: [String?] = [
            "Annexure \(annexure.mark)", annexure.title, annexure.duplicateNote, annexure.cardForm,
        ]
        let spoken: String = parts.compactMap { $0 }.joined(separator: ", ")
        return Button {
            opened = annexure
        } label: {
            HStack(spacing: Spacing.sm) {
                Text(annexure.mark)
                    .font(.brand(.footnote, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .frame(minWidth: 46, alignment: .leading)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(annexure.title)
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textPrimary)
                        .dynamicLineLimit(2)
                    if let note = annexure.duplicateNote {
                        StatusPill(text: note, tone: .warning, systemImage: "exclamationmark.triangle")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(annexure.cardForm)
                    .font(.brand(.caption))
                    .italic()
                    .foregroundStyle(theme.textTertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: Layout.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.recordRow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Opens this annexure")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("filing-annexure-card-\(annexure.mark)")
    }
}

/// "Documents attached to this chat": the conversation's files that are not yet annexures, each
/// one tap from being the next (`FilingAssembly.jsx`, its smart seed). Nothing is added without
/// that tap.
struct FilingSeedSection: View {
    @Environment(\.theme) private var theme

    let model: FilingAssemblyViewModel
    /// Told the annexure a tap has just made, so the screen can bring it on screen: it lands in
    /// the list above, which may be scrolled out of sight.
    var onAdded: (FilingAnnexure) -> Void = { _ in }

    var body: some View {
        Section {
            ForEach(model.seedFiles, id: \.self) { file in
                seedRow(file)
            }
        } header: {
            SectionHeader(title: FilingChatScope.seedTitle)
        }
    }

    /// One chip per row, the row being the chip: there is nothing else in it to tap.
    private func seedRow(_ file: ChatAttachment) -> some View {
        let name = DisplayText.fileName(file.name)
        // The chip at its own width, the rest of the row empty: the chip's frame is then the
        // control's, wherever the row ends on a wide screen.
        return HStack(spacing: 0) {
            Button {
                Task { await add(file) }
            } label: {
                ChipLabel(title: name, systemImage: "plus", isSelected: false)
            }
            .buttonStyle(ChipButtonStyle(isSelected: false))
            .disabled(model.isAdding)
            .accessibilityLabel("Add \(name) as an annexure")
            .accessibilityIdentifier("filing-seed-\(file.name)")
            Spacer(minLength: 0)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: Spacing.xxs, leading: 0, bottom: Spacing.xxs, trailing: 0))
    }

    private func add(_ file: ChatAttachment) async {
        guard await model.addSeed(file) else { return }
        let suffix = "/" + file.name
        if let added = model.annexures.last(where: { $0.sourceFilePath.hasSuffix(suffix) }) {
            onAdded(added)
        }
    }
}
