import SwiftUI
import UIKit

/// The judgment reader: the header card, the typeset blocks, the contents, find-in-judgment with
/// its count, the text size, a paragraph's link and the citation to copy, and the original to
/// share (`caselaw/JudgmentView.jsx`, `JudgmentBlocks.jsx`, `JudgmentHeader.jsx`).
struct LibraryJudgmentReader: View {
    @Environment(\.theme) private var theme

    let model: LibraryJudgmentViewModel

    @State private var findText = ""
    @State private var isFinding = false
    @State private var isShowingContents = false
    @State private var target: String?
    @State private var toast: String?
    @State private var sharing: LibrarySharedFile?
    @State private var isPreparingShare = false

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .missing:
                EmptyStateView(LibraryJudgmentViewModel.missingTitle, systemImage: "books.vertical",
                               message: LibraryJudgmentViewModel.missingMessage, tone: .neutral)
                    .accessibilityIdentifier("library-not-on-shelf")
            case .tooLarge:
                EmptyStateView(LibraryJudgmentViewModel.tooLargeTitle, systemImage: "doc.text",
                               message: LibraryJudgmentViewModel.tooLargeMessage, tone: .neutral) {
                    shareButton(label: "Share the original")
                        .buttonStyle(.primaryAction)
                }
            case .failed(let failure):
                EmptyStateView(LibraryJudgmentViewModel.failedTitle, systemImage: "exclamationmark.triangle",
                               message: failure.message, tone: .warning) {
                    if failure.isRetryable {
                        Button("Try again") { Task { await model.load() } }
                            .buttonStyle(.primaryAction)
                    }
                }
            case .ready:
                reader
            }
        }
        .recordToast($toast)
        .sheet(item: $sharing) { shared in
            ActivityView(url: shared.url) { sharing = nil }
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - The reader

    private var reader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.md) {
                    if model.isPlain {
                        Text(LibraryJudgmentViewModel.plainNote)
                            .font(.brand(.footnote, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.surface2, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                            .accessibilityIdentifier("library-plain-note")
                    }
                    if !model.isPlain {
                        header
                            .id("judgment-top")
                    }
                    ForEach(Array(model.blocks.enumerated()), id: \.element.id) { index, block in
                        blockView(block, index: index)
                            .id(block.id)
                    }
                    if model.blocks.isEmpty {
                        Text("This judgment has no text we can show. It may be a scanned image; share the original.")
                            .font(.brand(.subheadline))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.lg)
                .readableColumn()
            }
            .background(theme.canvas)
            .safeAreaInset(edge: .top, spacing: 0) {
                if isFinding { findBar }
            }
            .onChange(of: target) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .top) }
                target = nil
            }
            .onChange(of: model.currentHitBlockID) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .onChange(of: findText) { _, text in model.find(text) }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isShowingContents = true
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .accessibilityLabel("Contents")
                .accessibilityIdentifier("library-contents")
                .disabled(model.contents.isEmpty)

                Button {
                    isFinding.toggle()
                    if !isFinding { findText = "" }
                } label: {
                    Image(systemName: "text.magnifyingglass")
                }
                .accessibilityLabel(isFinding ? "Close find" : "Find in this judgment")
                .accessibilityIdentifier("library-find-toggle")

                Menu {
                    Button {
                        model.enlarge()
                    } label: {
                        Label("Larger text", systemImage: "textformat.size.larger")
                    }
                    .disabled(!model.canEnlarge)
                    Button {
                        model.shrink()
                    } label: {
                        Label("Smaller text", systemImage: "textformat.size.smaller")
                    }
                    .disabled(!model.canShrink)
                    Button {
                        UIPasteboard.general.string = model.citationLine
                        toast = "Citation copied"
                    } label: {
                        Label("Copy citation", systemImage: "quote.opening")
                    }
                    shareButton(label: "Share the original")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Reading options")
                .accessibilityIdentifier("library-reader-menu")
            }
        }
        .sheet(isPresented: $isShowingContents) {
            contentsSheet
        }
    }

    private func shareButton(label: String) -> some View {
        Button {
            Task {
                isPreparingShare = true
                defer { isPreparingShare = false }
                guard let data = await model.originalText(),
                      let url = ShareableFile.url(for: data, named: "\(model.title).txt") else {
                    toast = "The original could not be fetched."
                    return
                }
                sharing = LibrarySharedFile(url: url)
            }
        } label: {
            Label(label, systemImage: "square.and.arrow.up")
        }
        .disabled(isPreparingShare)
        .accessibilityIdentifier("library-share-original")
    }

    // MARK: - Find

    private var findBar: some View {
        HStack(spacing: Spacing.sm) {
            RecordSearchField(text: $findText, prompt: "Find in this judgment")
                .accessibilityIdentifier("library-find-field")
            if !model.findLabel.isEmpty {
                Text(model.findLabel)
                    .font(.brand(.caption, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize()
                    .accessibilityIdentifier("library-find-count")
            }
            Button {
                model.step(-1)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(minWidth: Layout.touchTarget, minHeight: Layout.touchTarget)
            }
            .disabled(model.hits.isEmpty)
            .accessibilityLabel("Previous match")
            .accessibilityIdentifier("library-find-previous")
            Button {
                model.step(1)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(minWidth: Layout.touchTarget, minHeight: Layout.touchTarget)
            }
            .disabled(model.hits.isEmpty)
            .accessibilityLabel("Next match")
            .accessibilityIdentifier("library-find-next")
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.sm)
        .background(theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1) }
    }

    // MARK: - Contents

    private var contentsSheet: some View {
        VStack(spacing: 0) {
            RecordSheetHeader(title: "Contents", subtitle: model.title, onClose: { isShowingContents = false })
            ScrollView {
                RecordGroup {
                    ForEach(Array(model.contents.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { RecordDivider(inset: 14) }
                        Button {
                            isShowingContents = false
                            target = entry.id
                        } label: {
                            RecordRow(title: entry.label, titleLines: 2) {
                                if entry.level >= 3 {
                                    Image(systemName: "paragraphsign")
                                        .foregroundStyle(theme.textTertiary)
                                        .accessibilityHidden(true)
                                }
                            } trailing: {
                                EmptyView()
                            }
                        }
                        .buttonStyle(.recordRow)
                        .accessibilityIdentifier("library-contents-\(entry.id)")
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
            }
        }
        .background(theme.groupedBackground)
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("library-contents-sheet")
    }

    // MARK: - The header card

    private var header: some View {
        VStack(alignment: .center, spacing: Spacing.sm) {
            Text(model.court.name.uppercased())
                .recordText(RecordTokens.Typography.label)
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
            Text(model.title)
                .font(.serif(.title2, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !model.caseNumber.isEmpty {
                Text(model.caseNumber)
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 0) {
                if let decided = model.decided { ValueRow("Decided", value: decided) }
                if !model.bench.isEmpty {
                    ValueRow(model.bench.count > 1 ? "Bench of \(model.bench.count)" : "Bench",
                             value: model.bench.joined(separator: "\n"))
                }
                if let author = LibraryDisplay.truthy(model.header?.author) { ValueRow("Judgment by", value: author) }
                if let length = model.lengthText { ValueRow("Length", value: length) }
            }
            .font(.brand(.subheadline))
            .padding(.vertical, Spacing.xs)
            if !model.citations.isEmpty {
                LibraryFlowLayout(spacing: Spacing.xs) {
                    ForEach(model.citations, id: \.self) { citation in
                        Button {
                            UIPasteboard.general.string = citation
                            toast = "Citation copied"
                        } label: {
                            Label(citation, systemImage: "doc.on.doc")
                                .font(.brand(.caption, weight: .semibold))
                        }
                        .buttonStyle(ChipButtonStyle(isSelected: citation == model.citations.first))
                        .accessibilityLabel("Copy citation \(citation)")
                    }
                }
            }
            Button {
                UIPasteboard.general.string = model.citationLine
                toast = "Citation copied"
            } label: {
                Label("Copy citation", systemImage: "quote.opening")
            }
            .buttonStyle(.quietAction)
            .accessibilityIdentifier("library-copy-citation")
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(theme.separator, lineWidth: 1))
    }

    // MARK: - Blocks

    private var bodySize: CGFloat { 17 * model.textScale }

    /// The system serif at a size the reader chose, still scaling with Dynamic Type.
    private func serif(_ size: CGFloat) -> Font {
        let base = UIFont.systemFont(ofSize: size, weight: .regular)
        let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        return Font(UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont(descriptor: descriptor, size: size)))
    }

    @ViewBuilder
    private func blockView(_ block: JudgmentBlock, index: Int) -> some View {
        let marked = highlighted(block, index: index)
        switch block.kind {
        case .heading:
            Text(marked)
                .font(.serif(block.level == 1 ? .title3 : .headline, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: block.level == 1 ? .center : .leading)
                .multilineTextAlignment(block.level == 1 ? .center : .leading)
                .padding(.top, Spacing.md)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("judgment-block-\(block.id)")
        case .cause:
            VStack(spacing: Spacing.xxs) {
                ForEach(Array((block.lines ?? [block.text]).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.brand(size: bodySize * 0.92, weight: line.uppercased() == line ? .semibold : .regular, relativeTo: .body))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("judgment-block-\(block.id)")
        case .quote:
            Text(marked)
                .font(serif(bodySize * 0.95).italic())
                .foregroundStyle(theme.textPrimary)
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface2, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .padding(.leading, Spacing.lg)
                .accessibilityIdentifier("judgment-block-\(block.id)")
        case .list:
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(block.marker ?? "•")
                    .font(.brand(size: bodySize, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(theme.textSecondary)
                Text(marked)
                    .font(.brand(size: bodySize, relativeTo: .body))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, Spacing.lg)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("judgment-block-\(block.id)")
        case .meta:
            Text(marked)
                .font(.brand(size: bodySize * 0.92, relativeTo: .footnote))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("judgment-block-\(block.id)")
        case .table:
            ScrollView(.horizontal, showsIndicators: true) {
                Text(marked)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize()
                    .padding(Spacing.sm)
            }
            .background(theme.surface2, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .accessibilityLabel("Table")
            .accessibilityIdentifier("judgment-block-\(block.id)")
        case .para, .unknown:
            paragraph(block, marked)
        }
    }

    private func paragraph(_ block: JudgmentBlock, _ marked: AttributedString) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            if let n = block.n {
                Button {
                    let link = model.paragraphLink(block.id, apiBaseURL: APIConfig.current.baseURL)
                    UIPasteboard.general.string = link.absoluteString
                    toast = "Link to paragraph \(n) copied"
                } label: {
                    Text(n)
                        .font(.brand(size: bodySize * 0.8, weight: .bold, relativeTo: .footnote))
                        .monospacedDigit()
                        .foregroundStyle(theme.accentText)
                        .frame(minWidth: 28, minHeight: Layout.touchTarget, alignment: .topTrailing)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy link to paragraph \(n)")
                .accessibilityIdentifier("judgment-para-link-\(n)")
            }
            Text(marked)
                .font(serif(bodySize))
                .foregroundStyle(theme.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("judgment-block-\(block.id)")
    }

    /// The block's text with every find match marked, the current one stronger.
    private func highlighted(_ block: JudgmentBlock, index: Int) -> AttributedString {
        let text = block.searchableText as NSString
        let hits = model.hits(inBlock: index)
        guard !hits.isEmpty else { return AttributedString(block.searchableText) }
        let current = model.currentHit.flatMap { model.hits.indices.contains($0) ? model.hits[$0] : nil }
        var out = AttributedString()
        var at = 0
        for hit in hits where hit.start >= at && hit.end <= text.length {
            if hit.start > at {
                out += AttributedString(text.substring(with: NSRange(location: at, length: hit.start - at)))
            }
            var piece = AttributedString(text.substring(with: NSRange(location: hit.start, length: hit.end - hit.start)))
            piece.backgroundColor = hit == current ? theme.accentLine : theme.accentSoft
            piece.inlinePresentationIntent = .stronglyEmphasized
            out += piece
            at = hit.end
        }
        if at < text.length {
            out += AttributedString(text.substring(from: at))
        }
        return out
    }
}
