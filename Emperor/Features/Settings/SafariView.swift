import SafariServices
import SwiftUI

/// A provider's sign-in page in Safari's own view, inside the app.
///
/// Safari rather than a web view: Google refuses its sign-in in an embedded web view. The page
/// ends on the web app rather than coming back here, so `CloudConnectionsModel` watches the
/// connection instead and closes this once it is made; Done closes it at any time.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .done
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onFinish()
        }
    }
}

/// What stands in for the sign-in page under the UI tests: no network, a Done to close it.
struct CloudBrowserStub: View {
    @Environment(\.theme) private var theme
    let provider: CloudProvider
    let onFinish: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                Text("Sign in to \(provider.label)")
                    .font(.brand(.headline))
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityIdentifier("cloud-browser-stub")
                Text("The provider's sign-in page opens here.")
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.canvas)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onFinish() }
                        .accessibilityIdentifier("cloud-browser-done")
                }
            }
        }
    }
}
