import SwiftUI

/// "Documents attached to this chat": the conversation's files that are not yet annexures, each
/// one tap from being the next (`FilingAssembly.jsx`, its smart seed). Nothing is added without
/// that tap.
struct FilingSeedSection: View {
    @Environment(\.theme) private var theme

    let model: FilingAssemblyViewModel
    /// Told the annexure a tap has just made, so the screen can bring it on screen: it lands in
    /// the list above, which may be scrolled out of sight.
    var onAdded: (AssemblyAnnexure) -> Void = { _ in }

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
