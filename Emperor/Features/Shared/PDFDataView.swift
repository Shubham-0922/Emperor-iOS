import SwiftUI
import UIKit
import PDFKit

/// A PDF held in memory, optionally opened at a page.
///
/// Shared by the citation viewer and the order viewer so the page-jump behaviour cannot drift
/// between them — landing on the right page is the product's central claim in one case and the
/// whole point of the fetch in the other.
struct PDFDataView: UIViewRepresentable {
    let data: Data
    /// The 1-based page to show. When it changes the view moves to it — the cited page's Prev
    /// and Next — and on first load it is where the document opens.
    var page: Int?
    /// One page at a time, moved only by `page` — the cited-page sheet, whose "Page N of M" must
    /// always be the page on screen. Otherwise the pages scroll continuously.
    var pagesOneAtATime = false
    /// Passages to mark, by 0-based page, as rectangles in that page's own space — a citation's
    /// quoted words. Drawn on the document on screen only, never written into `data`, so what is
    /// shared is the document as stored. Applied once per change, and the first is brought into
    /// view.
    var highlights: [Int: [CGRect]] = [:]
    /// The marks' colour — the theme's `mark`.
    var highlightColor: UIColor = .systemYellow

    final class Coordinator {
        /// The page last moved to, so a redraw for any other reason does not move the reader.
        var shownPage: Int?
        var hasShown = false
        /// The marks drawn, and on which pages, so a change replaces them rather than adding.
        var appliedHighlights: [Int: [CGRect]] = [:]
        var annotations: [(page: PDFPage, annotation: PDFAnnotation)] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Replaces the marks when they have changed, and answers where the first one is.
    private func applyHighlights(
        to document: PDFDocument, _ coordinator: Coordinator
    ) -> (page: PDFPage, rect: CGRect)? {
        guard coordinator.appliedHighlights != highlights else { return nil }
        for drawn in coordinator.annotations {
            drawn.page.removeAnnotation(drawn.annotation)
        }
        coordinator.annotations = []
        coordinator.appliedHighlights = highlights
        var first: (page: PDFPage, rect: CGRect)?
        for index in highlights.keys.sorted() {
            guard let page = document.page(at: index) else { continue }
            for rect in highlights[index] ?? [] {
                let mark = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                mark.color = highlightColor
                page.addAnnotation(mark)
                coordinator.annotations.append((page, mark))
                if first == nil { first = (page, rect) }
            }
        }
        return first
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = pagesOneAtATime ? .singlePage : .singlePageContinuous
        view.displayDirection = .vertical
        view.usePageViewController(false, withViewOptions: nil)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document == nil, let document = PDFDocument(data: data) {
            view.document = document
        }
        guard let document = view.document else { return }
        let firstMark = applyHighlights(to: document, context.coordinator)
        defer {
            // After any page move, so the mark is what ends up in view. Deferred for the same
            // reason the page move is.
            if let firstMark {
                DispatchQueue.main.async {
                    view.go(to: firstMark.rect, on: firstMark.page)
                }
            }
        }
        guard !context.coordinator.hasShown || context.coordinator.shownPage != page else { return }
        context.coordinator.hasShown = true
        context.coordinator.shownPage = page

        guard let index = SourceDocumentViewModel.pageIndex(
            for: page, pageCount: document.pageCount),
              let target = document.page(at: index) else { return }
        // Deferred: PDFView ignores go(to:) until it has laid the document out.
        DispatchQueue.main.async {
            view.go(to: target)
        }
    }
}

/// Writes bytes to a temporary file so they can be shared.
///
/// `ShareLink` needs a `Transferable`, and `Data` is not one — a `URL` is. The file lands in
/// the temporary directory, which the system reclaims, so nothing confidential outlives the
/// share sheet by long.
@MainActor
enum ShareableFile {
    static func url(for data: Data, named name: String) -> URL? {
        // A `/` here would become a path separator, the intermediate directory would not
        // exist, and the write would throw — making the Share button silently disappear for
        // any document whose name carries a court reference like "W.P.(C) 1234/2024".
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = cleaned.isEmpty ? "Document.pdf" : cleaned
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmperorShare", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(safe)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            // Last resort: a name we know is writable, so sharing never silently vanishes.
            let fallback = directory.appendingPathComponent("\(UUID().uuidString).pdf")
            return (try? data.write(to: fallback, options: .atomic)) == nil ? nil : fallback
        }
    }

    /// Removes everything this has written. Called on sign-out: a shared order PDF sitting in
    /// `tmp` would otherwise outlive the session that fetched it.
    ///
    /// `nonisolated` because it is called from `ResponseCache.onClear`, which is `@Sendable` —
    /// a `@Sendable` closure literal gets no MainActor inference, so an isolated method would
    /// not compile there. It touches only `FileManager`, so there is no actor state to protect.
    nonisolated static func clear() {
        try? FileManager.default.removeItem(
            at: FileManager.default.temporaryDirectory
                .appendingPathComponent("EmperorShare", isDirectory: true))
    }
}
