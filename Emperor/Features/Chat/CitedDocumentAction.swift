import SwiftUI

/// Opens the document a reference line names — `[3] Lease.pdf, p. 12 — "…"` — at the quoted
/// words. Set by the conversation, which knows how to find the document; absent anywhere else,
/// where a tapped reference shows its card to copy as it always has.
struct OpenCitedDocumentAction {
    let handler: @MainActor (DocumentReference) -> Void

    init(_ handler: @escaping @MainActor (DocumentReference) -> Void) {
        self.handler = handler
    }

    @MainActor
    func callAsFunction(_ reference: DocumentReference) {
        handler(reference)
    }
}

/// Classic `EnvironmentKey` rather than `@Entry`, which is iOS 18 — the deployment target is 17.
/// The default is computed, so no shared value of a non-`Sendable` type is stored.
private struct OpenCitedDocumentKey: @preconcurrency EnvironmentKey {
    static var defaultValue: OpenCitedDocumentAction? { nil }
}

extension EnvironmentValues {
    var openCitedDocument: OpenCitedDocumentAction? {
        get { self[OpenCitedDocumentKey.self] }
        set { self[OpenCitedDocumentKey.self] = newValue }
    }
}
