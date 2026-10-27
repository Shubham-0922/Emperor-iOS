import SwiftUI

/// A file fetched for sharing, for `.sheet(item:)`.
struct LibrarySharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// The reading room: the tapped row paints the header at once, `/doc` fills it in, and the body
/// is the judgment reader for a text document or the PDF otherwise (`ReadingRoom.jsx`).
///
/// Also the way in from elsewhere in the app: `LibraryReadingRoom(docID:)` opens any catalogue
/// document by its id.
struct LibraryReadingRoom: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session

    let seed: LibraryDoc

    init(seed: LibraryDoc) {
        self.seed = seed
    }

    init(docID: Int) {
        self.seed = LibraryDoc(id: docID)
    }

    @State private var model: LibraryReaderViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.canvas)
        .navigationTitle(model?.title ?? LibraryDisplay.tidyTitle(seed))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Link(destination: LibraryLinks.doc(id: seed.id, apiBaseURL: APIConfig.current.baseURL)) {
                    Label("Open on the web", systemImage: "safari")
                }
                .accessibilityIdentifier("library-open-web")
            }
        }
        // A container of its own, so the identifier is not handed down to the find bar's
        // field, count and arrows in place of their own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-room")
        .task {
            guard model == nil else { return }
            let created = LibraryReaderViewModel(seed: seed, service: session.library)
            model = created
            await created.load()
        }
    }

    @ViewBuilder
    private func content(_ model: LibraryReaderViewModel) -> some View {
        switch model.body {
        case .loading:
            VStack(spacing: 0) {
                LibraryRoomHeader(doc: model.doc, title: model.title)
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .notFound:
            EmptyStateView(LibraryReaderViewModel.notFoundTitle, systemImage: "questionmark.folder",
                           message: LibraryReaderViewModel.notFoundMessage, tone: .neutral)
        case .failed(let failure):
            LoadFailureView(failure: failure, retry: { await model.load() })
        case .judgment:
            if let judgment = model.judgment {
                LibraryJudgmentReader(model: judgment)
            }
        case .pdf:
            VStack(spacing: 0) {
                LibraryRoomHeader(doc: model.doc, title: model.title)
                if let file = model.file {
                    LibraryFileView(model: file, docID: model.doc.id, shareName: model.shareName)
                }
            }
        }
    }
}

/// The reading room's header: a small cover, the title, what kind of document it is and its facts.
struct LibraryRoomHeader: View {
    @Environment(\.theme) private var theme

    let doc: LibraryDoc
    let title: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            LibraryCoverView(doc: doc, width: 52)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.serif(.headline, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .dynamicLineLimit(3)
                    .accessibilityAddTraits(.isHeader)
                Text(([LibraryDisplay.theme(doc.category).cap] + LibraryDisplay.docMeta(doc)).joined(separator: " · "))
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textSecondary)
                    .dynamicLineLimit(2)
                if let size = doc.fileSize, size > 0 {
                    Text(LibraryDisplay.bookSize(size))
                        .font(.brand(.caption2))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.md)
        .background(theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.separator).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A PDF from the catalogue, or why it is not here: not on the shelf yet, too large to hold in
/// memory (offered on the web), or a failure to retry.
struct LibraryFileView: View {
    @Environment(\.theme) private var theme

    let model: LibraryFileViewModel
    let docID: Int
    let shareName: String

    var body: some View {
        Group {
            switch model.content {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let data):
                PDFDataView(data: data)
                    .accessibilityIdentifier("library-pdf")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            if let url = ShareableFile.url(for: data, named: shareName) {
                                ShareLink(item: url) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .accessibilityLabel("Share the document")
                                .accessibilityIdentifier("library-share")
                            }
                        }
                    }
            case .missing:
                EmptyStateView(LibraryFileViewModel.missingTitle, systemImage: "books.vertical",
                               message: LibraryFileViewModel.missingMessage, tone: .neutral)
                    .accessibilityIdentifier("library-not-on-shelf")
            case .tooLarge(let bytes):
                EmptyStateView(LibraryFileViewModel.tooLargeTitle, systemImage: "doc.richtext",
                               message: LibraryFileViewModel.tooLargeMessage(bytes), tone: .neutral) {
                    Link(destination: LibraryLinks.doc(id: docID, apiBaseURL: APIConfig.current.baseURL)) {
                        Text("Open on the web")
                    }
                    .buttonStyle(.primaryAction)
                }
            case .failed(let failure):
                LoadFailureView(failure: failure, retry: { await model.load() })
            }
        }
        .task { await model.load() }
    }
}
