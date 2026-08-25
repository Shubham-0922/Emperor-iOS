import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Opens a cited source document at the page the citation names.
///
/// This is the claim the product rests on — every line names a page you can open — so the
/// jump has to actually land, and the failure has to be honest when it cannot.
struct SourceDocumentView: View {
    let attachment: ChatAttachment
    let mention: AnnexureMention

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var data: Data?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Opening \(displayName)")
                } else if let data, isPDF {
                    PDFPageView(data: data, page: mention.startPage)
                } else if let data, let image = UIImage(data: data) {
                    // Scanned exhibits are frequently filed as images rather than PDFs.
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image).resizable().scaledToFit()
                    }
                } else if let data, let text = String(data: data, encoding: .utf8) {
                    ScrollView {
                        Text(text)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                } else {
                    ContentUnavailableView(
                        "Cannot preview this document",
                        systemImage: "doc.questionmark",
                        description: Text(
                            errorMessage ?? "\(displayName) is not a format this app can display."))
                }
            }
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(displayName).font(.headline).lineLimit(1)
                        // The mark is how the document is referred to in the filing, so it
                        // belongs in the title bar next to the page.
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .task { await load() }
        }
    }

    private var displayName: String {
        attachment.name.replacingOccurrences(of: "_", with: " ")
    }

    private var subtitle: String {
        [mention.mark, mention.pageDescription].compactMap { $0 }.joined(separator: " · ")
    }

    private var isPDF: Bool {
        attachment.name.lowercased().hasSuffix(".pdf")
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            data = try await session.files.fileData(
                name: attachment.name, folderName: attachment.folderName)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// A PDF opened at a specific page.
private struct PDFPageView: UIViewRepresentable {
    let data: Data
    /// The cited page, **1-based** — the server indexes pages as `idx + 1`
    /// (`sync-server.js:1479`), while PDFKit is 0-based.
    let page: Int?

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.usePageViewController(false)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard view.document == nil, let document = PDFDocument(data: data) else { return }
        view.document = document

        guard let page, page > 0 else { return }
        // Clamp rather than fail: a citation can name a page beyond the file if the model
        // read a different edition, and landing on the last page beats showing nothing.
        let index = min(page - 1, max(document.pageCount - 1, 0))
        guard let target = document.page(at: index) else { return }
        // Deferred: PDFView ignores go(to:) until it has laid the document out.
        DispatchQueue.main.async {
            view.go(to: target)
        }
    }
}
