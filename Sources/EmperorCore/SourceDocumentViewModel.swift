import Foundation
#if canImport(Darwin)
import Observation
#endif

/// Opening a cited source document at the page the citation names.
///
/// This is the claim the product rests on — every line names a page you can open — so the
/// jump has to actually land, and the failure has to be honest when it cannot.
///
/// See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class SourceDocumentViewModel {
    private(set) var data: Data?
    private(set) var isLoading = true
    var errorMessage: String?

    /// True when `data` holds a server-rendered PDF of a Word document rather than the document
    /// itself. Worth surfacing: the user should know they are looking at a rendering, because
    /// the layout is LibreOffice's reading of it and not necessarily what the sender saw.
    private(set) var isConvertedPreview = false

    /// When `data` is the copy kept on this device rather than what the server just sent, the
    /// moment that copy was fetched.
    private(set) var savedCopyAt: Date?
    /// Set when the document opened but could not be kept for reading offline, because the room
    /// for offline copies is taken. Said rather than left to be discovered in a corridor with no
    /// signal.
    private(set) var offlineNote: String?

    /// A Word document the server could not convert: the text read out of it at upload, shown in
    /// its place (`ExtractedText`). Never kept for offline reading.
    private(set) var extractedText: FileTextResponse?
    /// Why the document is shown as extracted text — the converter's reason.
    private(set) var conversionNote: String?

    let attachment: ChatAttachment
    let mention: AnnexureMention
    /// The words the citation quotes, to find and mark; `""` for none.
    let quote: String
    /// The server's check of those words against this document.
    let quoteStatus: QuoteStatus?

    /// What the search for the quoted words found, once it has run.
    private(set) var quoteSearch: QuoteSearchResult?
    /// The web's sentence about that search, when there is one to say — words found on another
    /// page, not found, or a scan still being prepared.
    var quoteNote: String?

    private let service: any FileProviding
    private let officePreview: (any OfficePreviewProviding)?
    private let offline: OfflineDocuments?
    private let connectivity: (any ConnectivityReporting)?
    private let words: (any CitedSourceResolving)?
    private let fileText: (any FileRouteProviding)?

    /// - Parameters:
    ///   - offline: where this account keeps documents for reading offline. Every document that
    ///     opens is kept there, and opens from there when the server cannot be reached.
    ///   - connectivity: whether the device is known to have no connection.
    ///   - quote: the words a citation quotes, to find on the cited page and mark.
    ///   - quoteStatus: the server's check of those words.
    ///   - words: where a scanned page's placed words come from (`/page-words`).
    ///   - fileText: where a Word document's extracted text comes from when the server cannot
    ///     convert it for viewing.
    init(
        attachment: ChatAttachment,
        mention: AnnexureMention,
        service: any FileProviding,
        officePreview: (any OfficePreviewProviding)? = nil,
        offline: OfflineDocuments? = nil,
        connectivity: (any ConnectivityReporting)? = nil,
        quote: String = "",
        quoteStatus: QuoteStatus? = nil,
        words: (any CitedSourceResolving)? = nil,
        fileText: (any FileRouteProviding)? = nil
    ) {
        self.attachment = attachment
        self.mention = mention
        self.service = service
        self.officePreview = officePreview
        self.offline = offline
        self.connectivity = connectivity
        self.quote = quote
        self.quoteStatus = quoteStatus
        self.words = words
        self.fileText = fileText
    }

    // MARK: - The quoted words

    /// What the head adds for the server's check of the quote, if anything.
    var quoteStatusLabel: String? {
        switch quoteStatus {
        case .verified: return "Quote checked"
        case .mismatch: return "Quote differs from the source"
        case .unlocated: return "Quote not found in the source"
        case .tooShort, nil: return nil
        }
    }

    /// The placed words of one page of a scanned document, or `nil` when they cannot be had —
    /// the page's own text is used then.
    func scannedWords(page: Int) async -> PageWords? {
        guard let words else { return nil }
        let folder = (attachment.folderName?.isEmpty ?? true) ? "." : attachment.folderName!
        return try? await words.pageWords(folderName: folder, fileName: attachment.name, page: page)
    }

    /// Looks for the quoted words on the cited page, then one either side, as the web's viewer
    /// does: a scanned page's placed words where the server has them, the page's own text
    /// (`textWords`, the `\S+` runs of a 1-based page) otherwise. Sets `quoteSearch` and
    /// `quoteNote`. Nothing is searched for without a quote, or in a document that is not a PDF.
    func findQuote(
        pageCount: Int, textWords: @MainActor (Int) -> [String]
    ) async -> QuoteSearchResult? {
        guard !quote.isEmpty, isPDF, pageCount > 0 else { return nil }
        let target = min(pageCount, max(1, mention.startPage ?? 1))
        var pending = false
        for n in CitedSource.searchOrder(target: target, pageCount: pageCount) {
            let scanned = await scannedWords(page: n)
            if let scanned, scanned.status == .ready, !scanned.words.isEmpty {
                if let range = CitedSource.findQuoteRange(words: scanned.words.map(\.text), quote: quote) {
                    return finish(QuoteSearchResult(
                        page: n, target: target,
                        hit: .scanBoxes(CitedSource.lineRects(scanned.words.map(\.box), range))))
                }
                continue
            }
            let text = textWords(n)
            // A scan still being prepared, with next to no text of its own: say so if nothing is
            // found, rather than that the words are not there.
            if scanned?.status == .pending, text.count < 20 { pending = true }
            if let range = CitedSource.findQuoteRange(words: text, quote: quote) {
                return finish(QuoteSearchResult(page: n, target: target, hit: .textWords(range)))
            }
        }
        return finish(QuoteSearchResult(page: target, target: target, hit: nil, pending: pending))
    }

    /// The words were found but the page could not place a mark on them: counted as not
    /// located, so neither the note under the page nor VoiceOver claims they are highlighted.
    func quoteWasNotMarked() {
        guard let found = quoteSearch, found.hit != nil else { return }
        _ = finish(QuoteSearchResult(page: found.page, target: found.target, hit: nil, pending: found.pending))
    }

    private func finish(_ result: QuoteSearchResult) -> QuoteSearchResult {
        quoteSearch = result
        quoteNote = CitedSource.note(
            target: result.target, foundOn: result.hit == nil ? nil : result.page,
            pending: result.pending)
        return result
    }

    /// The line under the page about what was cited, for the page on screen.
    func citedNote(page: Int) -> CitedNote {
        if !quote.isEmpty, let search = quoteSearch {
            if search.hit != nil, page == search.page, search.page == search.target {
                return CitedNote(text: "The quoted words are highlighted.", isWarning: false)
            }
            if let quoteNote { return CitedNote(text: quoteNote, isWarning: true) }
        }
        guard let cited = mention.startPage else {
            return CitedNote(
                text: "The answer cites this document without a page, so it opens at the first.",
                isWarning: false)
        }
        let onCited = page == cited || mention.endPage.map { (cited...max(cited, $0)).contains(page) } == true
        return CitedNote(
            text: onCited
                ? "This is the page the answer cites."
                : "The answer cites \(mention.pageDescription ?? "page \(cited)").",
            isWarning: false)
    }

    // MARK: - Titles

    var displayName: String { DisplayText.fileName(attachment.name) }

    /// The mark is how the document is referred to in the filing, so it belongs next to the
    /// page rather than being dropped.
    var subtitle: String {
        [mention.mark, mention.pageDescription].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Content

    /// A converted Word document counts: what `data` holds in that case *is* a PDF, and the
    /// renderer has to be told so or a successful preview would fall through to the "not a
    /// format this app can display" branch.
    var isPDF: Bool {
        isConvertedPreview || attachment.name.lowercased().hasSuffix(".pdf")
    }

    /// Whether this is a document the server can render for viewing.
    var isOfficeDocument: Bool { OfficePreview.canPreview(fileName: attachment.name) }

    /// The document as text, when it is text at all.
    ///
    /// Only consulted after the PDF and image paths have been ruled out, so a `nil` here means
    /// the format genuinely cannot be shown rather than that it is empty.
    var textContents: String? {
        guard let data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// What to say when nothing can be rendered.
    ///
    /// A load failure is the more useful explanation when there was one; otherwise the file
    /// arrived intact and simply is not a format this app displays.
    var unavailableMessage: String {
        errorMessage ?? "\(displayName) is not a format this app can display."
    }

    /// The 0-based page to open, from the citation's 1-based page number.
    ///
    /// The server indexes pages as `idx + 1` (`sync-server.js:1479`) while PDFKit is 0-based.
    /// Out-of-range pages are clamped rather than refused: a citation can name a page beyond
    /// the file if the model read a different edition, and landing on the last page beats
    /// showing nothing.
    /// `nonisolated` because it is arithmetic on its arguments: the caller is `PDFView`
    /// layout code, which has no reason to hop to the main actor to ask.
    nonisolated static func pageIndex(for page: Int?, pageCount: Int) -> Int? {
        guard let page, page > 0, pageCount > 0 else { return nil }
        return min(page - 1, pageCount - 1)
    }

    // MARK: - Loading

    /// Fetches the document — a Word document through the server's converter, see
    /// `DocumentFetch` — and keeps what arrived for reading offline.
    ///
    /// - Important: the converter's metadata route answers **200 with `success: false`** when
    ///   conversion fails. Branching on the status code would leave `data` nil with no
    ///   `errorMessage`, and the screen would show "not a format this app can display" — which is
    ///   wrong, and hides the reason the server actually gave. `DocumentFetch` throws it instead.
    ///
    /// The copy kept on the device opens in two cases only, per `OfflineReading`: the system says
    /// there is no connection, or the request could not reach the server. A document is a file
    /// rather than a feed, so with no connection the copy is opened without asking the network at
    /// all — the person is reading it, and it should not reload under them.
    func load() async {
        isLoading = true
        defer { isLoading = false }

        if OfflineReading.opensSavedCopyFirst(connectivity), openSavedCopy() { return }

        do {
            let document = try await DocumentFetch.fetch(
                attachment, files: service, officePreview: officePreview)
            data = document.data
            isConvertedPreview = document.isConvertedPreview
            savedCopyAt = nil
            keep(document)
        } catch {
            if OfflineReading.mayStandIn(after: error), openSavedCopy() { return }
            if let notViewable = error as? DocumentNotViewable,
               await openExtractedText(because: notViewable.message) {
                return
            }
            errorMessage = (error as? DocumentNotViewable)?.message
                ?? DisplayText.message(for: error)
        }
    }

    /// A Word document the converter refused: its extracted text instead, as the web's viewer
    /// falls back (`src/components/viewer/viewers.jsx`). `false` when there is none to ask for
    /// or the request failed — the converter's reason is then said as before.
    private func openExtractedText(because reason: String) async -> Bool {
        guard isOfficeDocument, let fileText else { return false }
        guard let response = try? await fileText.fileText(
            name: attachment.name, folderName: attachment.folderName)
        else { return false }
        extractedText = response
        conversionNote = reason
        errorMessage = nil
        return true
    }

    /// The banner over the extracted text.
    var extractedNotice: String? {
        extractedText.map { ExtractedText.notice(for: $0, conversionNote: conversionNote) }
    }

    /// "Offline — showing the copy saved yesterday", while the kept copy is on screen.
    func offlineNotice(now: Date = Date()) -> String? {
        savedCopyAt.map { OfflineReading.notice(savedAt: $0, now: now) }
    }

    /// The rendering this viewer fetches for the document, which is the one to look for offline.
    private var showsConverted: Bool { isOfficeDocument && officePreview != nil }

    private func openSavedCopy() -> Bool {
        guard let copy = offline?.copy(of: attachment, converted: showsConverted) else {
            return false
        }
        data = copy.data
        isConvertedPreview = showsConverted
        savedCopyAt = copy.savedAt
        errorMessage = nil
        return true
    }

    /// Keeps what opened, without changing whether it was saved on purpose. Nothing is kept of a
    /// document that arrived empty: on this API an empty body is "unknown", never a document.
    private func keep(_ document: ViewableDocument) {
        guard let offline else { return }
        switch offline.keep(document, of: attachment, pin: nil) {
        case .notSaved(.noRoom):
            offlineNote = "Not kept for reading offline — the space for offline copies is taken by documents you saved."
        case .notSaved(.tooLarge):
            offlineNote = "Too large to keep for reading offline."
        default:
            offlineNote = nil
        }
    }
}

/// Where the search for a citation's quoted words landed.
struct QuoteSearchResult: Equatable, Sendable {
    /// The words, found among a scanned page's placed words or in the page's own text.
    enum Hit: Equatable, Sendable {
        /// One rectangle per line, top-left origin, the page as shown (`/page-words`'s space).
        case scanBoxes([QuoteBox])
        /// Which of the page's `\S+` runs (`CitedSource.wordRuns`) the quote covers.
        case textWords(ClosedRange<Int>)
    }

    /// The 1-based page to show: where the words are, or the cited page when they were not found.
    var page: Int
    /// The cited page, brought into the document.
    var target: Int
    var hit: Hit?
    /// Not found, and a page searched was a scan still being prepared.
    var pending = false
}

/// What the viewer says under the page about the citation.
struct CitedNote: Equatable, Sendable {
    var text: String
    /// Said on the warning wash: the words were elsewhere, or not found.
    var isWarning: Bool
}
