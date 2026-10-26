import Foundation

// The small rules the filing page applies itself, ported and held to the platform's own code by
// `FilingGoldenTests` (`scripts/generate-filing-fixtures.mjs`). Index numbering, folios, marks and
// the checklist's verdicts are the server's and are not ported.

/// Annexure marks — `P-1`, `R-2` — and their order (the page's `parseMark` / `compareMark`).
enum FilingMarks {

    /// The side, upper-cased, and the number, for a mark of letters, a hyphen and digits;
    /// anything else is its own text with the number 0.
    static func parse(_ mark: String?) -> (side: String, number: Int) {
        let text = mark ?? ""
        guard let hyphen = text.firstIndex(of: "-") else { return (text, 0) }
        let side = text[text.startIndex..<hyphen]
        let digits = text[text.index(after: hyphen)...]
        guard !side.isEmpty, !digits.isEmpty,
              side.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) || ("a"..."z").contains($0) }),
              digits.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) })
        else { return (text, 0) }
        return (side.uppercased(), Int(digits) ?? Int.max)
    }

    /// Negative when `a` comes first, positive when `b` does, 0 when they rank the same.
    static func compare(_ a: String, _ b: String) -> Int {
        let (sa, na) = parse(a)
        let (sb, nb) = parse(b)
        if sa == sb { return na < nb ? -1 : (na > nb ? 1 : 0) }
        // JavaScript compares strings by UTF-16 code unit.
        return Array(sa.utf16).lexicographicallyPrecedes(Array(sb.utf16)) ? -1 : 1
    }

    /// The marks in mark order. Stable, as the page's sort is: marks that rank the same keep
    /// their order.
    static func sorted(_ marks: [String]) -> [String] {
        marks.enumerated()
            .sorted { lhs, rhs in
                let order = compare(lhs.element, rhs.element)
                return order != 0 ? order < 0 : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Whether the binding order is the mark order.
    static func isInMarkOrder(_ marks: [String]) -> Bool {
        marks == sorted(marks)
    }
}

/// The forum on the cover page.
enum FilingForum {

    /// The page's suggestions, verbatim and in its order — the four the assembler supports first.
    static let suggestions = [
        "NCLT", "NCLAT", "High Court", "Supreme Court", "District Court",
        "Debts Recovery Tribunal (DRT)", "DRAT", "Consumer Commission (NCDRC / State / District)",
        "Arbitral Tribunal", "Data Protection Board of India", "Competition Commission of India (CCI)",
        "SAT (Securities Appellate Tribunal)", "Registrar of Companies (RoC)", "Adjudicating Officer",
    ]

    /// The forums the assembler can make a bundle for.
    static let supported = ["NCLT", "NCLAT", "High Court", "Supreme Court"]

    /// Which of the four the assembler will read `input` as, or `nil` for none — the server's
    /// `normalizeForum`. A forum it does not read is refused only after the whole bundle has
    /// been rendered, so the app checks first.
    static func normalize(_ input: String?) -> String? {
        let s = (input ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return nil }
        if s == "nclt" || s.contains("company law tribunal ") { return "NCLT" }
        if s == "nclat" || s.contains("appellate tribunal") { return "NCLAT" }
        if s == "hc" || s.contains("high court") { return "High Court" }
        if s == "sc" || s.contains("supreme") { return "Supreme Court" }
        if s.contains("company law tribunal") { return "NCLT" }
        return nil
    }
}

/// How a checklist item is drawn.
enum FilingChecklistTone: Equatable, Sendable {
    case success, danger, warn, neutral

    /// The page's three headings, in its order.
    static let kinds = ["ai", "assembled", "human"]

    static func tone(for status: String) -> FilingChecklistTone {
        switch status.lowercased() {
        case "ok": return .success
        case "missing": return .danger
        case "attention": return .warn
        default: return .neutral
        }
    }

    static func groupTitle(kind: String) -> String {
        switch kind {
        case "ai": return "AI-prepared"
        case "human": return "Human action required"
        default: return "Assembled by system"
        }
    }
}
