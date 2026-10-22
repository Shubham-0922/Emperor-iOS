import SwiftUI
import UIKit

/// Settings — the design's screen, reached from Account & Profile: the advocate profile and its
/// save, the three briefings, chambers, app & legal (About & Compliance within), and delete,
/// under the design's own footer.
///
/// Everything the mock draws is drawn. What has no backing yet — chambers, add account, the
/// update check, delete — stands in the way the More tab's case-tool cards do: styled, named,
/// and doing nothing rather than pretending. What does have a backend is wired straight to it:
/// the profile saves through `ProfileEditor` (every field on every save, a name required), and
/// the three switches are `NotificationSettingsViewModel`'s own — the same preferences the
/// Notifications screen edits, so the two screens can never disagree about the account.
struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(\.theme) private var theme

    @State private var profile: ProfileEditor?
    @State private var notifications: NotificationSettingsViewModel?
    /// The screen pushed from this one: the editor behind the header, About & Compliance behind
    /// its row. One destination for both, so neither row needs the disclosure chevron iOS adds
    /// to a `NavigationLink` — the design draws its own glyph instead.
    @State private var destination: Destination?
    @FocusState private var focusedField: String?

    private enum Destination: Hashable {
        case editor
        case about
    }

    var body: some View {
        Group {
            if let profile, let notifications {
                content(profile, notifications)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.canvas)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if profile == nil, let user = session.currentUser {
                let account = session
                profile = ProfileEditor(user: user, service: account.profile) { saved in
                    account.adoptProfile(saved)
                }
            }
            if notifications == nil {
                notifications = NotificationSettingsViewModel(
                    coordinator: AppNotifications.shared.coordinator,
                    emailService: NotificationOptInService(client: session.client),
                    account: NotificationAccount(session: session),
                    emailAddress: session.currentUser?.email)
            }
            await notifications?.load()
        }
        // What a switch or a save came to, said as it appears — the Notifications screen's rule.
        .onChange(of: notifications?.notice) { _, notice in
            if let notice { VoiceOver.announce(notice) }
        }
        .onChange(of: notifications?.emailNotice) { _, notice in
            if let notice { VoiceOver.announce(notice) }
        }
        .onChange(of: profile?.saveError) { _, error in
            if let error { VoiceOver.announce(error) }
        }
    }

    private func content(_ model: ProfileEditor, _ notifications: NotificationSettingsViewModel) -> some View {
        @Bindable var bindable = model
        return List {
            headerSection(bindable)
            advocateSection(bindable)
            saveRow(bindable)
            briefingsSection(notifications)
            chambersSection
            appLegalSection
            deleteSection
        }
        .font(.brand(.body))
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(theme.groupedBackground)
        .accessibilityIdentifier("settings-screen")
        .navigationDestination(item: $destination) { destination in
            switch destination {
            case .editor: EditProfileView()
            case .about: AboutComplianceView()
            }
        }
    }

    // MARK: - Header

    /// The account over the avatar, the design's camera badge on its corner — into the editor,
    /// the way the profile card on You does.
    private func headerSection(_ model: ProfileEditor) -> some View {
        Section {
            Button {
                destination = .editor
            } label: {
                VStack(spacing: Spacing.sm) {
                    AccountAvatar(photo: model.photo, monogram: model.monogram, size: 72)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.brand(size: 10, weight: .semibold, relativeTo: .caption2))
                                .foregroundStyle(theme.onAccent)
                                .frame(width: 24, height: 24)
                                .background(theme.accentText, in: Circle())
                                .overlay(Circle().strokeBorder(theme.surface, lineWidth: 2))
                                .accessibilityHidden(true)
                        }
                    Text(displayName(model))
                        .font(.brand(.title3, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit profile, \(displayName(model))")
            .accessibilityIdentifier("settings-profile")
        }
        .listRowBackground(Color.clear)
    }

    private func displayName(_ model: ProfileEditor) -> String {
        let name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Your account" : name
    }

    // MARK: - Advocate profile

    /// The four fields as the design draws them — the label on the left, its value in a box on
    /// the right — saving through the same editor as Edit profile, where an absent field would
    /// clear its column on the server.
    private func advocateSection(_ model: ProfileEditor) -> some View {
        @Bindable var bindable = model
        return Section {
            fieldRow(
                "Full name", placeholder: ProfileEditor.Copy.namePlaceholder,
                text: $bindable.name, id: "settings-name", contentType: .name)
            fieldRow(
                "Designation", placeholder: ProfileEditor.Copy.titlePlaceholder,
                text: $bindable.title, id: "settings-designation", contentType: .jobTitle, wraps: true)
            fieldRow(
                "Organisation", placeholder: ProfileEditor.Copy.organizationPlaceholder,
                text: $bindable.organization, id: "settings-organisation",
                contentType: .organizationName, wraps: true)
            // Shown, not edited: the address is the sign-in — Edit profile says so beside it.
            boxedValue("Email", value: model.email ?? "—", id: "settings-email")
        } header: {
            SectionHeader(title: "Advocate profile")
        } footer: {
            if let problem = model.nameProblem {
                footnote(problem, tone: theme.warning)
            } else if let error = model.saveError {
                footnote(error, tone: theme.warning)
            }
        }
        .listRowBackground(theme.surface)
    }

    /// One field: label left, its box at the trailing edge, the value right-aligned inside it.
    /// Stacked under a large text size, where two columns would give neither room to be read.
    private func fieldRow(
        _ label: String, placeholder: String, text: Binding<String>, id: String,
        contentType: UITextContentType, wraps: Bool = false
    ) -> some View {
        AdaptiveStack(spacing: Spacing.sm) {
            Text(label)
                .font(.brand(.body))
                .foregroundStyle(theme.textSecondary)
                .accessibilityHidden(true)
            // The example in the palette's tertiary — the system's placeholder grey is about
            // 2.4:1 on a dark card (`EditProfileView.field`'s own reason).
            let prompt = Text(verbatim: placeholder).foregroundStyle(theme.textTertiary)
            Group {
                if wraps {
                    // One paragraph, as Edit profile keeps its wrapping fields: Return is
                    // "done", and the line break it would type never reaches the account.
                    TextField(label, text: oneParagraph(text), prompt: prompt, axis: .vertical)
                        .lineLimit(1...4)
                } else {
                    TextField(label, text: text, prompt: prompt)
                }
            }
            .multilineTextAlignment(.trailing)
            .font(.brand(.body, weight: .semibold))
            .foregroundStyle(theme.textPrimary)
            .textContentType(contentType)
            .submitLabel(.done)
            .focused($focusedField, equals: id)
            .padding(.horizontal, Spacing.sm)
            .frame(minHeight: 36)
            .background(theme.surface2, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(theme.separator, lineWidth: 1))
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
        }
        .padding(.vertical, Spacing.xxs)
    }

    /// The text as one paragraph, exactly as `EditProfileView.oneParagraph` holds the same
    /// fields on the other screen — the newline a wrapped field's Return types is taken as
    /// "done" and dropped, so a designation saved from here reads the same as one saved there.
    private func oneParagraph(_ text: Binding<String>) -> Binding<String> {
        Binding(
            get: { text.wrappedValue },
            set: { new in
                guard new.contains("\n") else {
                    text.wrappedValue = new
                    return
                }
                text.wrappedValue = new.replacingOccurrences(of: "\n", with: "")
                focusedField = nil
            })
    }

    /// The same box with a value in it, for the field that is read rather than typed.
    private func boxedValue(_ label: String, value: String, id: String) -> some View {
        AdaptiveStack(spacing: Spacing.sm) {
            Text(label)
                .font(.brand(.body))
                .foregroundStyle(theme.textSecondary)
                .accessibilityHidden(true)
            Text(value)
                .font(.brand(.body, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, Spacing.sm)
                .frame(minHeight: 36, maxWidth: .infinity, alignment: .trailing)
                .background(theme.surface2, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(theme.separator, lineWidth: 1))
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
        }
        .padding(.vertical, Spacing.xxs)
    }

    /// "✓ Save Changes", right-aligned between the profile card and the briefings, as the design
    /// places it — enabled only when something really changed, and the name is there.
    private func saveRow(_ model: ProfileEditor) -> some View {
        Section {
            HStack {
                Spacer(minLength: Spacing.sm)
                Button {
                    Task {
                        if await model.save() { VoiceOver.announce("Profile saved") }
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        if model.isSaving {
                            ProgressView().tint(theme.onInverse)
                        } else {
                            Image(systemName: "checkmark")
                                .imageScale(.small)
                                .accessibilityHidden(true)
                            Text("Save Changes")
                        }
                    }
                    .font(.brand(.subheadline, weight: .semibold))
                    .foregroundStyle(model.canSave ? theme.onInverse : theme.textTertiary)
                    .padding(.horizontal, Spacing.md)
                    // A full tap target, not the design's slimmer pill: the audit measures it.
                    .frame(minHeight: 44)
                    .background(
                        model.canSave ? theme.inverse : theme.surface2,
                        in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!model.canSave)
                .accessibilityLabel("Save Changes")
                .accessibilityIdentifier("settings-save")
            }
            .padding(.vertical, Spacing.xxs)
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Briefings & notifications

    /// The three switches the design names, on the notification view model's own preferences:
    /// the cause list's morning briefing, the account's daily email, and the master switch over
    /// both. The Notifications screen edits the same state.
    private func briefingsSection(_ model: NotificationSettingsViewModel) -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { model.preferences.morningBriefing },
                set: { on in Task { await model.setMorningBriefing(on) } }
            )) {
                Text("Daily Cause List")
                    .font(.brand(.body, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .dynamicLineLimit(2)
            }
            .tint(theme.accentText)
            .accessibilityIdentifier("settings-daily-cause-list")

            switch model.email {
            case .loading:
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                    Text("Loading…")
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textSecondary)
                }
            case .failed:
                HStack(spacing: Spacing.sm) {
                    Text(NotificationSettingsViewModel.Copy.emailFailed)
                        .font(.brand(.subheadline))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Spacing.sm)
                    Button("Try again") {
                        Task { await model.loadEmail() }
                    }
                    .font(.brand(.footnote, weight: .semibold))
                }
                .padding(.vertical, Spacing.xxs)
            case .loaded:
                Toggle(isOn: Binding(
                    get: { model.emailSwitchIsOn },
                    set: { on in Task { await model.setEmailBriefing(on) } }
                )) {
                    Text("Email Briefing")
                        .font(.brand(.body, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .dynamicLineLimit(2)
                }
                .tint(theme.accentText)
                .disabled(model.isChangingEmail)
                .accessibilityIdentifier("settings-email-briefing")
            }

            Toggle(isOn: Binding(
                get: { model.switchIsOn },
                set: { on in Task { await model.setEnabled(on) } }
            )) {
                Text("Push Notifications")
                    .font(.brand(.body, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .dynamicLineLimit(2)
            }
            .tint(theme.accentText)
            .disabled(model.isBusy)
            .accessibilityIdentifier("settings-push-notifications")
        } header: {
            SectionHeader(title: "Briefings & notifications")
        } footer: {
            // Only when there is something to say: a switch that will not deliver, or what the
            // last change came to.
            if let notice = model.emailNotice {
                footnote(notice)
            } else if model.isBlocked {
                footnote(NotificationSettingsViewModel.Copy.blocked, tone: theme.warning)
            } else if !model.isOn {
                footnote("Push notifications are off, so nothing is delivered until they're on.")
            }
        }
        .listRowBackground(theme.surface)
    }

    // MARK: - Chambers

    /// The account's own chambers as the default one, and a way to add another — drawn as the
    /// design draws them. There is one chamber and no second account yet, so neither row leaves
    /// the screen: the stand-in the case-tool cards are.
    private var chambersSection: some View {
        Section {
            Button {
                // One chamber, and no way to switch between accounts yet.
            } label: {
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(theme.success)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(chamberName)
                        .font(.brand(.body, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .dynamicLineLimit(2)
                    Spacer(minLength: Spacing.sm)
                    StatusPill(text: "Default")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(chamberName), default chamber")
            .accessibilityIdentifier("settings-chamber")

            Button {
                // Accounts to add — a later step, with the sign-in flows behind them.
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "plus")
                        .font(.brand(.body, weight: .semibold))
                        .foregroundStyle(theme.accentText)
                        .accessibilityHidden(true)
                    Text("Add Account")
                        .font(.brand(.body, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                    Spacer(minLength: Spacing.sm)
                    RowChevron()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings-add-account")
        } header: {
            SectionHeader(title: "Chambers")
        }
        .listRowBackground(theme.surface)
    }

    /// The chambers the account names, or the plain words for one when it names none.
    private var chamberName: String {
        let organization = session.currentUser?.organization?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return organization.isEmpty ? "Your chambers" : organization
    }

    // MARK: - App & legal

    private var appLegalSection: some View {
        Section {
            HStack(spacing: Spacing.sm) {
                Text("App Updates")
                    .font(.brand(.body, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .dynamicLineLimit(2)
                Spacer(minLength: Spacing.sm)
                // The built version, so a bug report names the right build; "(Latest)" is the
                // design's word — nothing has been checked against a store yet.
                Text("v\(AppVersion.short) (Latest)")
                    .font(.brand(.footnote))
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                Button {
                    // No store listing to check against yet — the row is the design's.
                } label: {
                    Text("Check")
                        .font(.brand(.footnote, weight: .semibold))
                        .foregroundStyle(theme.onInverse)
                        .padding(.horizontal, Spacing.sm)
                        // 44 points minimum, as for Save — the audit measures the pill.
                        .frame(minHeight: 44)
                        .background(theme.inverse, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Check for updates")
            }
            .padding(.vertical, Spacing.xxs)

            Button {
                destination = .about
            } label: {
                HStack(spacing: Spacing.sm) {
                    Text("About & Compliance")
                        .font(.brand(.body, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .dynamicLineLimit(2)
                    Spacer(minLength: Spacing.sm)
                    Image(systemName: "arrow.up.right.square")
                        .font(.brand(.footnote, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("about-compliance")
        } header: {
            SectionHeader(title: "App & legal")
        }
        .listRowBackground(theme.surface)
    }

    // MARK: - Delete

    /// The danger row, and the design's footer under it. Deletion itself happens with support —
    /// there is no self-serve route yet — so the row is drawn, not wired.
    private var deleteSection: some View {
        Section {
            Button {
                // Self-serve deletion — a later step, with the route behind it.
            } label: {
                HStack(spacing: Spacing.sm) {
                    Text("Delete Account")
                        .font(.brand(.body, weight: .medium))
                        .foregroundStyle(theme.danger)
                        .dynamicLineLimit(2)
                    Spacer(minLength: Spacing.sm)
                    Image(systemName: "chevron.right")
                        .font(.brand(.footnote, weight: .semibold))
                        .foregroundStyle(theme.danger)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings-delete")
        } footer: {
            VStack(spacing: Spacing.xxs) {
                Text("Emperor AI Law Engine · SOC-2 Type II Certified")
                Text("Subject to Indian Evidence Act digital custody standards.")
            }
            .font(.brand(.caption))
            .foregroundStyle(theme.textTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.sm)
        }
        .listRowBackground(theme.surface)
    }

    // MARK: - Pieces

    private func footnote(_ text: String, tone: Color? = nil) -> some View {
        Text(text)
            .font(.brand(.caption))
            .foregroundStyle(tone ?? theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
