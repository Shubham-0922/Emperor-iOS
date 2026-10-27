import Foundation
#if canImport(Darwin)
import Observation
#endif

// Assembling a filing from the draft on screen in a conversation, rather than from a saved draft
// picked from a list (`src/pages/FilingAssembly.jsx`, its inline mode). The rules here are the
// page's own and held to its code by `FilingGoldenTests` (`scripts/generate-filing-fixtures.mjs`).

/// Where Filing Assembly starts: the list of saved drafts, one saved draft already chosen, or the
/// draft of a conversation.
enum FilingScope: Equatable, Sendable {
    case pick
    case draft(FilingDraft)
    case chat(FilingChatContext)
}

extension FilingDraft {
    /// A saved draft from the drafts list, as filing reads it.
    init(_ item: DraftedItem) {
        self.init(
            id: item.id, title: item.title, type: item.type, createdAtRaw: item.createdAtRaw,
            chatID: item.chatID)
    }
}

extension FilingAnnexure {
    /// How a card under the draft names the annexure's form.
    var cardForm: String { isTyped ? "typed copy" : "original" }

    /// "same file as P-1" when this mark repeats an earlier one's file and pages.
    var duplicateNote: String? {
        guard let duplicateOf, !duplicateOf.isEmpty else { return nil }
        return "same file as \(duplicateOf)"
    }

    /// "Annexure P-2 — Notice under Section 8".
    var viewerTitle: String { "Annexure \(mark) — \(title)" }
}

/// The List of Annexures under a finished draft: the conversation's annexures, read once. A
/// register that cannot be read shows nothing rather than an error, as on the web.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class FilingAnnexureCardsModel {
    static let title = "List of Annexures"
    static let caption = "Attached annexures below will download along with the entire petition."

    private(set) var rows: [FilingAnnexure] = []
    private(set) var hasLoaded = false

    private let service: any FilingProviding
    let chatID: String

    init(service: any FilingProviding, chatID: String) {
        self.service = service
        self.chatID = chatID
    }

    func load() async {
        rows = (try? await service.annexures(chatID: chatID)) ?? []
        hasLoaded = true
    }
}

/// One annexure opened from its card: its typed copy, or its original — a PDF of its pages or
/// an image — read only when it is opened.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class FilingAnnexureViewerModel {
    enum Content: Equatable {
        case loading
        case typed(String)
        case message(String)
        case pdf(Data)
        case image(Data)
        case unpreviewable
    }

    static let couldNotLoad = "Could not load this annexure."
    static let unpreviewable =
        "This file type can't be previewed here — use \"Assemble filing\" for the combined paperbook, or \"Download\" for the appended copy."

    let annexure: FilingAnnexure
    private(set) var content: Content = .loading

    private let service: any FilingProviding
    private let chatID: String

    init(service: any FilingProviding, chatID: String, annexure: FilingAnnexure) {
        self.service = service
        self.chatID = chatID
        self.annexure = annexure
    }

    var title: String { annexure.viewerTitle }

    func load() async {
        content = .loading
        if annexure.isTyped {
            content = await typedContent()
        } else {
            content = await originalContent()
        }
    }

    private func typedContent() async -> Content {
        do {
            let copy = try await service.typedCopy(chatID: chatID, mark: annexure.mark)
            if copy.skipped {
                let reason = copy.reason ?? ""
                return .message(reason.isEmpty ? Self.couldNotLoad : reason)
            }
            if let html = copy.html, !html.isEmpty { return .typed(html) }
            return .message(Self.couldNotLoad)
        } catch {
            if case .server(_, let message)? = error as? APIError, !message.isEmpty {
                return .message(message)
            }
            return .message(Self.couldNotLoad)
        }
    }

    private func originalContent() async -> Content {
        do {
            let original = try await service.original(chatID: chatID, mark: annexure.mark)
            if original.isPDF { return .pdf(original.data) }
            if original.isImage { return .image(original.data) }
            return .unpreviewable
        } catch {
            // Without a connection the file's kind is not the reason; anything the server
            // refused is said as the page says it.
            if case .transport? = error as? APIError { return .message(Self.couldNotLoad) }
            return .unpreviewable
        }
    }
}

extension FilingChatContext {
    /// Bundles assembled from this conversation are listed under this draft id.
    var bundleKey: String { "chat:\(chatID)" }
}

enum FilingChatScope {

    /// The sheet's title and its lead, as the page words them.
    static let title = "Assemble court-ready filing"

    static func lead(for draftTitle: String) -> String {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "this draft" : trimmed
        return "Assembling \(name) and its annexures into a court-ready, paginated bundle with cover, index and list of annexures."
    }

    static let seedTitle = "Documents attached to this chat"

    /// What filing needs from a drafted document in a conversation, or `nil` where it does not
    /// apply: a table, or an answer not yet in a stored conversation. The draft is sent as HTML
    /// and clean — a court filing carries no citation numbers.
    static func context(
        for artifact: StreamArtifact, chatID: String?, attachments: [ChatAttachment]
    ) -> FilingChatContext? {
        guard artifact.kind == .canvas, let chatID, !chatID.isEmpty else { return nil }
        let clean = stripMentions(DraftCitations.withoutMarkers(artifact.body))
        let html = artifact.format == .html ? clean : MarkdownHTML.html(from: clean)
        return FilingChatContext(
            chatID: chatID, draftTitle: artifact.title, draftHTML: html, attachments: attachments)
    }

    // MARK: - Chat files

    /// Every file the conversation's questions carried, once each, in the order first sent. A
    /// file is its folder and its name together: two files of one name in two folders are two
    /// documents.
    static func attachments(in messages: [ChatMessage]) -> [ChatAttachment] {
        var seen = Set<String>()
        var out: [ChatAttachment] = []
        for message in messages {
            for file in ChatAttachment.list(from: message.attachments) {
                let key = (file.folderName ?? "") + "\u{0}" + file.name
                if seen.insert(key).inserted { out.append(file) }
            }
        }
        return out
    }

    /// The conversation's files that are not yet annexures, offered one tap each. An annexure's
    /// stored path ends in `<folder>/<name>`; only a file sent without a folder is matched on its
    /// name alone.
    static func unannexed(attachments: [ChatAttachment], annexurePaths: [String]) -> [ChatAttachment] {
        attachments.filter { file in
            guard !file.name.isEmpty else { return false }
            let folder = file.folderName ?? ""
            if folder.isEmpty {
                return !annexurePaths.contains { baseName($0) == file.name }
            }
            let tail = folder + "/" + file.name
            return !annexurePaths.contains { $0 == tail || $0.hasSuffix("/" + tail) }
        }
    }

    private static func baseName(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? path
    }

    // MARK: - Mentions

    /// `<@file.pdf:P-2>` / `<@file.pdf:P-2:41-45>` — how a draft names the file behind a mark.
    private static let mentionRegex = try! NSRegularExpression(
        pattern: "<@([^:>]+):([A-Za-z]+-[0-9]+)(?::([0-9]+)(?:-([0-9]+))?)?>")

    /// The draft without its annexure mentions, the words around them kept.
    static func stripMentions(_ content: String) -> String {
        let range = NSRange(location: 0, length: (content as NSString).length)
        return mentionRegex.stringByReplacingMatches(
            in: content, options: [], range: range, withTemplate: "")
    }

    // MARK: - Cover

    /// JavaScript's `\s`, which is wider than ICU's; spelled out so the two read the same text.
    private static let ws =
        "\\t\\n\\u000B\\f\\r \\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF"

    private static func regex(_ pattern: String, caseInsensitive: Bool) -> NSRegularExpression {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        return try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let tagRegex = regex("<[^>]+>", caseInsensitive: false)
    private static let spaceRunRegex = regex("[" + ws + "]+", caseInsensitive: false)
    private static let edgeSpaceRegex = regex("^[" + ws + "]+|[" + ws + "]+\\z", caseInsensitive: false)

    private static let forumRegex: NSRegularExpression = {
        let body = "[A-Z][A-Za-z0-9 ,.'’&()\\-]+?"
        let ends = "(?:COURT|TRIBUNAL|COMMISSION|BOARD|AUTHORITY|FORUM|APPELLATE TRIBUNAL)"
        let pattern: String = "IN THE[" + ws + "]+(" + body + ends + ")"
        return regex(pattern, caseInsensitive: true)
    }()

    private static let caseNumberRegex: NSRegularExpression = {
        let s = "[" + ws + "]"
        let kinds: [String] = [
            "C\\.?" + s + "?P\\.?", "W\\.?" + s + "?P\\.?", "CS", "SLP", "C\\.?" + s + "?A\\.?",
            "I\\.?" + s + "?A\\.?", "O\\.?" + s + "?M\\.?" + s + "?P\\.?", "COMPLAINT", "APPEAL",
            "PETITION", "APPLICATION",
        ]
        let head: String = "(?:" + kinds.joined(separator: "|") + ")"
        let tail: String = "[^,.\\n]{0,32}?No\\.?" + s + "*[:\\-]?" + s + "*[0-9IVXLC]+" + s
            + "*(?:of|\\/)" + s + "*[0-9]{2,4}"
        return regex("(" + head + tail + ")", caseInsensitive: true)
    }()

    private static let caseTypeRegex: NSRegularExpression = {
        let pattern: String = "^([A-Za-z." + ws + "()]+?)[" + ws + "]*No"
        return regex(pattern, caseInsensitive: true)
    }()

    private static let partiesRegex: NSRegularExpression = {
        let side = "[A-Z][A-Za-z0-9 .,&'’()\\-]"
        let s = "[" + ws + "]+"
        let pattern: String = "(" + side + "{2,70}?)" + s + "(?:versus|vs\\.?|v\\.)" + s + "(" + side + "{2,70})"
        return regex(pattern, caseInsensitive: false)
    }()

    /// The cover read back from the draft's cause title — "IN THE … COURT", a case number and
    /// "X versus Y" — so the advocate corrects rather than retypes. Best effort: anything not
    /// found is left empty.
    static func deriveCover(html: String) -> FilingCover {
        var text = replace(tagRegex, in: html, with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        text = trim(collapse(text))
        let ns = text as NSString
        let head = ns.length > 2500 ? ns.substring(to: 2500) : text

        var out = FilingCover()
        if let forum = firstGroup(forumRegex, in: head) {
            out.forum = forumName(forum)
        }
        if let number = firstGroup(caseNumberRegex, in: head) {
            out.caseNumber = trim(collapse(number))
            if let type = firstGroup(caseTypeRegex, in: out.caseNumber) {
                out.caseType = trim(collapse(type))
            }
        }
        if let pair = groups(partiesRegex, in: head), pair.count == 2 {
            let joined: String = trim(pair[0]) + " versus " + trim(pair[1])
            out.parties = collapse(joined)
        }
        return out
    }

    /// The forum as the page names it from what follows "IN THE".
    private static func forumName(_ raw: String) -> String {
        let upper = raw.uppercased()
        if upper.contains("APPELLATE"), upper.contains("COMPANY LAW") { return "NCLAT" }
        if upper.contains("COMPANY LAW TRIBUNAL") { return "NCLT" }
        if upper.contains("SUPREME COURT") { return "Supreme Court" }
        if upper.contains("HIGH COURT") { return titleCased(trim(collapse(raw))) }
        if upper.contains("DATA PROTECTION BOARD") { return "Data Protection Board of India" }
        return titleCased(trim(collapse(raw)))
    }

    /// Every letter or digit that begins an ASCII word upper-cased, as `/\b\w/g` does; the rest
    /// left as written.
    private static func titleCased(_ s: String) -> String {
        var units = Array(s.utf16)
        var previousIsWord = false
        for i in units.indices {
            let u = units[i]
            let isWord = isASCIIWord(u)
            if isWord, !previousIsWord, u >= 0x61, u <= 0x7A { units[i] = u - 0x20 }
            previousIsWord = isWord
        }
        return String(decoding: units, as: UTF16.self)
    }

    private static func isASCIIWord(_ u: UInt16) -> Bool {
        (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || u == 0x5F
    }

    private static func collapse(_ s: String) -> String { replace(spaceRunRegex, in: s, with: " ") }

    private static func trim(_ s: String) -> String { replace(edgeSpaceRegex, in: s, with: "") }

    private static func replace(_ re: NSRegularExpression, in s: String, with template: String) -> String {
        let range = NSRange(location: 0, length: (s as NSString).length)
        return re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: template)
    }

    private static func firstGroup(_ re: NSRegularExpression, in s: String) -> String? {
        groups(re, in: s)?.first
    }

    private static func groups(_ re: NSRegularExpression, in s: String) -> [String]? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length))
        else { return nil }
        return (1..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }
}
