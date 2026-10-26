import SwiftUI

/// The matter's List of Dates and Events as a PDF — the web's export, in the synopsis format
/// (court, case, cause title, then one row per date) — shown, then shared or printed.
struct ListOfDatesShare: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// The list as an HTML fragment (`MatterPrintouts.listOfDatesHTML`).
    let html: String
    let fileName: String

    @State private var file: URL?
    @State private var pdf: Data?

    var body: some View {
        VStack(spacing: 0) {
            RecordSheetHeader(title: "List of Dates", subtitle: fileName, onClose: { dismiss() })
            Group {
                if let pdf {
                    PDFDataView(data: pdf)
                        .accessibilityLabel("List of Dates preview")
                        .accessibilityIdentifier("list-of-dates-preview")
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
            let data = AnswerPDF.render(html: html)
            pdf = data
            file = PrintedPDF.temporaryFile(data, named: fileName)
        }
    }
}
