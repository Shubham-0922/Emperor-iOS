import SwiftUI

/// The line under a finished answer that cites the reader's own documents: "2 citations ·
/// checked against source", or which were not found — the web's `CitationMeta`. Nothing at all
/// for an answer that cites none. The checking and the wording are `CitationCheck`'s.
struct CitationMetaLine: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session

    /// The answer's text.
    let content: String
    /// The message it belongs to, for the line's identifier.
    let messageID: String
    /// The matter the conversation belongs to, if any.
    var projectID: String?

    @State private var check: CitationCheck?

    var body: some View {
        // Decided from the text alone, so an answer citing nothing never asks the server and
        // never draws a line; the task runs on a view that is on screen.
        if !CitedSource.citedDocs(content).isEmpty {
            line(label: check?.label ?? placeholder, tone: check?.tone ?? .plain)
                .task(id: content + "|" + (projectID ?? "")) {
                    let created = CitationCheck(
                        content: content, resolver: session.citedSources, projectID: projectID,
                        account: session.currentUser.map { String($0.id) } ?? "")
                    check = created
                    await created.run()
                }
        }
    }

    /// What `CitationCheck` says while it checks, before it exists.
    private var placeholder: String {
        let n = CitedSource.citedDocs(content).count
        return "\(n) citation\(n == 1 ? "" : "s") · checking against source…"
    }

    private func line(label: String, tone: CitationCheck.Tone) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            switch tone {
            case .ok:
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.success)
                    .accessibilityHidden(true)
            case .warn:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.warning)
                    .accessibilityHidden(true)
            case .plain:
                EmptyView()
            }
            Text(label)
                .font(.brand(.caption))
                .foregroundStyle(tone == .warn ? theme.textPrimary : theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("citation-meta-\(messageID)")
    }
}
