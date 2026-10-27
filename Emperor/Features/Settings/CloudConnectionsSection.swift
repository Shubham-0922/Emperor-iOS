import SwiftUI

/// Account → "Connected services": Google Drive and OneDrive, each connected in Safari or
/// disconnected, as the web's Settings card does it.
///
/// Everything it decides is `CloudConnectionsModel`'s; this lays it out. A section's modifiers are
/// given to every row, so nothing is presented from the section itself: each row presents only
/// what concerns its own drive — the row tapped is the one certainly on screen — and the header,
/// drawn before the rows, starts the first read.
struct CloudConnectionsSection: View {
    @Environment(Session.self) private var session
    @Environment(\.theme) private var theme

    @State private var model: CloudConnectionsModel?
    @State private var confirming: CloudProvider?
    /// The drive last connected or disconnected: whose row shows a failure, and which the read
    /// after the sign-in page closes checks.
    @State private var actedOn: CloudProvider?

    var body: some View {
        Section {
            if let model, !model.connections.isEmpty {
                ForEach(CloudProvider.allCases, id: \.self) { provider in
                    row(provider, model: model)
                }
            } else if let failure = model?.state.failure {
                failureRow(failure)
            } else {
                ProgressView()
                    .tint(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("Loading connected services")
            }
        } header: {
            header
        } footer: {
            footer
        }
        .listRowBackground(theme.surface)
    }

    private var header: some View {
        SectionHeader(title: "Connected services")
            .accessibilityIdentifier("settings-header-cloud")
            .task {
                if model == nil { model = CloudConnectionsModel(service: session.cloud) }
                await model?.load()
            }
    }

    // MARK: - Rows

    private func row(_ provider: CloudProvider, model: CloudConnectionsModel) -> some View {
        let connection: CloudConnection = model.connection(provider)
        let description: String = model.description(of: provider)
        let isBusy: Bool = model.busy == provider
        let content = AdaptiveStack(spacing: Spacing.md) {
            IconTile(systemImage: Self.symbol(provider), hue: .steel)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.label)
                    .font(.brand(.body, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                Text(description)
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.sm)
            trailing(provider, connection: connection, isBusy: isBusy, model: model)
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cloud-row-\(provider.rawValue)")
        return presentations(content, for: provider, model: model)
    }

    @ViewBuilder
    private func trailing(
        _ provider: CloudProvider, connection: CloudConnection, isBusy: Bool,
        model: CloudConnectionsModel
    ) -> some View {
        if !connection.isConfigured {
            StatusPill(text: CloudCopy.notAvailable, tone: .neutral)
        } else if isBusy {
            ProgressView()
                .tint(theme.textSecondary)
                .accessibilityLabel("Working")
        } else if connection.isConnected {
            Button("Disconnect") {
                actedOn = provider
                confirming = provider
            }
            .buttonStyle(.quietAction)
            .disabled(model.busy != nil)
            .accessibilityLabel("Disconnect \(provider.label)")
            .accessibilityIdentifier("cloud-disconnect-\(provider.rawValue)")
            .confirmationDialog(
                CloudCopy.disconnectQuestion(provider),
                isPresented: confirmingBinding(provider),
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    Task { await model.disconnect(provider) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(CloudCopy.disconnectMessage)
            }
        } else {
            Button("Connect") {
                actedOn = provider
                Task { await model.connect(provider) }
            }
            .buttonStyle(.compactSecondaryAction)
            .disabled(model.busy != nil)
            .accessibilityLabel("Connect \(provider.label)")
            .accessibilityIdentifier("cloud-connect-\(provider.rawValue)")
        }
    }

    private func failureRow(_ failure: LoadFailure) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(failure.message)
                .font(.brand(.footnote))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if failure.isRetryable {
                Button("Try again") {
                    Task { await model?.load() }
                }
                .buttonStyle(.compactSecondaryAction)
                .accessibilityIdentifier("cloud-retry")
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    static func symbol(_ provider: CloudProvider) -> String {
        provider == .google ? "icloud" : "externaldrive.connected.to.line.below"
    }

    // MARK: - What a row presents

    /// The sign-in page for this drive, the reads while it is up, and why an action failed.
    private func presentations<V: View>(
        _ view: V, for provider: CloudProvider, model: CloudConnectionsModel
    ) -> some View {
        view
            .fullScreenCover(item: pendingBinding(provider), onDismiss: { browserGone(provider) }) { pending in
                browser(pending)
                    // Lives exactly as long as the page: read until the drive says it is connected.
                    .task(id: pending.id) { await model.pollWhileConnecting(pending.provider) }
            }
            .alert("Couldn't do that", isPresented: errorBinding(provider)) {
                Button("OK") { model.error = nil }
            } message: {
                Text(model.error ?? "")
            }
    }

    @ViewBuilder
    private func browser(_ pending: IdentifiedURL) -> some View {
        #if DEBUG
        if UITestSupport.isActive {
            CloudBrowserStub(provider: pending.provider) { model?.pendingURL = nil }
        } else {
            SafariView(url: pending.url) { model?.pendingURL = nil }
                .ignoresSafeArea()
        }
        #else
        SafariView(url: pending.url) { model?.pendingURL = nil }
            .ignoresSafeArea()
        #endif
    }

    private func pendingBinding(_ provider: CloudProvider) -> Binding<IdentifiedURL?> {
        Binding(
            get: {
                guard let pending = model?.pendingURL, pending.provider == provider else { return nil }
                return pending
            },
            set: { newValue in
                if newValue == nil, model?.pendingURL?.provider == provider { model?.pendingURL = nil }
            })
    }

    private func browserGone(_ provider: CloudProvider) {
        guard let model else { return }
        Task { await model.browserClosed(provider) }
    }

    private func confirmingBinding(_ provider: CloudProvider) -> Binding<Bool> {
        Binding(
            get: { confirming == provider },
            set: { if !$0 { confirming = nil } })
    }

    private func errorBinding(_ provider: CloudProvider) -> Binding<Bool> {
        Binding(
            get: { model?.error != nil && actedOn == provider },
            set: { if !$0 { model?.error = nil } })
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let notice = model?.notice {
                Text(notice)
                    .foregroundStyle(theme.success)
                    .accessibilityIdentifier("cloud-notice")
            } else if let hint = model?.hint {
                Text(hint)
                    .foregroundStyle(theme.warning)
                    .accessibilityIdentifier("cloud-hint")
            }
            Text(CloudCopy.footer)
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.brand(.caption))
        // Said as well as shown: it lands in the footer, away from where VoiceOver is.
        .onChange(of: model?.notice) { _, notice in
            if let notice { VoiceOver.announce(notice) }
        }
        // A confirmation is a moment, not a state: it goes after a few seconds.
        .task(id: model?.notice) {
            guard model?.notice != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            model?.notice = nil
        }
    }
}
