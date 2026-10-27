import Foundation
#if canImport(Darwin)
import Observation
#endif

/// The two files "Filing ready" makes.
enum FilingReadyFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf
    case word

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: return "Filing ready · PDF"
        case .word: return "Filing ready · Word"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .word: return "docx"
        }
    }
}

/// "Filing ready": the draft, a List of Annexures for every annexure its conversation cites, the
/// typed copies, and every original's pages, as one document (`src/lib/output.js`,
/// `buildReadyToFileHtml`). Nothing is taken from what the model streamed: the pieces are read
/// fresh from the annexure register when the file is made. The markup is the web's, held to it
/// by `FilingGoldenTests`.
enum FilingReadyExport {

    static let attachFailure = "Could not attach the original for this annexure."

    private static let pageBreak = "<div style=\"page-break-before:always\"></div>"

    /// `&`, `<` and `>` escaped, as the web's `escapeText`.
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// The List of Annexures, in the register's order; empty when there are none.
    static func listHTML(rows: [FilingAnnexure]) -> String {
        guard !rows.isEmpty else { return "" }
        var trs = ""
        for (i, a) in rows.enumerated() {
            let form = a.isTyped ? "Typed copy (attached below)" : "Original (attached below)"
            let number = String(i + 1)
            trs += "<tr><td>" + number + ".</td><td>" + escape(a.mark) + "</td><td>"
                + escape(a.title) + "</td><td>" + form + "</td></tr>"
        }
        let pad = "\n          "
        var html = pad + pageBreak
        html += pad + "<p style=\"text-align:center\"><strong><u>LIST OF ANNEXURES</u></strong></p>"
        html += pad + "<table style=\"width:100%;border-collapse:collapse\">"
        html += pad + "  <thead><tr><th>S. No.</th><th>Mark</th><th>Particulars</th><th>Form</th></tr></thead>"
        html += pad + "  <tbody>" + trs + "</tbody>"
        html += pad + "</table>"
        html += pad + "<p style=\"font-style:italic;font-size:0.9em;margin-top:1em\">"
            + "For a real, physically-paginated PDF paperbook with folios reflected in the Index, use \"Assemble filing\" instead.</p>"
        return html
    }

    /// The heading an original goes under.
    static func originalHeading(mark: String) -> String {
        pageBreak + "<p style=\"text-align:center\"><strong><u>ANNEXURE " + escape(mark)
            + " (ORIGINAL)</u></strong></p>"
    }

    /// One original: its pages, the earlier mark it repeats, or the line saying it could not be
    /// attached — never left out, since the list above promised it.
    static func originalHTML(
        mark: String, pages: [FilingOriginalPages.Page], duplicateOf: String?, error: String?
    ) -> String {
        let heading = originalHeading(mark: mark)
        if let duplicateOf, !duplicateOf.isEmpty {
            return heading + "<p style=\"font-style:italic\">Same document and page range as Annexure "
                + escape(duplicateOf)
                + " above — see there for the full original, to avoid embedding it twice.</p>"
        }
        if !pages.isEmpty {
            let images = pages.map { page in
                "<img src=\"data:" + page.mime + ";base64," + page.base64 + "\" style=\"max-width:100%\"/>"
            }
            return heading + images.joined(separator: pageBreak)
        }
        return failureHTML(mark: mark, error: error)
    }

    /// The red line in place of an original that could not be attached.
    static func failureHTML(mark: String, error: String?) -> String {
        let message = (error?.isEmpty == false) ? error! : attachFailure
        return originalHeading(mark: mark)
            + "<p style=\"font-style:italic;color:#b00020\">" + escape(message) + "</p>"
    }

    /// What the page makes of an original-pages answer.
    static func originalHTML(mark: String, answer: FilingOriginalPages) -> String {
        if answer.success, let dup = answer.duplicateOf, !dup.isEmpty {
            return originalHTML(mark: mark, pages: [], duplicateOf: dup, error: nil)
        }
        if answer.success, !answer.pages.isEmpty {
            return originalHTML(mark: mark, pages: answer.pages, duplicateOf: nil, error: nil)
        }
        return failureHTML(mark: mark, error: answer.error)
    }

    static func combine(draft: String, list: String, typed: String, originals: [String]) -> String {
        draft + list + typed + originals.joined()
    }

    /// The share name: the draft's title, marked as the filing-ready copy.
    static func fileName(title: String, format: FilingReadyFormat) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = trimmed.isEmpty ? "Document" : trimmed
        return stem + " (filing ready)." + format.fileExtension
    }
}

/// What the device turns into the file: pieces of HTML, and originals as the server sent them.
/// A Word file is one piece of HTML with the originals' pages as images; a PDF is the draft, the
/// list and the typed copies, then each original's own pages.
struct FilingReadyPackage: Equatable, Sendable {
    enum Part: Equatable, Sendable {
        case html(String)
        /// An original's bytes, a PDF or an image. `mark` names it if it cannot be read.
        case original(mark: String, data: Data, mime: String)
    }

    var format: FilingReadyFormat
    var title: String
    var parts: [Part]

    /// The whole package as one piece of HTML, for a Word file.
    var html: String {
        parts.map { part in
            if case .html(let s) = part { return s }
            return ""
        }.joined()
    }
}

/// Makes a "Filing ready" file from the conversation's draft, reporting progress as the page
/// does: 8 when it starts, 25 once the list is read, 45 once the typed copies are, then on to 75
/// as each original arrives (fetched side by side, each failure a line of its own), and 100 when
/// the file is made. An unreachable register still gives the draft.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class FilingReadyExportModel {

    private(set) var progress: Int?
    private(set) var format: FilingReadyFormat?
    /// The file made, ready to share.
    private(set) var result: URL?
    /// Why no file was made.
    var failure: String?
    /// Every progress value reported, in order.
    private(set) var progressHistory: [Int] = []

    var isRunning: Bool { progress != nil && result == nil && failure == nil }

    private let service: any FilingProviding
    private let context: FilingChatContext

    init(service: any FilingProviding, context: FilingChatContext) {
        self.service = service
        self.context = context
    }

    /// Makes the file. `render` turns the package into a file on disk; `nil` is a failure.
    @discardableResult
    func run(
        _ format: FilingReadyFormat,
        render: @MainActor (FilingReadyPackage) async -> URL?
    ) async -> URL? {
        guard !isRunning else { return nil }
        self.format = format
        result = nil
        failure = nil
        progressHistory = []
        let package = await build(format)
        let url = await render(package)
        report(100)
        if let url {
            result = url
        } else {
            failure = "Could not prepare the filing-ready \(format == .pdf ? "PDF" : "Word file")."
        }
        return url
    }

    func dismiss() {
        progress = nil
        format = nil
        result = nil
        failure = nil
    }

    /// The pieces, read from the register. Never fails: what cannot be read is said in place.
    func build(_ format: FilingReadyFormat) async -> FilingReadyPackage {
        report(8)
        let chatID = context.chatID
        let draft = FilingChatScope.stripMentions(context.draftHTML)
        let rows: [FilingAnnexure] = (try? await service.annexures(chatID: chatID)) ?? []
        let list = FilingReadyExport.listHTML(rows: rows)
        report(25)
        let typed: String = (try? await service.typedCopies(chatID: chatID)) ?? ""
        report(45)
        let originals = rows.filter { !$0.isTyped }
        let fetched = await fetchOriginals(originals, format: format)
        report(75)

        var parts: [FilingReadyPackage.Part]
        switch format {
        case .word:
            let pieces: [String] = fetched.map { part in
                if case .html(let s) = part { return s }
                return ""
            }
            let combined = FilingReadyExport.combine(
                draft: draft, list: list, typed: typed, originals: pieces)
            parts = [.html(combined)]
        case .pdf:
            parts = [.html(draft + list + typed)]
            parts.append(contentsOf: fetched)
        }
        return FilingReadyPackage(format: format, title: context.draftTitle, parts: parts)
    }

    /// Each original, side by side, in the register's order: for Word its pages as images, for a
    /// PDF the file itself.
    private func fetchOriginals(
        _ rows: [FilingAnnexure], format: FilingReadyFormat
    ) async -> [FilingReadyPackage.Part] {
        guard !rows.isEmpty else { return [] }
        let service = self.service
        let chatID = context.chatID
        var results = [FilingReadyPackage.Part?](repeating: nil, count: rows.count)
        var done = 0
        await withTaskGroup(of: (Int, FilingReadyPackage.Part).self) { group in
            for (index, row) in rows.enumerated() {
                let mark = row.mark
                let duplicate = row.duplicateOf
                group.addTask {
                    let part = await Self.fetchOne(
                        service: service, chatID: chatID, mark: mark, duplicateOf: duplicate,
                        format: format)
                    return (index, part)
                }
            }
            for await (index, part) in group {
                results[index] = part
                done += 1
                let share = Double(done) / Double(rows.count) * 30
                report(45 + Int((share + 0.5).rounded(.down)))
            }
        }
        return results.map { $0 ?? .html(FilingReadyExport.failureHTML(mark: "", error: nil)) }
    }

    nonisolated private static func fetchOne(
        service: any FilingProviding, chatID: String, mark: String, duplicateOf: String?,
        format: FilingReadyFormat
    ) async -> FilingReadyPackage.Part {
        switch format {
        case .word:
            do {
                let answer = try await service.originalPages(chatID: chatID, mark: mark)
                return .html(FilingReadyExport.originalHTML(mark: mark, answer: answer))
            } catch {
                return .html(FilingReadyExport.failureHTML(mark: mark, error: nil))
            }
        case .pdf:
            if let duplicateOf, !duplicateOf.isEmpty {
                return .html(FilingReadyExport.originalHTML(
                    mark: mark, pages: [], duplicateOf: duplicateOf, error: nil))
            }
            do {
                let original = try await service.original(chatID: chatID, mark: mark)
                return .original(mark: mark, data: original.data, mime: original.mime)
            } catch {
                return .html(FilingReadyExport.failureHTML(mark: mark, error: message(for: error)))
            }
        }
    }

    /// The server's own sentence for a failed original, when it gave one.
    nonisolated static func message(for error: Error) -> String? {
        if case .server(_, let message)? = error as? APIError, !message.isEmpty { return message }
        if error as? FilingPreviewError == .unpreviewable {
            return "This file type can't be attached here — use \"Assemble filing\" for the combined paperbook."
        }
        return nil
    }

    private func report(_ value: Int) {
        let clamped = max(1, min(100, value))
        progress = clamped
        progressHistory.append(clamped)
    }
}
