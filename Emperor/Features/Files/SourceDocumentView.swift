import SwiftUI
import UIKit
import PDFKit
import UniformTypeIdentifiers

/// The cited page: a full-height sheet that opens a cited document at the page its citation
/// names.
///
/// This is the claim the product rests on — every line names a page you can open — so the jump
/// has to actually land, and the failure has to be honest when it cannot. The head names the file
/// and "Page N of M"; Prev and Next move a page at a time; under the page it says what was cited,
/// plainly — including when the citation named no page and the document opened at its first.
///
/// When the citation quotes words, they are looked for on the cited page and one either side —
/// in a scanned page's placed words from the server, or the page's own text — and marked where
/// they are found, in the theme's `mark`. The marks are drawn on the page on screen only; Share
/// sends the document as stored. When the words are elsewhere or nowhere, the sheet says so in
/// the web's words rather than pretending to have found them.
struct SourceDocumentView: View {
    @Environment(\.theme) private var theme
    let attachment: ChatAttachment
    let mention: AnnexureMention
    /// Whether a citation opened this — `false` for a document opened from the library, which
    /// has no cited page to speak of.
    var isCitation = true
    /// The words the citation quotes, to find and mark; `""` for none.
    var quote: String = ""
    /// The server's check of those words against this document.
    var quoteStatus: QuoteStatus?

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var model: SourceDocumentViewModel?
    /// The 1-based page on screen, for a PDF.
    @State private var page = 1
    @State private var pageCount: Int?
    @State private var sharing: SharedDocumentFile?
    /// The quoted words' marks, by 0-based page, in page space.
    @State private var highlights: [Int: [CGRect]] = [:]

    private struct SharedDocumentFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        VStack(spacing: 0) {
            RecordSheetHeader(
                title: model?.displayName ?? DisplayText.fileName(attachment.name),
                subtitle: headerSubtitle,
                onClose: { dismiss() })

            Group {
                if let model {
                    content(model)
                        // Whatever the document is drawn as, say when it is the copy kept on
                        // this device — and when it could not be kept.
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            offlineFooter(model)
                        }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            footer
        }
        .background(theme.elevated.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Radius.sheet)
        .sheet(item: $sharing) { shared in
            ActivityView(url: shared.url) { sharing = nil }
                .presentationDetents([.medium, .large])
        }
        .task {
            guard model == nil else { return }
            page = max(1, mention.startPage ?? 1)
            let created = SourceDocumentViewModel(
                attachment: attachment, mention: mention, service: session.files,
                officePreview: session.officePreview,
                offline: session.offlineCopies.map { OfflineDocuments(store: $0.documents) },
                connectivity: AppConnectivity.current,
                quote: quote, quoteStatus: quoteStatus, words: session.citedSources)
            model = created
            await created.load()
            if created.isPDF, let data = created.data, let document = PDFDocument(data: data) {
                pageCount = document.pageCount
                await findQuote(created, in: document)
            }
        }
    }

    /// Looks for the quoted words and marks them, landing on the page they are on.
    private func findQuote(_ model: SourceDocumentViewModel, in document: PDFDocument) async {
        guard let result = await model.findQuote(
            pageCount: document.pageCount,
            textWords: { number in
                guard let page = document.page(at: number - 1) else { return [] }
                return PDFQuoteHighlighter.words(on: page)
            })
        else { return }
        page = result.page
        if let hit = result.hit, let found = document.page(at: result.page - 1) {
            let rects = PDFQuoteHighlighter.rects(for: hit, on: found)
            if rects.isEmpty {
                // PDFKit gave no rectangles: the words are not marked, so the page does not
                // say they are; the "not located" note is said instead.
                model.quoteWasNotMarked()
            } else {
                highlights = [result.page - 1: rects]
            }
        }
        if let note = model.quoteNote {
            VoiceOver.announce(note)
        } else if !highlights.isEmpty {
            VoiceOver.announce("The quoted words are highlighted.")
        }
    }

    /// "Page 3 of 40 · Annexure P-3 · Quote checked".
    private var headerSubtitle: String? {
        var parts: [String] = []
        if let pageCount, model?.isPDF == true {
            parts.append("Page \(min(page, pageCount)) of \(pageCount)")
        } else if let pages = mention.pageDescription {
            parts.append(pages)
        }
        if !mention.mark.isEmpty { parts.append(mention.mark) }
        if let status = model?.quoteStatusLabel { parts.append(status) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Prev and Next, and what was cited — said plainly.
    private var pageControls: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let pageCount, pageCount > 1 {
                HStack(spacing: Spacing.sm) {
                    Button {
                        page = max(1, page - 1)
                        Haptics.selection()
                    } label: {
                        Label("Prev", systemImage: "chevron.left")
                    }
                    .buttonStyle(.compactSecondaryAction)
                    .disabled(page <= 1)
                    .accessibilityLabel("Previous page")

                    Spacer(minLength: 0)
                    Text("Page \(page) of \(pageCount)")
                        .font(.brand(.footnote, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textTertiary)
                    Spacer(minLength: 0)

                    Button {
                        page = min(pageCount, page + 1)
                        Haptics.selection()
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Text("Next")
                            Image(systemName: "chevron.right")
                        }
                    }
                    .buttonStyle(.compactSecondaryAction)
                    .disabled(page >= pageCount)
                    .accessibilityLabel("Next page")
                }
            }

            if isCitation {
                citedNote
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }

    /// The citation, under the page: which page it named, or that it named none — and, for a
    /// quote, that its words are marked, or where they were or were not found, on the warning wash.
    @ViewBuilder
    private var citedNote: some View {
        if let model {
            let note = model.citedNote(page: page)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: note.isWarning ? "exclamationmark.triangle" : "text.quote")
                    .foregroundStyle(note.isWarning ? theme.warning : theme.accentText)
                    .accessibilityHidden(true)
                Text(note.text)
                    .font(.brand(size: 13.5, relativeTo: .footnote))
                    .foregroundStyle(note.isWarning ? theme.textPrimary : theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(
                note.isWarning ? theme.warnBg : theme.accentSoft,
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle().fill(note.isWarning ? theme.warning : theme.accentText).frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(note.isWarning ? "source-quote-note" : "source-cited-note")
        }
    }

    /// Share — the one action, so it carries the gradient.
    private var footer: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                guard let data = model?.data,
                      let url = ShareableFile.url(
                        for: data, named: model?.displayName ?? attachment.name)
                else { return }
                sharing = SharedDocumentFile(url: url)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
            .disabled(model?.data == nil)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
        .background(theme.elevated)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.separator).frame(height: 1)
        }
    }

    @ViewBuilder
    private func offlineFooter(_ model: SourceDocumentViewModel) -> some View {
        if let notice = model.offlineNotice() {
            OfflineCopyBanner(notice: notice)
        } else if let note = model.offlineNote {
            Label(note, systemImage: "arrow.down.circle")
                .font(.brand(.caption))
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Spacing.sm)
                .padding(.horizontal, Spacing.lg)
                .background(theme.surface)
                .overlay(alignment: .top) {
                    Rectangle().fill(theme.separator).frame(height: 0.5)
                }
        }
    }

    @ViewBuilder
    private func content(_ model: SourceDocumentViewModel) -> some View {
        if model.isLoading {
            ProgressView("Opening \(model.displayName)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let data = model.data, model.isPDF {
            VStack(spacing: 0) {
                pageControls
                // The page as paper: the document's own white, on the sheet's recessed ground.
                PDFDataView(
                    data: data, page: page, pagesOneAtATime: true,
                    highlights: highlights, highlightColor: UIColor(theme.mark))
                    .background(theme.surface2)
            }
                .safeAreaInset(edge: .bottom) {
                    if model.isConvertedPreview {
                        // Said out loud because it is not the document. Pagination, fonts and
                        // line breaks are LibreOffice's reading of the file, so a page number
                        // taken from here may not match the one the sender sees — which for a
                        // filing is the difference that matters.
                        Label(
                            "Converted for viewing. Page breaks may differ from the original.",
                            systemImage: "info.circle")
                            .font(.brand(.caption))
                            .foregroundStyle(theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                            .padding(.horizontal, Spacing.lg)
                            .background(theme.surface)
                            .overlay(alignment: .top) {
                                Rectangle().fill(theme.separator).frame(height: 0.5)
                            }
                    }
                }
        } else if let data = model.data, let image = UIImage(data: data) {
            // Scanned exhibits are frequently filed as images rather than PDFs.
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image).resizable().scaledToFit()
                    // Otherwise announced only as "image".
                    .accessibilityLabel("Scanned page, \(model.displayName)")
            }
        } else if let text = model.textContents {
            ScrollView {
                Text(text)
                    .font(.brand(.callout))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        } else {
            EmptyStateView(
                "Cannot preview this document",
                systemImage: "doc.questionmark",
                message: model.unavailableMessage,
                tone: .neutral)
        }
    }
}
