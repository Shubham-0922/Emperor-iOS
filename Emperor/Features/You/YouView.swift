import SwiftUI

/// Account & Profile: the account and its standing, how answers start, the role, appearance,
/// the way to usage, billing and settings, search, and signing out.
///
/// The design's screen, in the mock's order: the profile card led by the avatar, the demo-tour
/// stand-in, appearance, the current role with its way to switch it, one card holding **Usage**
/// (this month's allowances, on their own screen), **Billings** (the stand-in — the app takes no
/// money yet) and **Settings** (the design's screen: the advocate profile and its save, the
/// briefings with Notifications within, chambers, app & legal with About & Compliance, and
/// delete), the spotlight search, and Sign Out from Device.
///
/// What used to be rows here has moved: notifications and app lock are inside Settings, offline
/// storage is on More, and the Tools rows belong to More alone (see `MoreView`); the default
/// answer mode is the composer's own chip, not a preference.
struct YouView: View {
    @Environment(Session.self) private var session
    @Environment(\.theme) private var theme
    @Environment(\.practice) private var practice
    @Environment(\.scenePhase) private var scenePhase

    @State private var isConfirmingSignOut = false
    /// The Usage row's own load — its subtitle reads the same entitlements the allowances
    /// screen shows, so the row never claims a plan the account has moved off.
    @State private var usage: AccountUsageViewModel?

    var body: some View {
        NavigationStack {
            List {
                if let user = session.currentUser {
                    Section {
                        NavigationLink {
                            EditProfileView()
                        } label: {
                            profile(user)
                        }
                        .accessibilityIdentifier("edit-profile")
                    }
                    .listRowBackground(theme.surface)

                    Section {
                        demoTourRow
                    }
                    .listRowBackground(theme.surface)
                }

                Section {
                    RecordSegmentedControl(
                        label: "Appearance",
                        options: ThemePreference.allCases.map { (value: $0, title: $0.label) },
                        selection: Binding(
                            get: { theme.preference },
                            set: { theme.select($0) }))
                        .listRowInsets(EdgeInsets(top: Spacing.sm, leading: Spacing.md, bottom: Spacing.sm, trailing: Spacing.md))
                } header: {
                    SectionHeader(title: "Appearance")
                }
                .listRowBackground(theme.surface)

                Section {
                    roleCard
                } footer: {
                    footnote("The role changes the suggestions on Ask and how answers are written, and is saved to your account, so the web opens in the same role.")
                }
                .listRowBackground(theme.surface)

                Section {
                    NavigationLink {
                        UsagePlanView()
                    } label: {
                        IconRowLabel(
                            title: "Usage", systemImage: "chart.bar",
                            subtitle: usageSubtitle)
                    }
                    .accessibilityIdentifier("settings-usage")

                    Button {
                        // Invoices and GST receipts — the app takes no money yet, so there is
                        // nothing to list. The row is the design's, standing in like Chambers.
                    } label: {
                        HStack(spacing: Spacing.md) {
                            IconTile(systemImage: "doc.plaintext")
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text("Billings")
                                    .font(.brand(.body, weight: .medium))
                                    .foregroundStyle(theme.textPrimary)
                                    .dynamicLineLimit(2)
                                Text("Invoices, GST receipts & chamber payment")
                                    .font(.brand(.footnote))
                                    .foregroundStyle(theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: Spacing.sm)
                            StatusPill(text: "Paid")
                        }
                        .padding(.vertical, Spacing.xxs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Billings, Paid")
                    .accessibilityIdentifier("settings-billings")

                    NavigationLink {
                        SettingsView()
                    } label: {
                        IconRowLabel(
                            title: "Settings", systemImage: "gearshape",
                            subtitle: "Security, citation preferences & offline cache")
                    }
                    .accessibilityIdentifier("settings-entry")
                }
                .listRowBackground(theme.surface)
                .task {
                    if usage == nil { usage = AccountUsageViewModel(service: session.usage) }
                    await usage?.load()
                }
                // Back from the plans page in the browser, where the account's plan may have
                // changed — the same two reloads `PlanUsageSection` does for itself.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { reloadUsage() }
                }
                .onChange(of: session.currentUser?.planLabel) { _, _ in reloadUsage() }

                Section {
                    let isIndexing = AppSpotlight.shared.coordinator.isEnabled
                    Toggle(isOn: Binding(
                        get: { isIndexing },
                        set: {
                            Haptics.selection()
                            AppSpotlight.shared.setEnabled($0)
                        }
                    )) {
                        IconRowLabel(title: SpotlightCoordinator.Copy.toggle, systemImage: "magnifyingglass")
                    }
                    .tint(theme.accentText)
                    .accessibilityIdentifier("spotlight-toggle")
                } header: {
                    SectionHeader(title: "Search")
                } footer: {
                    footnote(SpotlightCoordinator.Copy.footer)
                }
                .listRowBackground(theme.surface)

                Section {
                    Button {
                        Haptics.warning()
                        isConfirmingSignOut = true
                    } label: {
                        Label("Sign Out from Device", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.destructiveAction)
                    .accessibilityIdentifier("Sign out")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    VStack(spacing: Spacing.xs) {
                        Text("Signing out removes your credentials and every matter cached on this device.")
                        Text(versionLine)
                            .monospacedDigit()
                    }
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Spacing.sm)
                }
            }
            .font(.brand(.body))
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.groupedBackground)
            .navigationTitle("Account & Profile")
            .navigationBarTitleDisplayMode(.large)
            .confirmationDialog(
                "Sign out of Emperor?",
                isPresented: $isConfirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    Task { await session.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Cached matters on this device will be removed.")
            }
        }
    }

    // MARK: - The current role

    /// The role as its own card — the overline, the role in the account's own words, and the
    /// way to switch it, as the mock draws it. The whole card is the link; "Switch" is what it
    /// promises, not a second target.
    private var roleCard: some View {
        NavigationLink {
            RolePickerView()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("CURRENT ROLE")
                    .font(.brand(.caption2, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                HStack(spacing: Spacing.sm) {
                    Image(systemName: practice.role.systemImage)
                        .foregroundStyle(theme.accentText)
                        .accessibilityHidden(true)
                    Text(practice.role.label)
                        .font(.brand(.body, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .dynamicLineLimit(2)
                    Spacer(minLength: Spacing.sm)
                    Text("Switch")
                        .font(.brand(.subheadline, weight: .semibold))
                        .foregroundStyle(theme.accentText)
                }
            }
            .padding(.vertical, Spacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current role, \(practice.role.label)")
        .accessibilityHint("Opens the role picker")
        .accessibilityIdentifier("Role selector")
    }

    // MARK: - Profile

    /// The design's card: the standing pill, the avatar centred, the name, the address, and the
    /// plan as its own pill — the whole card the way into the editor.
    private func profile(_ user: User) -> some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                StatusPill(text: "Active session", tone: .success, systemImage: "checkmark.shield")
                Spacer(minLength: 0)
            }
            AccountAvatar(
                photo: ProfilePhoto.source(of: user.avatar),
                monogram: ProfilePhoto.monogram(name: user.name, email: user.email),
                size: 72)
            VStack(spacing: Spacing.xxs) {
                Text(displayName(user))
                    .font(.brand(.title3, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let email = user.email {
                    Text(email)
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(roleLine(user))
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            StatusPill(
                text: "\(session.currentUser?.planLabel ?? "PRO") plan",
                tone: .accent,
                systemImage: "star")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("account-profile")
    }

    /// The design's guide card. The tour itself is not built yet — the row is the promise, the
    /// same stand-in the More tab's case-tool cards are.
    private var demoTourRow: some View {
        Button {
            // A later step: the walkthrough of research, cause lists and citations.
        } label: {
            HStack(spacing: Spacing.sm) {
                IconTile(systemImage: "map", size: .large)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text("Start Demo Tour")
                            .font(.brand(.subheadline, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .dynamicLineLimit(2)
                        StatusPill(text: "Guide", tone: .info)
                    }
                    Text("Walkthrough research, cause lists & citations")
                        .font(.brand(.caption))
                        .foregroundStyle(theme.textTertiary)
                        .dynamicLineLimit(2)
                }
                Spacer(minLength: Spacing.sm)
                Text("Start")
                    .font(.brand(.subheadline, weight: .semibold))
                    .foregroundStyle(theme.accentText)
                RowChevron()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start Demo Tour")
        .accessibilityHint("Walkthrough research, cause lists and citations")
    }

    private func displayName(_ user: User) -> String {
        let name = user.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Your account" : name
    }

    /// "Advocate · Litigator" — the title the account gives, then the role practised in.
    private func roleLine(_ user: User) -> String {
        let parts = [user.title, user.organization]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return (parts + [practice.role.label]).joined(separator: " · ")
    }

    // MARK: - Usage

    /// What the Usage row says under its title: the first allowance worth showing, straight
    /// from the account's own entitlements — or the plain words until the load answers.
    private var usageSubtitle: String {
        guard let meter = usage?.visibleMeters.first else { return "Plan & allowances" }
        return "\(meter.title): \(meter.summary)"
    }

    private func reloadUsage() {
        let usage = usage
        Task { await usage?.load() }
    }

    // MARK: - Pieces

    private var versionLine: String {
        // The same read as About & Compliance and Settings's App row — one answer to "which
        // build", wherever a bug report finds it (`AppVersion`).
        "Emperor \(AppVersion.short) (\(AppVersion.build))"
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.brand(.caption))
            .foregroundStyle(theme.textTertiary)
    }
}
