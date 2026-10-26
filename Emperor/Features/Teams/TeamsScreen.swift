import SwiftUI

/// Teams: the colleagues tracked court cases are shared with.
///
/// Lists the account's teams, creates one, and adds an existing account to one. An invite is
/// immediate membership, as on the web, so the button says what it does and nothing more.
struct TeamsScreen: View {
    static let isReady = true

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session

    @State private var model: TeamsViewModel?
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.groupedBackground)
            .navigationTitle("Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .recordToast($toast)
            .task {
                guard model == nil else { return }
                let created = TeamsViewModel(service: session.teams)
                model = created
                await created.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: TeamsViewModel) -> some View {
        if model.teams.isEmpty, model.state.isLoading || model.state == .idle {
            ProgressView()
        } else if model.teams.isEmpty, let failure = model.state.failure {
            LoadFailureView(failure: failure, retry: { await model.load() })
        } else {
            form(model)
        }
    }

    private func form(_ model: TeamsViewModel) -> some View {
        List {
            teamsSection(model)
            createSection(model)
            inviteSection(model)
            if let message = model.message {
                Section {
                    Text(message.text)
                        .font(.brand(.subheadline, weight: .semibold))
                        .foregroundStyle(message.isError ? theme.danger : theme.success)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("team-message")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load() }
        .onChange(of: model.message) { _, new in
            if let new, !new.isError { toast = new.text }
        }
    }

    private func teamsSection(_ model: TeamsViewModel) -> some View {
        Section {
            ForEach(model.teams) { team in
                RecordRow(
                    title: team.name, subtitle: team.rowDetail,
                    leading: { IconTile(systemImage: "person.2") },
                    trailing: { StatusPill(text: team.roleLabel, tone: .neutral) }
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("team-row-\(team.id)")
            }
        } header: {
            SectionHeader(title: "Your teams", detail: "\(model.teams.count)")
        } footer: {
            Text("Everyone in a team sees the court cases it tracks, and their hearings, under Matters.")
        }
    }

    private func createSection(_ model: TeamsViewModel) -> some View {
        Section {
            TextField(
                "e.g. Litigation Team",
                text: Binding(get: { model.newTeamName }, set: { model.newTeamName = $0 })
            )
            .submitLabel(.done)
            .onSubmit { Task { await model.create() } }
            .accessibilityIdentifier("team-new-name")
            Button("Create") { Task { await model.create() } }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!model.canCreate)
                .accessibilityIdentifier("team-create")
        } header: {
            SectionHeader(title: "Create a team")
        }
    }

    private func inviteSection(_ model: TeamsViewModel) -> some View {
        Section {
            if model.showsPicker {
                Picker(
                    "Team",
                    selection: Binding(
                        get: { model.inviteTarget?.id ?? "" },
                        set: { model.pickedTeamID = $0 })
                ) {
                    ForEach(model.invitable) { team in
                        Text(team.pickerLabel).tag(team.id)
                    }
                }
                .accessibilityIdentifier("team-invite-target")
            }
            TextField(
                "teammate@email.com",
                text: Binding(get: { model.inviteEmail }, set: { model.inviteEmail = $0 })
            )
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.send)
            .onSubmit { Task { await model.invite() } }
            .disabled(model.invitable.isEmpty)
            .accessibilityIdentifier("team-invite-email")
            Button("Invite") { Task { await model.invite() } }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!model.canInvite)
                .accessibilityIdentifier("team-invite")
        } header: {
            SectionHeader(title: model.inviteHeading)
        } footer: {
            Text(
                model.invitable.isEmpty
                    ? "Only a team's owner can add members."
                    : TeamsViewModel.inviteFootnote)
        }
    }
}
