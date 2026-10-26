import SwiftUI

/// One document as a cover with its title under it — a shelf, a grid (`DocCard.jsx`,
/// `BookCard.jsx`). Opens what the document is: an Act page for an Act, the reading room for
/// anything else.
struct LibraryDocCard: View {
    @Environment(\.theme) private var theme

    let doc: LibraryDoc
    var width: CGFloat = 110
    /// A caption other than the document's own title — a volume inside its series.
    var title: String?
    var meta: [String]?

    var body: some View {
        NavigationLink(value: LibraryRoute.open(doc)) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                LibraryCoverView(doc: doc, width: width)
                Text(displayTitle)
                    .font(.brand(.footnote, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .dynamicLineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let line = metaLine {
                    Text(line)
                        .font(.brand(.caption2))
                        .foregroundStyle(theme.textTertiary)
                        .dynamicLineLimit(1)
                }
            }
            .frame(width: width, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("library-doc-\(doc.id)")
    }

    private var displayTitle: String {
        if let title { return title }
        switch doc.category {
        case LibraryCategoryKey.caseLaw.rawValue, LibraryCategoryKey.tribunals.rawValue:
            return LibraryDisplay.caseTitleText(doc)
        case LibraryCategoryKey.bareActs.rawValue:
            return LibraryDisplay.actTitle(doc)
        default:
            return LibraryDisplay.tidyTitle(doc)
        }
    }

    private var facts: [String] { meta ?? LibraryDisplay.docMeta(doc) }

    private var metaLine: String? {
        let f = facts
        return f.isEmpty ? nil : f.joined(separator: " · ")
    }

    private var accessibilityText: String {
        facts.isEmpty ? displayTitle : "\(displayTitle). \(facts.joined(separator: ", "))"
    }
}

/// One document as a row: a small cover, its title, its facts, and a passage when a search found
/// words inside it.
struct LibraryDocRow: View {
    @Environment(\.theme) private var theme

    let doc: LibraryDoc
    var title: String?
    var meta: [String]?
    /// A leading line above the title — a regulator's reference.
    var eyebrow: String?
    var snippet: LibrarySnippet?
    var badge: String?

    var body: some View {
        NavigationLink(value: LibraryRoute.open(doc)) {
            HStack(alignment: .top, spacing: Spacing.md) {
                LibraryCoverView(doc: doc, width: 44, showsImage: doc.category != LibraryCategoryKey.caseLaw.rawValue)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    if let eyebrow, !eyebrow.isEmpty {
                        Text(eyebrow)
                            .font(.brand(.caption, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                            .dynamicLineLimit(1)
                    }
                    Text(displayTitle)
                        .font(.brand(.subheadline, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .dynamicLineLimit(3)
                    if !facts.isEmpty || badge != nil {
                        HStack(spacing: Spacing.xs) {
                            if let badge { StatusPill(text: badge, tone: .neutral) }
                            if !facts.isEmpty {
                                Text(facts.joined(separator: " · "))
                                    .font(.brand(.caption))
                                    .foregroundStyle(theme.textTertiary)
                                    .dynamicLineLimit(2)
                            }
                        }
                    }
                    if let snippet {
                        LibrarySnippetText(snippet: snippet)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RowChevron()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: Layout.listRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(.recordRow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("library-doc-\(doc.id)")
    }

    private var displayTitle: String {
        if let title { return title }
        switch doc.category {
        case LibraryCategoryKey.caseLaw.rawValue, LibraryCategoryKey.tribunals.rawValue:
            return LibraryDisplay.caseTitleText(doc)
        case LibraryCategoryKey.bareActs.rawValue:
            return LibraryDisplay.actTitle(doc)
        default:
            return LibraryDisplay.tidyTitle(doc)
        }
    }

    private var facts: [String] { meta ?? LibraryDisplay.docMeta(doc) }

    private var accessibilityText: String {
        var parts = [displayTitle]
        if let eyebrow, !eyebrow.isEmpty { parts.insert(eyebrow, at: 0) }
        if !facts.isEmpty { parts.append(facts.joined(separator: ", ")) }
        if let text = snippet?.text, !text.isEmpty { parts.append(text) }
        return parts.joined(separator: ". ")
    }
}

/// A passage a body search found, the matched words in bold.
struct LibrarySnippetText: View {
    @Environment(\.theme) private var theme
    let snippet: LibrarySnippet

    var body: some View {
        Text(attributed)
            .font(.brand(.footnote))
            .foregroundStyle(theme.textSecondary)
            .dynamicLineLimit(3)
    }

    private var attributed: AttributedString {
        guard let text = snippet.text, !text.isEmpty else {
            return AttributedString("The words appear inside this judgment.")
        }
        var out = AttributedString((snippet.before == true ? "… " : "") + text + (snippet.after == true ? " …" : ""))
        if let term = snippet.term, term.count >= 2 {
            var searchFrom = out.startIndex
            while searchFrom < out.endIndex,
                  let range = out[searchFrom...].range(of: term, options: .caseInsensitive) {
                out[range].inlinePresentationIntent = .stronglyEmphasized
                searchFrom = range.upperBound
            }
        }
        return out
    }
}
