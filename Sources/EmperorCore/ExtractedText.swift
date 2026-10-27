import Foundation

/// A Word document the server could not convert for viewing, shown instead as the text read out
/// of it when it was uploaded — the web's `ExtractedTextPane`
/// (`src/components/viewer/viewers.jsx`).
///
/// Two rules carried over from the web, both about not passing a reconstruction off as the
/// document:
///
/// - **One section per extractor page, labelled with the extractor's own number.** The text is
///   never re-paginated: an advocate cites page numbers, and "Page 7" over text that is not page
///   7 of the filed document is worse than no label.
/// - **The banner says what this is**, every time: rebuilt from extracted text, not the original.
enum ExtractedText {

    /// One page as drawn: its label and its body as an HTML fragment.
    struct PageSection: Equatable, Sendable {
        let page: Int
        let label: String
        let html: String
    }

    /// What an answer with no pages means.
    enum EmptyState: Equatable, Sendable {
        /// The document itself is missing from storage.
        case gone
        /// Still being read, or nothing readable could be pulled out of it.
        case notYet

        var title: String {
            switch self {
            case .gone: return "This file is no longer on the server"
            case .notYet: return "No text has been extracted yet"
            }
        }

        var message: String {
            switch self {
            case .gone:
                return "It is listed in your files, but the document itself is missing from storage. Nothing can be shown for it."
            case .notYet:
                return "This document is still being processed, or no readable text could be pulled out of it. The original file is unaffected and can be shared."
            }
        }
    }

    /// The pages in the order the server sent them, each labelled with its own number.
    static func sections(from response: FileTextResponse) -> [PageSection] {
        (response.pages ?? []).map { page in
            let text = page.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = text.isEmpty ? "<p><em>(no text on this page)</em></p>" : MarkdownHTML.html(from: page.content)
            return PageSection(page: page.page, label: "Page \(page.page)", html: body)
        }
    }

    /// `(label, html)` pairs, for callers that need no page number.
    static func pages(from response: FileTextResponse) -> [(label: String, html: String)] {
        sections(from: response).map { (label: $0.label, html: $0.html) }
    }

    /// The pages joined into one fragment for a single web view, each under its label.
    static func joinedHTML(from response: FileTextResponse) -> String {
        sections(from: response).map { section in
            let heading = #"<p class="page-label" style="font-family: -apple-system, sans-serif; font-size: 0.75em; letter-spacing: 0.08em; text-transform: uppercase; opacity: 0.7; margin: 2em 0 0.5em;">"#
            return heading + section.label + "</p>" + section.html
        }
        .joined(separator: "\n<hr>\n")
    }

    /// The banner over the pages: what this is, and — when the server said so — that the text
    /// was matched by name alone, or that only the first pages are here.
    static func notice(for response: FileTextResponse, conversionNote: String? = nil) -> String {
        var parts: [String] = []
        if let note = conversionNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            parts.append(note)
        }
        parts.append(
            "Rebuilt from extracted text — not the original document. This is the text read out of it when it was uploaded, laid out again here. Headings, emphasis, lists and tables survive; images, signatures, stamps, headers and footers do not. Each section is one page as the extractor found it.")
        if response.matchedBy == "name" {
            parts.append(
                "The text was matched by file name, so it may come from another copy of a document with this name.")
        }
        if response.truncated == true {
            let shown = response.pages?.count ?? 0
            let total = response.totalPages ?? shown
            parts.append("Only the first \(shown) of \(total) pages are shown here.")
        }
        return parts.joined(separator: " ")
    }

    /// `nil` when there are pages to show.
    static func emptyState(for response: FileTextResponse) -> EmptyState? {
        guard (response.pages ?? []).isEmpty else { return nil }
        return response.fileExists == false ? .gone : .notYet
    }
}
