import SwiftUI

/// The workspace's sections as a row of chips that scrolls sideways — the web's section nav.
/// A chip carries a count of what is waiting there, never a total for its own sake: open tasks
/// (marked when one is overdue), entries on the record, people, chats; Court a link mark when a
/// case is linked.
struct MatterSectionBar: View {
    @Environment(\.theme) private var theme

    let sections: [MatterVocabulary.MatterSection]
    let counts: [MatterVocabulary.MatterSection: MatterWorkspaceViewModel.NavCount]
    @Binding var selection: MatterVocabulary.MatterSection

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(sections, id: \.self) { section in
                        chip(section)
                            .id(section)
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: selection) { _, chosen in
                withAnimation(Motion.easeOut(Motion.Duration.fade)) {
                    proxy.scrollTo(chosen, anchor: .center)
                }
            }
        }
    }

    private func chip(_ section: MatterVocabulary.MatterSection) -> some View {
        let isSelected = selection == section
        let count = counts[section]
        let image: String? = count?.danger == true ? "exclamationmark.circle"
            : count?.dot == true ? "link" : nil
        return Button {
            selection = section
        } label: {
            ChipLabel(title: section.label, systemImage: image, count: count?.count, isSelected: isSelected)
        }
        .buttonStyle(ChipButtonStyle(isSelected: isSelected))
        .accessibilityLabel(spoken(section, count))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("matter-section-\(section.rawValue)")
    }

    private func spoken(_ section: MatterVocabulary.MatterSection, _ count: MatterWorkspaceViewModel.NavCount?) -> String {
        var parts = [section.label]
        if let n = count?.count { parts.append("\(n)") }
        if count?.danger == true { parts.append("one or more overdue") }
        if count?.dot == true { parts.append("linked to a court case") }
        return parts.joined(separator: ", ")
    }
}
