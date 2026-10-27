import SwiftUI
import UIKit

/// One annexure, opened from its card: a typed copy as a document, an original as its PDF pages
/// or its image, or the reason it cannot be shown here (`ToolWorkspace.jsx`,
/// `AnnexureViewerModal`). Read only when opened.
struct FilingAnnexureViewer: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session

    let chatID: String
    let annexure: FilingAnnexure

    @State private var model: FilingAnnexureViewerModel?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(annexure.viewerTitle)
                    .font(.brand(.subheadline, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .dynamicLineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("filing-viewer")
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(theme.surface2.ignoresSafeArea())
            .navigationTitle("Annexure \(annexure.mark)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            guard model == nil else { return }
            let created = FilingAnnexureViewerModel(
                service: session.filing, chatID: chatID, annexure: annexure)
            model = created
            await created.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model?.content ?? .loading {
        case .loading:
            VStack(spacing: Spacing.md) {
                ProgressView()
                Text(annexure.isTyped ? "Loading…" : "Preparing preview…")
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textSecondary)
            }
            .accessibilityElement(children: .combine)
        case .typed(let html):
            // Model-authored and register-built HTML: shown with scripts off, as every draft is.
            DocumentWebView(html: html)
                .background(theme.paper)
                .accessibilityIdentifier("filing-viewer-typed")
        case .message(let text):
            EmptyStateView("Nothing to show", systemImage: "doc.text", message: text, tone: .warning)
                .accessibilityIdentifier("filing-viewer-message")
        case .pdf(let data):
            PDFDataView(data: data)
                .accessibilityIdentifier("filing-viewer-pdf")
        case .image(let data):
            if let image = UIImage(data: data) {
                FilingZoomableImage(image: image, label: annexure.viewerTitle)
                    .accessibilityIdentifier("filing-viewer-image")
            } else {
                unpreviewable
            }
        case .unpreviewable:
            unpreviewable
        }
    }

    private var unpreviewable: some View {
        EmptyStateView(
            "Can't preview this file", systemImage: "eye.slash",
            message: FilingAnnexureViewerModel.unpreviewable, tone: .neutral)
            .accessibilityIdentifier("filing-viewer-unpreviewable")
    }
}

/// An image that pinches to zoom, from fitting the screen up to four times.
private struct FilingZoomableImage: View {
    let image: UIImage
    let label: String

    @State private var scale: CGFloat = 1
    @State private var settled: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                picture(in: proxy.size)
            }
        }
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    let next: CGFloat = settled * value.magnification
                    scale = min(4, max(1, next))
                }
                .onEnded { _ in settled = scale })
    }

    private func picture(in size: CGSize) -> some View {
        let width: CGFloat = size.width * scale
        let height: CGFloat = size.height * scale
        return Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
            .accessibilityLabel(label)
    }
}
