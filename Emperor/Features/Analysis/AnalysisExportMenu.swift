import SwiftUI
import UIKit

/// "Download" for a finished run: the report as PDF or Word, the index as CSV, the list of dates
/// as Word, PDF or text — each of what is on screen.
///
/// The files are built in the menu's content, which SwiftUI evaluates when the menu opens, so a
/// result that is only read is never laid out as a PDF (as `DocumentExportMenu`).
struct AnalysisExportMenu: View {
    let outcome: AnalysisOutcome
    let docIndexState: DocIndexViewState
    let dateChartState: DateChartViewState
    @Binding var toast: String?

    var body: some View {
        Menu {
            switch outcome.result {
            case .devilsAdvocate(let report):
                let html = DevilsAdvocateExport.html(report, madeOn: AnalysisHistoryFormat.madeOn(outcome.madeOn))
                let stem = Self.stem(report.matter.title, fallback: "Devils_Advocate_report")
                pdfLink(html, named: "\(stem).pdf")
                wordLink(html, named: "\(stem).docx")
            case .docIndex(let index):
                if let csv = ShareableFile.url(for: Data(docIndexState.csv(index).utf8), named: "doc-index.csv") {
                    ShareLink(item: csv) {
                        Label("Download CSV", systemImage: "tablecells")
                    }
                    .accessibilityIdentifier("di-csv")
                }
            case .listOfDates(let chart):
                let shown = dateChartState.shown(chart)
                let html = chart.wordBody(shown)
                let stem = "Event_Chart_\(chart.fileStem)"
                wordLink(html, named: "\(stem).docx")
                pdfLink(html, named: "\(stem).pdf")
                Button {
                    UIPasteboard.general.string = chart.asPlainText(shown)
                    toast = "Copied"
                } label: {
                    Label("Copy as text", systemImage: "doc.on.doc")
                }
            }
        } label: {
            Label("Download", systemImage: "square.and.arrow.down")
        }
        .accessibilityLabel("Download")
        .accessibilityIdentifier("analysis-export")
    }

    @ViewBuilder
    private func pdfLink(_ html: String, named name: String) -> some View {
        if let url = ShareableFile.url(for: AnswerPDF.render(html: html), named: name) {
            ShareLink(item: url) {
                Label("PDF", systemImage: "doc.richtext")
            }
        }
    }

    @ViewBuilder
    private func wordLink(_ html: String, named name: String) -> some View {
        if let url = ShareableFile.url(for: DocxDocument.make(fromHTML: html), named: name) {
            ShareLink(item: url) {
                Label("Word (.docx)", systemImage: "doc.text")
            }
        }
    }

    /// A file name from the matter's title: letters and digits, the rest as one dash.
    private static func stem(_ title: String, fallback: String) -> String {
        var out = ""
        var inRun = false
        for scalar in title.unicodeScalars {
            if scalar.isASCII, scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) {
                out.unicodeScalars.append(scalar)
                inRun = false
            } else if !inRun, !out.isEmpty {
                out.append("_")
                inRun = true
            }
        }
        while out.hasSuffix("_") { out.removeLast() }
        return out.isEmpty ? fallback : String(out.prefix(80))
    }
}
