import Foundation

/// The handful of JavaScript conversions the analysis pages lean on, restated so the Swift ports
/// of their shaping code (`DevilsAdvocateReport`, `DocIndex`, `DateChart`) read a model's answer
/// exactly as the web does: what `String(v)`, `Number(v)`, `trim()`, truthiness, `Math.round` and
/// a UTF-16 `slice` make of it. Held to the platform by the analysis golden fixtures.
enum AnalysisJS {

    // MARK: - Strings

    /// The characters `String.prototype.trim` removes: ECMAScript WhiteSpace and LineTerminator.
    private static let jsSpace: Set<Unicode.Scalar> = {
        var set: Set<Unicode.Scalar> = [
            "\u{09}", "\u{0A}", "\u{0B}", "\u{0C}", "\u{0D}", "\u{20}", "\u{A0}", "\u{1680}",
            "\u{2028}", "\u{2029}", "\u{202F}", "\u{205F}", "\u{3000}", "\u{FEFF}",
        ]
        for v in 0x2000...0x200A { if let s = Unicode.Scalar(v) { set.insert(s) } }
        return set
    }()

    /// Whether `scalar` is what a JavaScript regular expression's `\s` matches.
    static func isSpace(_ scalar: Unicode.Scalar) -> Bool { jsSpace.contains(scalar) }

    /// `s.trim()`.
    static func trim(_ s: String) -> String {
        let scalars = s.unicodeScalars
        guard let first = scalars.firstIndex(where: { !jsSpace.contains($0) }) else { return "" }
        let last = scalars.lastIndex(where: { !jsSpace.contains($0) })!
        return String(scalars[first...last])
    }

    /// `s.trimEnd()`.
    static func trimEnd(_ s: String) -> String {
        let scalars = s.unicodeScalars
        guard let last = scalars.lastIndex(where: { !jsSpace.contains($0) }) else { return "" }
        return String(scalars[...last])
    }

    /// `s.length`: UTF-16 code units, as JavaScript counts.
    static func length(_ s: String) -> Int { s.utf16.count }

    /// `s.slice(0, n)`, counted in UTF-16 code units.
    static func prefix(_ s: String, _ n: Int) -> String {
        guard s.utf16.count > n else { return s }
        return String(decoding: Array(s.utf16.prefix(max(0, n))), as: UTF16.self)
    }

    /// `s.replace(/\s+/g, ' ')`.
    static func collapseSpaces(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var inSpace = false
        for scalar in s.unicodeScalars {
            if jsSpace.contains(scalar) {
                if !inSpace { out.append(" ") }
                inSpace = true
            } else {
                out.append(scalar)
                inSpace = false
            }
        }
        return String(out)
    }

    // MARK: - Numbers

    /// `String(n)` for a number: integers without a decimal point, everything else in the
    /// shortest form that reads back as the same number.
    static func string(_ n: Double) -> String {
        if n.isNaN { return "NaN" }
        if n.isInfinite { return n < 0 ? "-Infinity" : "Infinity" }
        if n == 0 { return "0" }
        if n == n.rounded(), abs(n) < 1e21 {
            return String(format: "%.0f", n)
        }
        var text = "\(n)"
        // Swift writes "1e-07" where JavaScript writes "1e-7".
        if let e = text.firstIndex(of: "e") {
            let mantissa = text[..<e]
            var exponent = String(text[text.index(after: e)...])
            var sign = "+"
            if exponent.hasPrefix("-") { sign = "-"; exponent.removeFirst() }
            else if exponent.hasPrefix("+") { exponent.removeFirst() }
            while exponent.count > 1, exponent.hasPrefix("0") { exponent.removeFirst() }
            text = "\(mantissa)e\(sign)\(exponent)"
        }
        return text
    }

    /// `Math.round(n)`: halves go up, towards positive infinity.
    static func round(_ n: Double) -> Double {
        let floor = n.rounded(.down)
        return n - floor >= 0.5 ? floor + 1 : floor
    }

    /// `Number(s)` for a string: blank is 0, a decimal literal is its value, anything else NaN.
    static func number(_ s: String) -> Double {
        let t = trim(s)
        if t.isEmpty { return 0 }
        let lower = t.lowercased()
        if lower.hasPrefix("0x") || lower.hasPrefix("0o") || lower.hasPrefix("0b") {
            let radix = lower.hasPrefix("0x") ? 16 : lower.hasPrefix("0o") ? 8 : 2
            return Int(t.dropFirst(2), radix: radix).map(Double.init) ?? .nan
        }
        switch t {
        case "Infinity", "+Infinity": return .infinity
        case "-Infinity": return -.infinity
        default: break
        }
        guard isDecimalLiteral(t), let value = Double(t) else { return .nan }
        return value
    }

    private static func isDecimalLiteral(_ t: String) -> Bool {
        var chars = Array(t.unicodeScalars)
        if let first = chars.first, first == "+" || first == "-" { chars.removeFirst() }
        var i = 0
        var digits = 0
        while i < chars.count, ("0"..."9").contains(chars[i]) { i += 1; digits += 1 }
        if i < chars.count, chars[i] == "." {
            i += 1
            while i < chars.count, ("0"..."9").contains(chars[i]) { i += 1; digits += 1 }
        }
        guard digits > 0 else { return false }
        if i < chars.count, chars[i] == "e" || chars[i] == "E" {
            i += 1
            if i < chars.count, chars[i] == "+" || chars[i] == "-" { i += 1 }
            var exponentDigits = 0
            while i < chars.count, ("0"..."9").contains(chars[i]) { i += 1; exponentDigits += 1 }
            guard exponentDigits > 0 else { return false }
        }
        return i == chars.count
    }

    /// `Number(v)` for any JSON value.
    static func number(_ v: JSONValue?) -> Double {
        guard let v else { return .nan }
        switch v {
        case .null: return 0
        case .bool(let b): return b ? 1 : 0
        case .number(let n): return n
        case .string(let s): return number(s)
        case .array(let items):
            if items.isEmpty { return 0 }
            if items.count == 1 { return number(string(items[0])) }
            return .nan
        case .object: return .nan
        }
    }

    /// `String(v)` for any JSON value. `nil` is `undefined`.
    static func string(_ v: JSONValue?) -> String {
        guard let v else { return "undefined" }
        switch v {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return string(n)
        case .string(let s): return s
        case .array(let items):
            return items.map { item -> String in
                if case .null = item { return "" }
                return string(item)
            }.joined(separator: ",")
        case .object: return "[object Object]"
        }
    }

    /// Whether JavaScript reads `v` as true.
    static func truthy(_ v: JSONValue?) -> Bool {
        guard let v else { return false }
        switch v {
        case .null: return false
        case .bool(let b): return b
        case .number(let n): return n != 0 && !n.isNaN
        case .string(let s): return !s.isEmpty
        case .array, .object: return true
        }
    }

    /// `v && typeof v === 'object'`: an object or an array.
    static func isObjectLike(_ v: JSONValue?) -> Bool {
        switch v {
        case .object?, .array?: return true
        default: return false
        }
    }

    /// The object's fields, or none for anything else — an array read as an object has no named
    /// fields worth reading here.
    static func fields(_ v: JSONValue?) -> [String: JSONValue] {
        if case .object(let o)? = v { return o }
        return [:]
    }

    // MARK: - Comparing

    /// `a.localeCompare(b, 'en', { numeric: true, sensitivity: 'base' })`, as ICU's root collation
    /// orders text at primary strength: spaces and punctuation, then symbols, then digits (a run of
    /// digits by its value), then letters, with case and accents ignored.
    ///
    /// Restated rather than delegated to Foundation, whose locale-aware comparison is not the same
    /// collator on every platform this code runs on.
    static func localeCompare(_ a: String, _ b: String) -> Int {
        let x = collationKeys(a)
        let y = collationKeys(b)
        for (p, q) in zip(x, y) {
            if p != q { return p < q ? -1 : 1 }
        }
        return x.count == y.count ? 0 : (x.count < y.count ? -1 : 1)
    }

    /// One primary weight: a group, then a value within it, then the digits of a number.
    private struct CollationKey: Comparable {
        var group: Int
        var value: UInt32
        var digits: [UInt8] = []

        static func < (l: CollationKey, r: CollationKey) -> Bool {
            if l.group != r.group { return l.group < r.group }
            if l.group == 3 {
                if l.digits.count != r.digits.count { return l.digits.count < r.digits.count }
                return l.digits.lexicographicallyPrecedes(r.digits)
            }
            return l.value < r.value
        }
    }

    /// CLDR root order of the ASCII punctuation and symbols, which is where model-written text
    /// differs from code-point order.
    private static let punctuationOrder: [Unicode.Scalar: UInt32] = {
        let order: [Unicode.Scalar] = [
            "_", "-", ",", ";", ":", "!", "?", ".", "'", "\"", "(", ")", "[", "]", "{", "}",
            "@", "*", "/", "\\", "&", "#", "%", "`", "^", "+", "<", "=", ">", "|", "~", "$",
        ]
        var map: [Unicode.Scalar: UInt32] = [:]
        for (i, s) in order.enumerated() { map[s] = UInt32(i) }
        // Typographic forms sort beside their plain ones.
        map["\u{2019}"] = map["'"]; map["\u{2018}"] = map["'"]
        map["\u{201C}"] = map["\""]; map["\u{201D}"] = map["\""]
        map["\u{2013}"] = map["-"]; map["\u{2014}"] = map["-"]
        return map
    }()

    private static func collationKeys(_ s: String) -> [CollationKey] {
        // Accents go: the base letter is what a primary comparison sees.
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var keys: [CollationKey] = []
        var digits: [UInt8] = []
        func flush() {
            guard !digits.isEmpty else { return }
            var trimmed = Array(digits.drop { $0 == 0 })
            if trimmed.isEmpty { trimmed = [0] }
            keys.append(CollationKey(group: 3, value: 0, digits: trimmed))
            digits = []
        }
        for scalar in folded.unicodeScalars {
            if ("0"..."9").contains(scalar) {
                digits.append(UInt8(scalar.value - 48))
                continue
            }
            flush()
            if jsSpace.contains(scalar) {
                keys.append(CollationKey(group: 0, value: scalar == " " ? 0 : scalar.value))
            } else if let rank = punctuationOrder[scalar] {
                keys.append(CollationKey(group: 1, value: rank))
            } else if scalar.properties.isAlphabetic {
                keys.append(CollationKey(group: 4, value: scalar.value))
            } else if scalar.properties.generalCategory == .nonspacingMark {
                continue
            } else {
                keys.append(CollationKey(group: 2, value: scalar.value))
            }
        }
        flush()
        return keys
    }

    /// Sorts stably by a three-way comparison, as `Array.prototype.sort` does.
    static func stableSorted<T>(_ items: [T], by compare: (T, T) -> Int) -> [T] {
        items.enumerated()
            .sorted { l, r in
                let c = compare(l.element, r.element)
                return c != 0 ? c < 0 : l.offset < r.offset
            }
            .map(\.element)
    }
}
