import SwiftUI

/// A Word document the server could not convert, shown as the text read out of it at upload —
/// the web's `ExtractedTextPane`. See `ExtractedText` for the two rules it keeps: the
/// extractor's own page numbers, and a banner that says this is not the original.
///
/// Never kept for reading offline: it is a stand-in, and the original is what a copy should be.
struct ExtractedTextView: View {
    @Environment(\.theme) private var theme

    let response: FileTextResponse
    let notice: String

    var body: some View {
        if let empty = ExtractedText.emptyState(for: response) {
            emptyView(empty)
        } else {
            VStack(spacing: 0) {
                banner
                pageIndex
                DocumentWebView(html: ExtractedText.joinedHTML(from: response))
                    .background(theme.surface2)
            }
        }
    }

    private func emptyView(_ empty: ExtractedText.EmptyState) -> some View {
        let isGone: Bool = empty == .gone
        let symbol: String = isGone ? "exclamationmark.triangle" : "clock"
        let tone: IconCircle.Tone = isGone ? .warning : .neutral
        return EmptyStateView(empty.title, systemImage: symbol, message: empty.message, tone: tone)
    }

    private var banner: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(theme.warning)
                .accessibilityHidden(true)
            Text(notice)
                .font(.brand(.footnote))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(theme.warnBg)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("file-text-banner")
    }

    /// The pages as the extractor numbered them — where the boundaries in the text below are,
    /// for a reader who cannot see the labels inside the page.
    private var pageIndex: some View {
        let sections = ExtractedText.sections(from: response)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(sections, id: \.page) { section in
                    StatusPill(text: section.label, tone: .neutral)
                        .accessibilityIdentifier("file-text-page-\(section.page)")
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.xs)
        }
        .background(theme.surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pages in this text")
    }
}
