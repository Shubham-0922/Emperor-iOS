import SwiftUI

/// Exporting a drafted document — as a PDF, as Word, or as its own text.
///
/// The PDF is the server's (`POST /print-pdf`), as the web's download is: laid out on A4 with
/// the footer and a page number on every page. It takes a few seconds, so a sheet says so while
/// it is prepared and then offers the share sheet. Offline, or when the server cannot render
/// it, the PDF is laid out on the phone instead and the sheet says it has no page numbers.
///
/// The Word file is built inside the menu's content closure, which SwiftUI evaluates when the
/// menu is opened rather than when the screen draws: packing an OOXML archive for every document
/// on screen would cost more than the feature is worth, and most documents are never exported.
struct DocumentExportMenu: View {
    @Environment(Session.self) private var session

    /// The document as it is held. Named `content` rather than `body`, which a `View` needs for
    /// itself.
    let content: String
    let isHTML: Bool
    let title: String
    /// Whether to ask, for each format, with or without the citation numbers — the Record
    /// draft's download menu. Offered only when the draft carries any.
    var offersCitationChoice = false
    /// Makes the "Filing ready" package — the draft with its List of Annexures, typed copies and
    /// originals — where the document can be filed. The caller shows its progress.
    var filingReady: ((FilingReadyFormat) -> Void)? = nil

    /// The PDF being prepared or ready to share. Its `id` stays the same from "preparing" to
    /// "ready", so the one sheet changes its content rather than closing and opening again.
    @State private var export: PDFExport?

    private struct PDFExport: Identifiable {
        let id: UUID
        var url: URL?
        /// Laid out on the phone, without the server's page numbers.
        var isLocal = false
        var failed = false
    }

    var body: some View {
        Menu {
            if let filingReady {
                Section("Filing ready") {
                    ForEach(FilingReadyFormat.allCases) { format in
                        filingReadyButton(format, action: filingReady)
                    }
                }
            }
            if offersCitationChoice {
                Section("Word") {
                    wordLink("Word · with citations", subtitle: "References listed at the end", citations: true)
                    wordLink("Word · without citations", subtitle: "A clean copy for filing", citations: false)
                }
                Section("PDF") {
                    pdfLink("PDF · with citations", citations: true)
                    pdfLink("PDF · without citations", citations: false)
                }
            } else {
                pdfLink("PDF", citations: true)
                wordLink("Word (.docx)", subtitle: nil, citations: true)
            }
            Divider()
            // The document as it stands, for pasting somewhere this app knows nothing about.
            ShareLink(item: content) {
                Label("Copy as text", systemImage: "textformat")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Download this document")
        .sheet(item: $export) { job in
            exportSheet(job)
                .presentationDetents([.medium, .large])
        }
    }

    private func filingReadyButton(
        _ format: FilingReadyFormat, action: @escaping (FilingReadyFormat) -> Void
    ) -> some View {
        let symbol: String = format == .pdf ? "books.vertical" : "doc.text"
        return Button {
            action(format)
        } label: {
            Label(format.title, systemImage: symbol)
        }
        .accessibilityIdentifier("filing-ready-\(format.rawValue)")
    }

    private func pdfLink(_ label: String, citations: Bool) -> some View {
        Button {
            exportPDF(citations: citations)
        } label: {
            Label(label, systemImage: "doc.richtext")
        }
    }

    @ViewBuilder
    private func exportSheet(_ job: PDFExport) -> some View {
        if let url = job.url {
            VStack(spacing: 0) {
                if job.isLocal {
                    Label("Saved without page numbers", systemImage: "info.circle")
                        .font(.brand(.caption))
                        .padding(.vertical, Spacing.sm)
                        .padding(.horizontal, Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("export-pdf-local")
                }
                ActivityView(url: url) { export = nil }
            }
        } else if job.failed {
            EmptyStateView(
                "Could not prepare the PDF",
                systemImage: "exclamationmark.triangle",
                message: "There was no room to save a copy to share. Free some space and try again.",
                tone: .warning)
        } else {
            VStack(spacing: Spacing.md) {
                ProgressView()
                Text("Preparing PDF…")
                    .font(.brand(.subheadline, weight: .medium))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("export-pdf-progress")
        }
    }

    /// The server's PDF, or the phone's own when there is no connection or the server fails.
    private func exportPDF(citations: Bool) {
        let html = fragment(citations: citations)
        let stem = fileStem(citations: citations)
        let job = PDFExport(id: UUID())
        export = job
        let offline = AppConnectivity.current.isOffline
        let routes = session.fileRoutes
        Task { @MainActor in
            var data: Data?
            if !offline {
                data = try? await routes.printPDF(html: html, title: stem, pageSetup: PageSetup())
            }
            let isLocal = data == nil
            let bytes: Data = data ?? AnswerPDF.render(html: html)
            // Closed while it was being prepared: nothing more to show.
            guard export?.id == job.id else { return }
            let url = ShareableFile.url(for: bytes, named: "\(stem).pdf")
            export = PDFExport(id: job.id, url: url, isLocal: isLocal, failed: url == nil)
        }
    }

    @ViewBuilder
    private func wordLink(_ label: String, subtitle: String?, citations: Bool) -> some View {
        if let word = wordURL(citations: citations) {
            ShareLink(item: word) {
                if let subtitle {
                    Label {
                        Text(label)
                        Text(subtitle)
                    } icon: {
                        Image(systemName: "doc.text")
                    }
                } else {
                    Label(label, systemImage: "doc.text")
                }
            }
        }
    }

    private func fragment(citations: Bool) -> String {
        let source = citations ? content : DraftCitations.withoutMarkers(content)
        return isHTML ? source : MarkdownHTML.html(from: source)
    }

    private func fileStem(citations: Bool) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = trimmed.isEmpty ? "Document" : trimmed
        return citations || !offersCitationChoice ? stem : "\(stem) (clean)"
    }

    private func wordURL(citations: Bool) -> URL? {
        ShareableFile.url(
            for: DocxDocument.make(fromHTML: fragment(citations: citations)),
            named: "\(fileStem(citations: citations)).docx")
    }
}
