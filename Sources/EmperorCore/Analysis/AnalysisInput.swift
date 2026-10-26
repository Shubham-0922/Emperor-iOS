import Foundation

/// Which picked documents an analysis can be run on, decided before anything is sent.
///
/// The tools read documents from My Files by name and folder, so a document counts only with a
/// folder (`analysisKit.js`, `isRealFile`). The rest mirrors what the start route refuses — a
/// matter's folder, a name that is a path, more than ten at once — so the reason is said beside
/// the document rather than after a round trip.
enum AnalysisInput {
    static let maxFiles = 10
    static let maxReference = 2000
    /// Where the intake starts counting the note's characters.
    static let referenceCounterFrom = 1800

    struct Refused: Equatable, Sendable, Identifiable {
        var file: ChatAttachment
        var reason: String
        var id: String { "\(file.folderName ?? "")\u{0}\(file.name)" }
    }

    static let noFolder = "Put it in a folder in My Files first"
    static let matterFolder = "A matter’s files cannot be used here. Put the document in My Files first."
    static let notAPlainName = "A file name must be a plain name, not a path"
    static let tooMany = "At most 10 documents at a time"

    /// The documents that can go, in the order picked, and those that cannot with the reason.
    static func usable(_ files: [ChatAttachment]) -> (accepted: [ChatAttachment], refused: [Refused]) {
        var accepted: [ChatAttachment] = []
        var refused: [Refused] = []
        var seen = Set<String>()
        for file in files {
            let folder = file.folderName ?? ""
            if AnalysisJS.trim(folder).isEmpty {
                refused.append(Refused(file: file, reason: noFolder))
                continue
            }
            let segments = folder.split(whereSeparator: { $0 == "/" || $0 == "\\" })
            if segments.contains(where: { AnalysisJS.trim(String($0)).lowercased().hasPrefix("_projects") }) {
                refused.append(Refused(file: file, reason: matterFolder))
                continue
            }
            if !isPlainName(file.name) {
                refused.append(Refused(file: file, reason: notAPlainName))
                continue
            }
            let key = "\(folder)\u{0}\(file.name)"
            guard seen.insert(key).inserted else { continue }
            if accepted.count >= maxFiles {
                refused.append(Refused(file: file, reason: tooMany))
                continue
            }
            accepted.append(file)
        }
        return (accepted, refused)
    }

    private static func isPlainName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.allSatisfy({ $0 == "." }) else { return false }
        return !name.unicodeScalars.contains { scalar in
            scalar == "/" || scalar == "\\" || scalar.value < 0x20 || scalar.value == 0x7F
        }
    }

    /// The note as it may be sent: the server trims it and refuses more than 2,000 characters.
    static func isReferenceTooLong(_ reference: String) -> Bool {
        AnalysisJS.length(AnalysisJS.trim(reference)) > maxReference
    }

    /// "1,850 / 2,000", shown once the note is near its limit.
    static func referenceCounter(_ reference: String) -> String? {
        let n = AnalysisJS.length(AnalysisJS.trim(reference))
        guard n > referenceCounterFrom else { return nil }
        return "\(DisplayText.grouped(n)) / \(DisplayText.grouped(maxReference))"
    }
}
