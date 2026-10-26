import Foundation

/// A fixed vocabulary of a matter field: the wire key as the raw value, the words the web shows
/// as `label`, and the cases in the web's own order.
protocol MatterVocab: RawRepresentable, CaseIterable, Hashable, Sendable where RawValue == String {
    var label: String { get }
}

extension MatterVocab {
    /// The label for a stored value; text the vocabulary does not know is shown as written
    /// (`our_side` takes free text), and nothing is "".
    static func label(for raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        return Self(rawValue: raw)?.label ?? raw
    }
}

/// The matter vocabularies, as the web lists them (`src/lib/projectsApi.js`, `lib/projects/rules.js`,
/// `src/lib/projectRecord.js`, `src/lib/projectColors.js`, `src/components/projects/shared.jsx`).
/// The order of `allCases` is the web's order for each list; `MatterGoldenTests` holds both to it.
enum MatterVocabulary {

    enum PracticeArea: String, MatterVocab {
        case civil, criminal, writ, arbitration, consumer, family, labour, tax, ipr, property, corporate, insolvency, other
        var label: String {
            switch self {
            case .civil: return "Civil"
            case .criminal: return "Criminal"
            case .writ: return "Writ / constitutional"
            case .arbitration: return "Arbitration"
            case .consumer: return "Consumer"
            case .family: return "Family"
            case .labour: return "Labour & service"
            case .tax: return "Tax"
            case .ipr: return "IPR"
            case .property: return "Property"
            case .corporate: return "Corporate"
            case .insolvency: return "Insolvency"
            case .other: return "Other"
            }
        }
    }

    enum OurSide: String, MatterVocab {
        case petitioner, respondent, plaintiff, defendant, appellant, complainant, accused, applicant, other
        var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    }

    /// The eight banner presets; the label is the key capitalised, as the picker reads it.
    enum BannerPreset: String, MatterVocab {
        case navy, slate, indigo, teal, forest, wine, gold, sand
        var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    }

    enum ProjectStatus: String, MatterVocab {
        case active, onHold = "on_hold", disposed, archived
        var label: String {
            switch self {
            case .active: return "Active"
            case .onHold: return "On hold"
            case .disposed: return "Disposed"
            case .archived: return "Archived"
            }
        }
    }

    /// In the form's order (high first); the server lists them low → high.
    enum Priority: String, MatterVocab {
        case high, normal, low
        var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    }

    /// The kinds `project_updates` accepts, in the server's order.
    enum UpdateKind: String, MatterVocab {
        case note, hearing, order, filing, task, milestone, event
        var label: String { ChronoKind(rawValue: rawValue)!.label }
    }

    /// The same kinds in the chronology's order, `event` first.
    enum ChronoKind: String, MatterVocab {
        case event, hearing, order, filing, milestone, task, note
        var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    }

    /// Who put an entry on the record.
    enum UpdateSource: String, MatterVocab {
        case manual, ai, court
        var label: String {
            switch self {
            case .manual: return "You"
            case .ai: return "AI"
            case .court: return "Court"
            }
        }
    }

    enum TaskKind: String, MatterVocab {
        case task, deadline, limitation, filing, certifiedCopy = "certified_copy", compliance, hearingPrep = "hearing_prep"
        var label: String {
            switch self {
            case .task: return "Task"
            case .deadline: return "Deadline"
            case .limitation: return "Limitation"
            case .filing: return "Filing"
            case .certifiedCopy: return "Certified copy"
            case .compliance: return "Compliance"
            case .hearingPrep: return "Hearing prep"
            }
        }
    }

    enum TaskStatus: String, MatterVocab {
        case open, done
        var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    }

    enum LedgerKind: String, MatterVocab {
        case fee, payment, expense
        var label: String {
            switch self {
            case .fee: return "Fee billed"
            case .payment: return "Payment received"
            case .expense: return "Expense"
            }
        }
    }

    /// In the form's order (UPI first); the server lists cash first.
    enum PaymentMode: String, MatterVocab {
        case upi, bank, cheque, cash, card, other
        var label: String {
            switch self {
            case .upi: return "UPI"
            case .bank: return "Bank transfer"
            case .cheque: return "Cheque"
            case .cash: return "Cash"
            case .card: return "Card"
            case .other: return "Other"
            }
        }
    }

    enum ExpenseCategory: String, MatterVocab {
        case courtFee = "court_fee", stampDuty = "stamp_duty", processFee = "process_fee", clerkage
        case typingCopies = "typing_copies", certifiedCopies = "certified_copies", travel, notary, other
        var label: String {
            switch self {
            case .courtFee: return "Court fee"
            case .stampDuty: return "Stamp duty"
            case .processFee: return "Process fee"
            case .clerkage: return "Clerkage"
            case .typingCopies: return "Typing & copies"
            case .certifiedCopies: return "Certified copies"
            case .travel: return "Travel"
            case .notary: return "Notary / oath"
            case .other: return "Other"
            }
        }
    }

    enum PeopleRole: String, MatterVocab {
        case client, oppositeParty = "opposite_party", opposingCounsel = "opposing_counsel", ourCounsel = "our_counsel"
        case judge, witness, other
        var label: String {
            switch self {
            case .client: return "Client"
            case .oppositeParty: return "Opposite party"
            case .opposingCounsel: return "Opposing counsel"
            case .ourCounsel: return "Our counsel"
            case .judge: return "Judge / bench"
            case .witness: return "Witness"
            case .other: return "Other"
            }
        }
    }

    /// The workspace sections, in the web's order.
    enum MatterSection: String, MatterVocab {
        case overview, ask, files, drafts, chronology, court, tasks, fees, people
        var label: String {
            switch self {
            case .ask: return "Ask Emperor"
            default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
            }
        }
    }

    /// The forum a matter is before (`forum_type`).
    enum Forum: String, MatterVocab {
        case district, highCourt = "high_court", supremeCourt = "supreme_court", tribunal, arbitration, other
        var label: String {
            switch self {
            case .district: return "District Court"
            case .highCourt: return "High Court"
            case .supremeCourt: return "Supreme Court"
            case .tribunal: return "Tribunal (NCLT / NCLAT / ITAT …)"
            case .arbitration: return "Arbitration"
            case .other: return "Other / Advisory"
            }
        }
        /// The label up to " (": "Tribunal".
        var shortLabel: String {
            guard let r = label.range(of: " (") else { return label }
            return String(label[..<r.lowerBound])
        }
        /// `forumMeta`: an unknown forum reads as the last one, Other.
        static func of(_ raw: String?) -> Forum { raw.flatMap(Forum.init(rawValue:)) ?? .other }
    }

    /// A project folder's colour identity. Nil (no colour) is the neutral treatment, not a ninth hue.
    enum ProjectColor: String, MatterVocab {
        case indigo, violet, fuchsia, rose, amber, green, teal, sky
        var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
        /// `normalizeProjectColor`: exactly one of the eight keys, or nil.
        static func normalize(_ raw: String?) -> ProjectColor? { raw.flatMap(ProjectColor.init(rawValue:)) }
        /// `projectColorLabel`.
        static func label(of raw: String?) -> String { normalize(raw)?.label ?? "No colour" }
    }

    /// The court-status vocabulary (`not_filed` only).
    static let courtStatuses = ["not_filed"]
}
