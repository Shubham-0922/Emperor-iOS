import SwiftUI
import WebKit

/// Editing a saved draft in place, inside its reader.
///
/// An HTML draft is edited where it is drawn — its page made `contenteditable` — so what is
/// edited is what was read; a Markdown draft is edited as its own text. Save sends the draft
/// over its row (`DraftEditorModel`), as the web's live-draft canvas does. A failed save keeps
/// the edit on screen with the reason, marked "Not saved".
struct DraftEditorView: View {
    @Environment(\.theme) private var theme

    let editor: DraftEditorModel
    let isHTML: Bool
    /// Told after a save: the content saved and the row that now holds it.
    let onSaved: (_ content: String, _ id: String) -> Void

    @State private var text = ""
    @State private var controller = EditableDocumentController()

    var body: some View {
        VStack(spacing: 0) {
            if let message = editor.errorMessage {
                errorBanner(message)
            }
            editorBody
            bar
        }
        .background(theme.canvas)
        .onAppear {
            text = editor.pendingEdit ?? editor.content
        }
    }

    @ViewBuilder
    private var editorBody: some View {
        if isHTML {
            EditableDocumentWebView(html: editor.content, controller: controller)
                .accessibilityIdentifier("draft-editor")
                .accessibilityLabel("Draft, editable")
        } else {
            TextEditor(text: $text)
                .font(.brand(.body))
                .foregroundStyle(theme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Spacing.md)
                .accessibilityIdentifier("draft-editor")
                .accessibilityLabel("Draft text")
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            StatusPill(text: "Not saved", tone: .danger)
            Text(message)
                .font(.brand(.footnote))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(theme.dangerBg)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("draft-save-error")
    }

    private var bar: some View {
        HStack(spacing: Spacing.sm) {
            Button("Cancel") {
                editor.cancel()
            }
            .buttonStyle(.secondaryAction)
            .disabled(editor.isSaving)
            .accessibilityIdentifier("draft-cancel-edit")

            Button {
                save()
            } label: {
                saveLabel
            }
            .buttonStyle(.primaryAction)
            .disabled(editor.isSaving)
            .accessibilityIdentifier("draft-save")
            .accessibilityLabel(editor.isSaving ? "Saving" : "Save")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
        .background(theme.elevated)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.separator).frame(height: 1)
        }
    }

    @ViewBuilder
    private var saveLabel: some View {
        if editor.isSaving {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else {
            Text("Save")
                .frame(maxWidth: .infinity)
        }
    }

    private func save() {
        let html = isHTML
        let typed = text
        Task { @MainActor in
            let edited: String
            if html {
                guard let read = await controller.currentHTML() else {
                    editor.couldNotRead()
                    return
                }
                edited = (read == controller.baseline) ? editor.content : read
            } else {
                edited = typed
            }
            let saved = await editor.save(edited)
            if saved {
                onSaved(editor.content, editor.itemID)
            }
        }
    }
}

/// Reads the edited body back out of an `EditableDocumentWebView`.
@MainActor
final class EditableDocumentController {
    weak var webView: WKWebView?

    /// The page as WebKit first serialised it; an unchanged read-back is not an edit.
    var baseline: String?

    /// The wrapper's `innerHTML`, or `nil` when it could not be read.
    ///
    /// Run in the client's own content world: the page's own scripts are off, and nothing on
    /// the page can see or answer this.
    func currentHTML() async -> String? {
        guard let webView else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            webView.callAsyncJavaScript(
                DraftEditor.readBackScript, arguments: [:], in: nil, in: .defaultClient
            ) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value as? String)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// `DocumentWebView`, with the document's wrapper made editable.
///
/// The same configuration — the page's JavaScript off, a non-persistent store, every navigation
/// but the first load refused — because the draft is the same model-authored markup. Loaded once:
/// reloading on a later update would throw away what was typed.
struct EditableDocumentWebView: UIViewRepresentable {
    let html: String
    let controller: EditableDocumentController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false
        configuration.defaultWebpagePreferences = preferences
        configuration.websiteDataStore = .nonPersistent()

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        let pointSize = Double(UIFontMetrics.default.scaledValue(
            for: CGFloat(ArtifactDocument.basePointSize)))
        let page = ArtifactDocument.html(wrapping: html, pointSize: pointSize, editable: true)
        view.loadHTMLString(page, baseURL: nil)
        controller.webView = view
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        controller.webView = view
    }

    /// `@MainActor` for the reason `DocumentWebView.Coordinator` gives: without it the policy
    /// method is never called, and a link in the draft could navigate the view.
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let controller: EditableDocumentController

        init(controller: EditableDocumentController) {
            self.controller = controller
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                controller.baseline = await controller.currentHTML()
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
        }
    }
}
