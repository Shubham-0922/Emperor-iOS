import Foundation

/// A reference to one of the reader's own documents: which file, which page, which words.
///
/// Written by the model as `[3] Lease_Agreement.pdf, p. 12 — "the lessee shall pay…"`. `quote` is
/// `""` when the reference quotes nothing; `page` is `nil` when it names no page.
struct DocumentReference: Equatable, Hashable, Sendable {
    var file: String
    var page: Int?
    var quote: String
}

/// A word's box on a page, in PDF points with the origin at the top left of the page as shown —
/// how `/page-words` reports it.
struct QuoteBox: Equatable, Sendable {
    var x0: Double
    var y0: Double
    var x1: Double
    var y1: Double
}

/// The web's cited-source module (`src/lib/citedSource.js`), ported: reading a reference line,
/// listing an answer's cited documents, and finding quoted words among a page's words so the
/// viewer can mark them. Held to the module's own answers by `CitedSourceGoldenTests`
/// (`scripts/generate-cited-source-fixtures.mjs`).
///
/// The web's patterns are JavaScript's, so they are restated here with JavaScript's meanings:
/// `\s` is JavaScript's whitespace set, `\d` and `\b` are ASCII, and character offsets and
/// lengths are UTF-16 code units, as a JavaScript string counts them.
enum CitedSource {

    // MARK: - Reading a reference

    /// JavaScript's `\s`, as a character-class body for ICU.
    private static let space =
        #"\t\n\x{0B}\f\r \x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}"#

    nonisolated(unsafe) private static let fileRE = regex(
        #"([^"# + space + #""“”'‘’()\[\],;]+\.(?:pdf|docx?|odt|rtf|txt|png|jpe?g|tiff?))"#,
        caseInsensitive: true)
    nonisolated(unsafe) private static let pageRE = regex(
        #"(?<![A-Za-z0-9_])(?:pp?|pg|page)\.?["# + space + #"]*([0-9]{1,5})(?![A-Za-z0-9_])"#,
        caseInsensitive: true)
    nonisolated(unsafe) private static let quoteRE = regex(#"[“"‘']([^”"’]{6,600})[”"’']"#)
    nonisolated(unsafe) private static let tagRE = regex(#"<[^>]+>"#)
    nonisolated(unsafe) private static let markerRE = regex(#"[*`]"#)
    nonisolated(unsafe) private static let lineRE = regex(
        #"^["# + space + #"]*(?:[-*•]|[0-9]+\.)?["# + space + #"]*\[([0-9]+)\](?:["# + space
            + #"]*[:-]|["# + space + #"]+)([^\n\r\x{2028}\x{2029}]+)\z"#)
    nonisolated(unsafe) private static let nameRunRE = regex(#"["# + space + #"_]+"#)

    private static func regex(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        // The patterns are constants; a failure here is a programming error caught by the tests.
        try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    private static func firstMatch(_ re: NSRegularExpression, in s: NSString) -> NSTextCheckingResult? {
        re.firstMatch(in: s as String, options: [], range: NSRange(location: 0, length: s.length))
    }

    private static func replacing(_ re: NSRegularExpression, in s: String, with template: String) -> String {
        re.stringByReplacingMatches(
            in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length),
            withTemplate: template)
    }

    /// `parseDocumentReference`: the file, page and quote a reference names, or `nil` when it
    /// names no file of the reader's — a case citation, say.
    static func parse(_ text: String) -> DocumentReference? {
        // Bold and code markers come off; underscores stay — they are part of every stored name.
        let s = replacing(markerRE, in: replacing(tagRE, in: text, with: " "), with: "") as NSString
        guard let f = firstMatch(fileRE, in: s) else { return nil }
        let file = s.substring(with: f.range(at: 1))
        let rest = s.substring(from: NSMaxRange(f.range)) as NSString
        let page = (firstMatch(pageRE, in: rest).map { (rest, $0) } ?? firstMatch(pageRE, in: s).map { (s, $0) })
            .flatMap { source, match in Int(source.substring(with: match.range(at: 1))) }
        let quote = firstMatch(quoteRE, in: rest).map { jsTrim(rest.substring(with: $0.range(at: 1))) } ?? ""
        return DocumentReference(file: file, page: page, quote: quote)
    }

    /// `citedDocs`: the document references in an answer, one per reference line, in order, with
    /// a repeat of the same file, page and opening words left out.
    static func citedDocs(_ content: String) -> [(number: Int, ref: DocumentReference)] {
        var out: [(number: Int, ref: DocumentReference)] = []
        var seen = Set<String>()
        // Split on UTF-16 newlines, as JavaScript does: Swift sees "\r\n" as one character and
        // would not split there.
        let units = Array(content.utf16)
        let lines = units.split(separator: 0x0A, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF16.self) }
        for line in lines {
            let ns = line as NSString
            guard let m = firstMatch(lineRE, in: ns),
                  let number = Int(ns.substring(with: m.range(at: 1))),
                  let ref = parse(ns.substring(with: m.range(at: 2)))
            else { continue }
            let quoteKey = String(decoding: Array(normName(ref.quote).utf16.prefix(48)), as: UTF16.self)
            let key = "\(normName(ref.file))#\(ref.page.flatMap { $0 == 0 ? nil : $0 }.map(String.init) ?? "")#\(quoteKey)"
            guard seen.insert(key).inserted else { continue }
            out.append((number, ref))
        }
        return out
    }

    private static func normName(_ s: String) -> String {
        replacing(nameRunRE, in: s, with: "_").lowercased()
    }

    // MARK: - Matching a quote to words

    /// `normChars`: NFC, Devanagari digits as ASCII, lower case, and nothing but letters, marks
    /// and digits — punctuation, curly quotes, dashes, spaces and joiners all differ between a
    /// model's quotation and the page.
    static func normChars(_ s: String) -> String {
        var mapped = String.UnicodeScalarView()
        for scalar in s.precomposedStringWithCanonicalMapping.unicodeScalars {
            if (0x966...0x96F).contains(scalar.value), let digit = Unicode.Scalar(scalar.value - 0x966 + 0x30) {
                mapped.append(digit)
            } else {
                mapped.append(scalar)
            }
        }
        var kept = String.UnicodeScalarView()
        for scalar in String(mapped).lowercased().unicodeScalars where isLetterMarkOrNumber(scalar) {
            kept.append(scalar)
        }
        return String(kept)
    }

    private static func isLetterMarkOrNumber(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    /// `findQuoteRange`: the words (inclusive indices into `words`, in reading order) the quote
    /// covers, or `nil`. Exact first; then the quote's opening and closing stretches as anchors,
    /// so a quotation right at both ends but off by a word in the middle still lands; then the
    /// densest window of the quote's words.
    static func findQuoteRange(words: [String], quote: String) -> ClosedRange<Int>? {
        let q = Array(normChars(quote).utf16)
        guard !q.isEmpty, !words.isEmpty else { return nil }
        var stream: [UInt16] = []
        var owner: [Int] = []
        for (i, word) in words.enumerated() {
            let c = Array(normChars(word).utf16)
            stream += c
            owner += Array(repeating: i, count: c.count)
        }
        guard !stream.isEmpty else { return nil }
        func span(_ a: Int, _ b: Int) -> ClosedRange<Int> {
            let start = owner[max(0, a)], end = owner[min(owner.count - 1, b)]
            return min(start, end)...max(start, end)
        }

        if let exact = indexOf(q[...], in: stream, from: 0) {
            return span(exact, exact + q.count - 1)
        }

        let l = min(24, q.count / 2)
        if l >= 6 {
            let head = indexOf(q[0..<l], in: stream, from: 0)
            let tail = indexOf(q[(q.count - l)...], in: stream, from: head ?? 0)
            if let head, let tail, tail - head < q.count * 2 { return span(head, tail + l - 1) }
            if let head { return span(head, head + q.count - 1) }
            if let tail { return span(tail + l - q.count, tail + l - 1) }
        }

        let qWords = jsSplitOnSpace(quote).map(normChars).filter { $0.utf16.count >= 3 }
        guard qWords.count >= 2 else { return nil }
        let want = Set(qWords)
        let keys = words.map(normChars)
        let n = max(qWords.count, 2)
        var best: (hits: Int, start: Int, end: Int)?
        var i = 0
        while i + n <= keys.count {
            var hits = 0
            for k in i..<(i + n) where want.contains(keys[k]) { hits += 1 }
            if best == nil || hits > best!.hits { best = (hits, i, i + n - 1) }
            i += 1
        }
        let needed = Int((Double(qWords.count) * 0.5).rounded(.up))
        guard let best, best.hits >= needed else { return nil }
        return best.start...best.end
    }

    /// `String.prototype.indexOf` on UTF-16 code units.
    private static func indexOf(_ needle: ArraySlice<UInt16>, in hay: [UInt16], from: Int) -> Int? {
        let n = needle.count
        guard n > 0 else { return min(max(from, 0), hay.count) }
        guard hay.count >= n else { return nil }
        var i = max(from, 0)
        let first = needle[needle.startIndex]
        while i + n <= hay.count {
            if hay[i] == first, hay[i..<(i + n)].elementsEqual(needle) { return i }
            i += 1
        }
        return nil
    }

    /// `lineRects`: one rectangle per visual line across the boxes in `range`, so a quote that
    /// wraps is marked line by line rather than as one block spanning the gap.
    static func lineRects(_ boxes: [QuoteBox], _ range: ClosedRange<Int>) -> [QuoteBox] {
        var out: [QuoteBox] = []
        for i in range where i >= 0 && i < boxes.count {
            let b = boxes[i]
            let h = b.y1 - b.y0
            if var last = out.last,
               abs((last.y0 + last.y1) / 2 - (b.y0 + b.y1) / 2) < h * 0.6, b.x0 >= last.x0 - h {
                last.x0 = min(last.x0, b.x0); last.y0 = min(last.y0, b.y0)
                last.x1 = max(last.x1, b.x1); last.y1 = max(last.y1, b.y1)
                out[out.count - 1] = last
            } else {
                out.append(b)
            }
        }
        return out
    }

    // MARK: - The viewer's search

    /// The pages to look on, in order: the cited page, then one either side — a model's page
    /// number can be off by one. The cited page is first brought into the document.
    static func searchOrder(target: Int, pageCount: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        let t = min(pageCount, max(1, target))
        return [t, t - 1, t + 1].filter { $0 >= 1 && $0 <= pageCount }
    }

    /// What the viewer says about a search for quoted words, in the web's words
    /// (`PdfCitePane.jsx`): nothing when they were found on the cited page.
    static func note(target: Int, foundOn: Int?, pending: Bool) -> String? {
        if let foundOn {
            return foundOn == target
                ? nil
                : "The quoted words are on page \(foundOn); the citation said page \(target)."
        }
        return pending
            ? "This scanned document is still being prepared for highlighting. Showing the cited page; try again in a minute or two."
            : "Couldn’t find the quoted words on page \(target). Showing the cited page."
    }

    /// The `\S+` runs of a page's text with their UTF-16 ranges — the words of a page that has a
    /// text layer of its own, and where each one is so it can be selected.
    static func wordRuns(_ text: String) -> [(word: String, range: NSRange)] {
        let ns = text as NSString
        var out: [(word: String, range: NSRange)] = []
        var start: Int?
        for i in 0...ns.length {
            let isSpace = i == ns.length || isJSSpace(ns.character(at: i))
            if isSpace, let s = start {
                let range = NSRange(location: s, length: i - s)
                out.append((ns.substring(with: range), range))
                start = nil
            } else if !isSpace, start == nil {
                start = i
            }
        }
        return out
    }

    /// A box from `/page-words` (top-left origin, the page as shown) in PDF page space: bottom-left
    /// origin, unrotated, offset by the crop box — what a PDF annotation is placed in.
    /// `rotation` is the page's own, in degrees clockwise.
    static func pageSpace(
        _ box: QuoteBox, cropX: Double, cropY: Double, cropWidth w: Double, cropHeight h: Double,
        rotation: Int
    ) -> QuoteBox {
        func point(_ u: Double, _ v: Double) -> (Double, Double) {
            switch ((rotation % 360) + 360) % 360 {
            case 90: return (v, u)
            case 180: return (w - u, v)
            case 270: return (w - v, h - u)
            default: return (u, h - v)
            }
        }
        let a = point(box.x0, box.y0), b = point(box.x1, box.y1)
        return QuoteBox(
            x0: cropX + min(a.0, b.0), y0: cropY + min(a.1, b.1),
            x1: cropX + max(a.0, b.0), y1: cropY + max(a.1, b.1))
    }

    // MARK: - JavaScript's whitespace

    static func isJSSpace(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
             0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    /// `String.prototype.trim`.
    static func jsTrim(_ s: String) -> String {
        var units = Array(s.utf16)[...]
        while let f = units.first, isJSSpace(f) { units = units.dropFirst() }
        while let l = units.last, isJSSpace(l) { units = units.dropLast() }
        return String(decoding: units, as: UTF16.self)
    }

    /// `s.split(/\s+/)`, empty pieces included as JavaScript leaves them.
    private static func jsSplitOnSpace(_ s: String) -> [String] {
        var pieces: [String] = []
        var current: [UInt16] = []
        var inSpace = false
        for unit in s.utf16 {
            if isJSSpace(unit) {
                if !inSpace { pieces.append(String(decoding: current, as: UTF16.self)); current = [] }
                inSpace = true
            } else {
                current.append(unit)
                inSpace = false
            }
        }
        pieces.append(String(decoding: current, as: UTF16.self))
        return pieces
    }
}
