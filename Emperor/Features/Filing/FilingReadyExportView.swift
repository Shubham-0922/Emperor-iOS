import SwiftUI
import PDFKit
import UIKit

/// "Filing ready" being made, then ready to share: a panel over the draft with the page's own
/// progress (`FilingReadyExportModel`), then the file.
struct FilingReadyExportView: View {
    @Environment(\.theme) private var theme

    let model: FilingReadyExportModel

    private var formatName: String { model.format == .word ? "Word file" : "PDF" }

    var body: some View {
        if model.progress != nil, model.format != nil {
            panel
                .padding(Spacing.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let url = model.result {
                Label("Filing-ready \(formatName) prepared", systemImage: "checkmark.circle")
                    .font(.brand(.subheadline, weight: .semibold))
                    .foregroundStyle(theme.success)
                HStack(spacing: Spacing.sm) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("filing-export-share")
                    Button("Close") { model.dismiss() }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                        .accessibilityIdentifier("filing-export-close")
                }
            } else if let failure = model.failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("filing-export-failed")
                Button("Close") { model.dismiss() }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
            } else {
                progressRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .panel()
    }

    private var progressRow: some View {
        let value: Double = Double(model.progress ?? 0)
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Preparing the filing-ready \(formatName)…")
                .font(.brand(.subheadline, weight: .medium))
                .foregroundStyle(theme.textPrimary)
            ProgressView(value: value, total: 100)
                .tint(theme.accent)
                .accessibilityLabel("Preparing the filing-ready \(formatName)")
                .accessibilityValue("\(model.progress ?? 0) percent")
                .accessibilityIdentifier("filing-export-progress")
            Text("The list of annexures, typed copies and originals are being attached.")
                .font(.brand(.caption))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Turns a filing-ready package into a file on the device: Word from the one piece of HTML; a
/// PDF from the draft laid out on A4, then each original's own pages — a PDF as it is, an image
/// as a page — and a notice page for any that cannot be read.
@MainActor
enum FilingReadyRenderer {

    static func file(for package: FilingReadyPackage) async -> URL? {
        let name = FilingReadyExport.fileName(title: package.title, format: package.format)
        switch package.format {
        case .word:
            let data = DocxDocument.make(fromHTML: package.html)
            return ShareableFile.url(for: data, named: name)
        case .pdf:
            let documents: [Data] = package.parts.map(pdf(for:))
            guard let merged = PDFTools.merge(documents: documents) else { return nil }
            return ShareableFile.url(for: merged, named: name)
        }
    }

    private static func pdf(for part: FilingReadyPackage.Part) -> Data {
        switch part {
        case .html(let html):
            return AnswerPDF.render(html: html)
        case .original(let mark, let data, let mime):
            if data.starts(with: Data("%PDF".utf8)), PDFDocument(data: data) != nil {
                return data
            }
            if mime.hasPrefix("image/"), let image = UIImage(data: data) {
                return PDFTools.page(for: image)
            }
            return AnswerPDF.render(html: FilingReadyExport.failureHTML(mark: mark, error: nil))
        }
    }
}
