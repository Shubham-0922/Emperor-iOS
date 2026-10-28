import Foundation
#if canImport(Darwin)
import Observation
#endif

/// The document viewer's "Searchable PDF": fetches the copy of a PDF whose scanned pages carry an
/// invisible text layer, for the share sheet — the web viewer's button of the same name
/// (`src/components/viewer/FileViewerModal.jsx`).
///
/// Differs from sharing the document as it is only for a PDF with scanned pages that has not
/// already been stored as its searchable version; for any other PDF the server sends the stored
/// file, renamed `…_searchable.pdf`.
///
/// See `ChatViewModel` for why `@Observable` is Apple-only.
#if canImport(Darwin)
@Observable
#endif
@MainActor
final class SearchableCopyViewModel {

    private(set) var isFetching = false
    /// Why the last attempt failed, worded for the person.
    var errorMessage: String?
    /// The copy, once it has arrived; the screen hands it to the share sheet and clears it.
    var copy: DownloadedFile?

    private let files: any FileManaging

    init(files: any FileManaging) {
        self.files = files
    }

    /// Whether the document has a searchable copy to offer — a PDF, by its stored name. A Word
    /// document shown through its converted preview does not.
    nonisolated static func isOffered(for attachment: ChatAttachment) -> Bool {
        FileDownloadWording.offersSearchableCopy(fileName: attachment.name)
    }

    func fetch(_ attachment: ChatAttachment) async {
        guard !isFetching, Self.isOffered(for: attachment) else { return }
        isFetching = true
        errorMessage = nil
        defer { isFetching = false }
        do {
            let data = try await files.downloadSearchable(
                name: attachment.name, folderName: attachment.folderName)
            guard !data.isEmpty else {
                throw DocumentNotViewable(message: "The searchable copy arrived empty.")
            }
            copy = DownloadedFile(
                fileName: FileDownloadWording.searchableName(for: attachment.name), data: data)
        } catch {
            errorMessage = DisplayText.message(for: error)
        }
    }
}
