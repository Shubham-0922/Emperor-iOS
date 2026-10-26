import SwiftUI

/// The Library's front room: one shelf per collection, in the web's order, each loaded as it
/// comes on screen (`LibraryHome.jsx`, `Shelf.jsx`).
struct LibraryHomeView: View {
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass

    let model: LibraryHomeViewModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.xxl) {
            ForEach(model.shelfKeys, id: \.self) { key in
                if let category = model.category(key) {
                    shelf(category)
                }
            }
        }
        .padding(.top, Spacing.md)
    }

    private var coverWidth: CGFloat { sizeClass == .regular ? 132 : 104 }

    private func shelf(_ category: LibraryCategory) -> some View {
        let theme = LibraryDisplay.theme(category.key)
        let state = model.shelf(category.key)
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: Spacing.sm) {
                    SectionHeader(
                        title: category.displayLabel,
                        detail: category.count.map { LibraryDisplay.fmtCount($0) })
                    NavigationLink(value: LibraryRoute.collection(category, query: "", inText: false)) {
                        Text("See all")
                    }
                    .buttonStyle(.quietAction)
                    .accessibilityLabel("See all \(category.displayLabel)")
                    .accessibilityIdentifier("library-see-all-\(category.key)")
                }
                if !theme.blurb.isEmpty {
                    Text(theme.blurb)
                        .font(.brand(.footnote))
                        .foregroundStyle(self.theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Spacing.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Spacing.md) {
                    if state.items.isEmpty, state.state.failure == nil {
                        ForEach(0..<5, id: \.self) { _ in placeholder }
                    }
                    ForEach(state.items) { doc in
                        LibraryDocCard(doc: doc, width: coverWidth)
                    }
                }
                .padding(.horizontal, Spacing.gutter)
            }
            if state.state.failure != nil {
                Button("This shelf could not be loaded. Try again") {
                    Task { await model.loadShelf(category.key) }
                }
                .buttonStyle(.quietAction)
                .padding(.horizontal, Spacing.gutter)
            } else if state.state.hasLoaded, state.items.isEmpty {
                Text("Nothing on this shelf yet.")
                    .font(.brand(.footnote))
                    .foregroundStyle(self.theme.textTertiary)
                    .padding(.horizontal, Spacing.gutter)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-shelf-\(category.key)")
        .task { await model.loadShelf(category.key) }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(theme.surface2)
            .frame(width: coverWidth, height: coverWidth * 4 / 3)
            .accessibilityHidden(true)
    }
}
