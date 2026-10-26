import SwiftUI
import UIKit

/// A payment's fee receipt as a PDF — the web's printed receipt, word for word
/// (`MatterPrintouts.receiptHTML`, without the on-screen Print bar) — shown, then shared or
/// printed.
struct ReceiptShare: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// The receipt's whole HTML document.
    let html: String
    let fileName: String

    @State private var file: URL?
    @State private var pdf: Data?

    var body: some View {
        VStack(spacing: 0) {
            RecordSheetHeader(title: "Fee receipt", subtitle: fileName, onClose: { dismiss() })
            Group {
                if let pdf {
                    PDFDataView(data: pdf)
                        .accessibilityLabel("Receipt preview")
                        .accessibilityIdentifier("receipt-preview")
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            HStack(spacing: Spacing.sm) {
                Button {
                    if let pdf { PrintedPDF.print(pdf, name: fileName) }
                } label: {
                    Label("Print", systemImage: "printer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondaryAction)
                .disabled(pdf == nil)
                if let file {
                    ShareLink(item: file) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryAction)
                    .accessibilityIdentifier("receipt-share")
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.md)
            .background(theme.chrome)
        }
        .background(theme.elevated.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .task {
            guard pdf == nil else { return }
            let data = PrintedPDF.render(document: html)
            pdf = data
            file = PrintedPDF.temporaryFile(data, named: fileName)
        }
    }
}

/// A full HTML document laid out on A4 by the print system, and the plumbing to share or print it.
///
/// `AnswerPDF` wraps a fragment in the artifact viewer's styles; a receipt brings its own `<html>`
/// and `@page` rules, so it is laid out as it is.
enum PrintedPDF {

    static func render(document html: String) -> Data {
        let renderer = UIPrintPageRenderer()
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        formatter.perPageContentInsets = UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

        let paperRect = CGRect(origin: .zero, size: AnswerPDF.Paper.a4.size)
        renderer.setValue(paperRect, forKey: "paperRect")
        renderer.setValue(paperRect, forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paperRect, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    /// The PDF under its own name in a fresh temporary folder, for the share sheet.
    static func temporaryFile(_ data: Data, named name: String) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    @MainActor
    static func print(_ data: Data, name: String) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = name
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true)
    }
}
