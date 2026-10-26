import UIKit
import PDFKit

/// Where a citation's quoted words are on a PDF page, as rectangles in the page's own space —
/// what a highlight annotation is placed in.
///
/// Which words they are is decided in the core (`SourceDocumentViewModel.findQuote`, the web's
/// matcher); this only reads a page's text for it and turns the answer into rectangles.
enum PDFQuoteHighlighter {

    /// The words of a page that has a text layer of its own, in the order PDFKit reads them.
    static func words(on page: PDFPage) -> [String] {
        CitedSource.wordRuns(page.string ?? "").map(\.word)
    }

    /// One rectangle per line of the quoted words, in page space.
    static func rects(for hit: QuoteSearchResult.Hit, on page: PDFPage) -> [CGRect] {
        switch hit {
        case .textWords(let range):
            let runs = CitedSource.wordRuns(page.string ?? "")
            guard range.lowerBound >= 0, range.upperBound < runs.count else { return [] }
            let first = runs[range.lowerBound].range
            let last = runs[range.upperBound].range
            let span = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
            guard let selection = page.selection(for: span) else { return [] }
            return selection.selectionsByLine()
                .map { $0.bounds(for: page).insetBy(dx: -1, dy: -1) }
                .filter { !$0.isEmpty }
        case .scanBoxes(let boxes):
            // The server places words on the page as shown, from its top; a page's own space is
            // unrotated, from its bottom, offset by the crop box.
            let crop = page.bounds(for: .cropBox)
            return boxes.map { box in
                let placed = CitedSource.pageSpace(
                    box, cropX: Double(crop.minX), cropY: Double(crop.minY),
                    cropWidth: Double(crop.width), cropHeight: Double(crop.height),
                    rotation: page.rotation)
                return CGRect(
                    x: placed.x0, y: placed.y0,
                    width: placed.x1 - placed.x0, height: placed.y1 - placed.y0)
                    .insetBy(dx: -1, dy: -1)
            }
        }
    }
}
