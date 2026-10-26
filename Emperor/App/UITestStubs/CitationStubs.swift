#if DEBUG
import Foundation
import UIKit

/// The UI tests' canned answers for citations and their sources, only under `-UITestCitedSource`
/// (and `-UITestCitedSourceMissing`, where the cited file is not found): one stored exchange whose
/// answer cites a page of the reader's lease, `/resolve-file` finding it, `/view-file` serving a
/// three-page PDF with the quoted words on page 2, and `/page-words` saying the PDF's own text is
/// all there is. Owned by package 07-P7. Answers nothing under `-UITestEmpty`.
enum CitationStubs {

    static let fileName = "Lease_Agreement.pdf"
    static let quote = "the lessee shall pay the monthly rent on the fifth day"

    private static var isOn: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-UITestCitedSource") || arguments.contains("-UITestCitedSourceMissing")
    }

    private static var isMissing: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestCitedSourceMissing")
    }

    static func reply(_ request: URLRequest, _ path: String) -> StubReply? {
        guard isOn, !UITestSupport.isEmpty else { return nil }
        switch path {
        case "/messages":
            return .json(messages)
        case "/resolve-file":
            return .json(isMissing
                ? #"{"found":false}"#
                : #"{"found":true,"folderName":"Bakshi","fileName":"\#(fileName)","page":2,"quoteStatus":"verified"}"#)
        case "/view-file" where UITestSupport.Fixtures.query(request, "fileName") == fileName:
            return .bytes(lease, type: "application/pdf")
        case "/page-words":
            return .json(#"{"status":"none","page":null}"#)
        default:
            return nil
        }
    }

    /// One question and an answer citing the lease, as `/messages` stores them.
    private static var messages: String {
        let answer = "The rent falls due on the fifth of each month [1].\\n\\n## References\\n\\n"
            + "[1] \(fileName), p. 2 — “\(quote)”"
        return #"{"success":true,"messages":[{"id":"m1","role":"user","content":"When is the rent due under the lease?"},{"id":"m2","role":"assistant","content":"\#(answer)"}]}"#
    }

    /// Three pages of text, the quoted words on the second — real text, so the page's own text
    /// layer is what the viewer searches.
    private static let lease: Data = {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let font = UIFont.systemFont(ofSize: 14)
        let pages = [
            "LEASE AGREEMENT\n\nThis agreement is made between the lessor and the lessee for the premises described in the schedule.",
            "2. RENT\n\nIn consideration of the premises, \(quote) of every calendar month, without any deduction whatsoever.",
            "3. TERM\n\nThe lease shall run for eleven months from the date of this agreement and may be renewed by consent.",
        ]
        return renderer.pdfData { context in
            for text in pages {
                context.beginPage()
                (text as NSString).draw(
                    in: bounds.insetBy(dx: 60, dy: 80),
                    withAttributes: [.font: font, .foregroundColor: UIColor.black])
            }
        }
    }()
}
#endif
