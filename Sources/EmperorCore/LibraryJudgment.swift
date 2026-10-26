import Foundation

/// A judgment's header card (`/judgment`, `header`).
struct LibraryJudgmentHeader: Decodable, Hashable, Sendable {
    var court: String?
    var courtLabel: String?
    var title: String?
    var petitioner: String?
    var respondent: String?
    var caseNumber: String?
    var caseType: String?
    /// A day in India.
    var decidedOn: String?
    var year: Int?
    var bench: [String]?
    var author: String?
    var citations: [String]?
    var neutralCitation: String?
    var source: String?
    var citesCount: Int?
    var citedByCount: Int?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case court, courtLabel, title, petitioner, respondent, caseNumber, caseType, decidedOn, year,
             bench, author, citations, neutralCitation, source, citesCount, citedByCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        court = c.libraryString(.court)
        courtLabel = c.libraryString(.courtLabel)
        title = c.libraryString(.title)
        petitioner = c.libraryString(.petitioner)
        respondent = c.libraryString(.respondent)
        caseNumber = c.libraryString(.caseNumber)
        caseType = c.libraryString(.caseType)
        decidedOn = c.libraryString(.decidedOn)
        year = c.libraryInt(.year)
        if let list = c.libraryArray(String.self, .bench) {
            bench = list
        } else if let text = c.libraryString(.bench) {
            bench = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        author = c.libraryString(.author)
        citations = c.libraryArray(String.self, .citations)
        neutralCitation = c.libraryString(.neutralCitation)
        source = c.libraryString(.source)
        citesCount = c.libraryInt(.citesCount)
        citedByCount = c.libraryInt(.citedByCount)
    }
}

/// One typeset block of a judgment.
struct JudgmentBlock: Decodable, Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        case heading, para, quote, list, cause, meta, table
        /// A type this client does not know: drawn as a paragraph.
        case unknown(String)

        init(_ raw: String) {
            switch raw {
            case "heading": self = .heading
            case "para": self = .para
            case "quote": self = .quote
            case "list": self = .list
            case "cause": self = .cause
            case "meta": self = .meta
            case "table": self = .table
            default: self = .unknown(raw)
            }
        }
    }

    var id: String
    var kind: Kind
    var text: String
    /// 1 or 2, on a heading.
    var level: Int?
    /// The paragraph's own number, as printed — `12`, `12.1`.
    var n: String?
    var marker: String?
    var lines: [String]?
    /// `author`, `date` or `signature`, on a meta block.
    var role: String?

    init(id: String, kind: Kind, text: String, level: Int? = nil, n: String? = nil,
         marker: String? = nil, lines: [String]? = nil, role: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.level = level
        self.n = n
        self.marker = marker
        self.lines = lines
        self.role = role
    }

    private enum CodingKeys: String, CodingKey { case id, type, text, level, n, marker, lines, role }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.libraryString(.id) ?? UUID().uuidString
        kind = Kind(c.libraryString(.type) ?? "para")
        text = c.libraryString(.text) ?? ""
        level = c.libraryInt(.level)
        n = c.libraryString(.n)
        marker = c.libraryString(.marker)
        lines = c.libraryArray(String.self, .lines)
        role = c.libraryString(.role)
    }

    /// What the reader shows, and what find searches (`blockText`, `readerModel.js`).
    var searchableText: String {
        switch kind {
        case .cause, .table: return (lines ?? [text]).joined(separator: "\n")
        case .meta where lines != nil: return (lines ?? []).joined(separator: "\n")
        default: return text
        }
    }
}

/// An entry of a judgment's contents.
struct JudgmentTOCEntry: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var label: String
    var level: Int

    init(id: String, label: String, level: Int) {
        self.id = id
        self.label = label
        self.level = level
    }

    private enum CodingKeys: String, CodingKey { case id, label, level }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.libraryString(.id) ?? ""
        label = c.libraryString(.label) ?? ""
        level = c.libraryInt(.level) ?? 1
    }
}

struct JudgmentStats: Decodable, Hashable, Sendable {
    var paragraphs: Int?
    var words: Int?
    var blocks: Int?
}

/// A structured judgment (`/judgment`).
struct LibraryJudgment: Decodable, Hashable, Sendable {
    var doc: LibraryDoc?
    var header: LibraryJudgmentHeader?
    var blocks: [JudgmentBlock] = []
    var toc: [JudgmentTOCEntry] = []
    var stats: JudgmentStats?

    init(doc: LibraryDoc? = nil, header: LibraryJudgmentHeader? = nil, blocks: [JudgmentBlock] = [],
         toc: [JudgmentTOCEntry] = [], stats: JudgmentStats? = nil) {
        self.doc = doc
        self.header = header
        self.blocks = blocks
        self.toc = toc
        self.stats = stats
    }

    private enum CodingKeys: String, CodingKey { case doc, header, blocks, toc, stats }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        doc = try? c.decodeIfPresent(LibraryDoc.self, forKey: .doc)
        header = try? c.decodeIfPresent(LibraryJudgmentHeader.self, forKey: .header)
        blocks = try c.decodeIfPresent([JudgmentBlock].self, forKey: .blocks) ?? []
        toc = c.libraryArray(JudgmentTOCEntry.self, .toc) ?? []
        stats = try? c.decodeIfPresent(JudgmentStats.self, forKey: .stats)
    }
}

/// The judgment reader's pure rules, ported from `caselaw/readerModel.js` and
/// `src/lib/judgmentDoc.js`: the plain-text fallback, find, and paragraph lookup.
enum JudgmentText {

    /// The reader opens a judgment's plain text up to this size (`MAX_READER_BYTES`).
    static let maxReaderBytes = 4 * 1024 * 1024

    /// `parseJudgmentText`: the stored text's header line block dropped, the site's "[Cites N]"
    /// furniture removed, then paragraphs split on blank lines.
    static func paragraphs(fromStoredText raw: String) -> [String] {
        var src = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let ns = src as NSString
        let headerEnd = ns.range(of: "\n===")
        if headerEnd.location != NSNotFound, headerEnd.location < 800 {
            let ruleEnd = ns.range(of: "\n", range: NSRange(location: headerEnd.location + 1, length: ns.length - headerEnd.location - 1))
            src = ruleEnd.location == NSNotFound ? "" : ns.substring(from: ruleEnd.location + 1)
        }
        src = LibraryDisplay.Pattern("^\\s*\\[Cites[\\s\\S]{0,80}?\\]\\s*", caseInsensitive: true).replaceFirst(src, "")
        return splitPlainText(src)
    }

    /// `splitPlainText`: blank lines end a paragraph; a single line break inside one is a space.
    static func splitPlainText(_ text: String) -> [String] {
        LibraryDisplay.Pattern("\\n\\s*\\n+").split(text).map { block in
            let joined = block.components(separatedBy: "\n").map { JSCompat.trim($0) }.filter { !$0.isEmpty }
                .joined(separator: " ")
            return JSCompat.trim(LibraryDisplay.Pattern("\\s{2,}").replaceAll(joined, " "))
        }.filter { !$0.isEmpty }
    }

    private static let paraNumber = LibraryDisplay.Pattern("^\\s*([0-9]{1,3}(?:\\.[0-9]{1,2})?)\\s*[.)]\\s+(?=\\S)")

    /// `blocksFromPlain`: a leading "12." becomes the paragraph's number, the first time it is seen.
    static func blocks(fromParagraphs paragraphs: [String]) -> [JudgmentBlock] {
        var seen = Set<String>()
        return paragraphs.enumerated().map { i, p in
            if let g = paraNumber.groups(p), let whole = g[0], let n = g[1], !seen.contains(n) {
                seen.insert(n)
                let rest = (p as NSString).substring(from: (whole as NSString).length)
                return JudgmentBlock(id: "para-\(n)", kind: .para, text: rest, n: n)
            }
            return JudgmentBlock(id: "b-\(i)", kind: .para, text: p)
        }
    }

    /// One match of find: the block's index, and the UTF-16 range in its text.
    struct Hit: Equatable, Sendable {
        let block: Int
        let start: Int
        let end: Int
    }

    /// `computeHits`: the phrase as typed, case-insensitive, at most `limit` matches.
    static func hits(in blocks: [JudgmentBlock], query: String, limit: Int = 3000) -> (hits: [Hit], capped: Bool) {
        let q = JSCompat.trim(query)
        guard q.utf16.count >= 2, !blocks.isEmpty else { return ([], false) }
        let term = JSCompat.trim(q.replacingOccurrences(of: "\"", with: ""))
        guard term.utf16.count >= 2 else { return ([], false) }
        var out: [Hit] = []
        for (bi, block) in blocks.enumerated() where out.count < limit {
            let text = block.searchableText as NSString
            var from = 0
            while from < text.length, out.count < limit {
                let r = text.range(of: term, options: [.caseInsensitive], range: NSRange(location: from, length: text.length - from))
                guard r.location != NSNotFound, r.length > 0 else { break }
                out.append(Hit(block: bi, start: r.location, end: r.location + r.length))
                from = r.location + r.length
            }
        }
        return (out, out.count >= limit)
    }

    /// `findPara`: the block numbered `n`, else the first numbered at or after it; `nil` for none.
    static func paragraphIndex(_ blocks: [JudgmentBlock], _ n: String) -> Int? {
        let want = JSCompat.trim(n)
        guard !want.isEmpty else { return nil }
        if let exact = blocks.firstIndex(where: { $0.n == want }) { return exact }
        guard let num = parseFloatPrefix(want) else { return nil }
        return blocks.firstIndex { b in
            guard let bn = b.n, let v = parseFloatPrefix(bn) else { return false }
            return v >= num
        }
    }

    /// `parseFloat`: the leading number of a string, or `nil`.
    static func parseFloatPrefix(_ s: String) -> Double? {
        guard let g = LibraryDisplay.Pattern("^\\s*[-+]?([0-9]+\\.?[0-9]*|\\.[0-9]+)").groups(s), let whole = g[0] else { return nil }
        return Double(JSCompat.trim(whole))
    }
}
