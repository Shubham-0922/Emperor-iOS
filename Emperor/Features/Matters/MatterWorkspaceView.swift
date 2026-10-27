import SwiftUI
import UIKit

/// One matter's workspace — the web's `ProjectWorkspace.jsx`: the banner with the matter's
/// name, status, parties, court and next hearing; the section bar; and the chosen section under
/// it, all in one scroll. The bar's menu edits, archives or deletes the matter; each section adds and
/// changes its own rows. Pull to refresh fetches the matter again and keeps what is on screen if
/// that fails.
///
/// `MatterWorkspaceViewModel` holds every rule; this lays it out.
struct MatterWorkspaceView: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    let route: MatterRoute
    /// The matter's file count from the list, when it came from there.
    var fileCount: Int?
    /// Opens the linked case's own page on the Matters stack.
    let onOpenCase: (String) -> Void
    /// The matter changed here — edited, archived or deleted — so the list behind it reloads;
    /// with a message for the list to say (a deletion, which leaves this screen).
    var onChanged: ((_ message: String?) -> Void)? = nil

    @State private var model: MatterWorkspaceViewModel?
    @State private var loadedRoute: MatterRoute?
    @State private var quick: MatterQuickActions?
    @State private var court: MatterCourtActions?
    @State private var sheet: MatterSheet?
    @State private var failure: String?
    /// Set once the matter is deleted: the screen leaves when the sheet has gone.
    @State private var leaveAfterSheet = false

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
        .navigationTitle(model?.title ?? "Matter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let project = model?.project, model?.state == .loaded {
                ToolbarItem(placement: .primaryAction) {
                    MatterMenu(
                        isArchived: project.isArchived,
                        onEdit: { sheet = .details(focus: nil) },
                        onArchive: { archive(!project.isArchived) },
                        onDelete: { sheet = .delete })
                }
            }
        }
        .sheet(item: $sheet, onDismiss: {
            if leaveAfterSheet { dismiss() }
        }) { which in
            sheetView(which)
        }
        .alert("That did not go through", isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
        .task(id: route) {
            // A fresh request for this matter (`MatterRoute.request`) is a fresh screen; coming
            // back to it from the case page is not, and keeps its section.
            guard model == nil || loadedRoute != route else { return }
            loadedRoute = route
            let created = MatterWorkspaceViewModel(
                projectID: route.projectID, service: session.projects, section: route.section,
                fileCount: fileCount)
            model = created
            quick = MatterQuickActions(projectID: route.projectID, writes: session.projectWrites)
            court = MatterCourtActions(
                projectID: route.projectID, writes: session.projectWrites, tracking: session.caseTracking)
            await created.load()
            await created.loadBanner()
        }
    }

    @ViewBuilder
    private func content(_ model: MatterWorkspaceViewModel) -> some View {
        @Bindable var bindable = model
        switch model.state {
        case .missing:
            EmptyStateView(
                "Matter not found", systemImage: "tray",
                message: "It may have been deleted, or it belongs to another account.", tone: .neutral)
        case .failed(let failure) where model.detail == nil:
            LoadFailureView(failure: failure, retry: { await model.load() })
        default:
            if model.detail == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        if let header = model.header {
                            MatterHeaderView(
                                header: header, preset: model.project?.bannerPreset ?? .navy,
                                imageData: model.bannerData,
                                height: sizeClass == .regular ? 104 : 132)
                        }
                        MatterSectionBar(
                            sections: model.visibleSections, counts: model.navCounts,
                            selection: $bindable.section)
                        sectionBody(model)
                    }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.xxxl)
                    .frame(maxWidth: ReadableWidth.cap(for: sizeClass))
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await model.reload() }
                .recordToast($bindable.toast)
            }
        }
    }

    @ViewBuilder
    private func sectionBody(_ model: MatterWorkspaceViewModel) -> some View {
        let edit = editActions(model)
        switch model.section {
        case .overview: MatterOverviewSection(model: model, edit: edit)
        case .chronology: MatterChronologySection(model: model, edit: edit)
        case .court: MatterCourtSection(model: model, onOpenCase: onOpenCase, edit: edit)
        case .tasks: MatterTasksSection(model: model, edit: edit)
        case .fees: MatterFeesSection(model: model, edit: edit)
        case .people: MatterPeopleSection(model: model, edit: edit)
        case .ask: MatterAskSection(model: model)
        case .files: MatterFilesSection(workspace: model)
        case .drafts: MatterDraftsSection(workspace: model)
        }
    }
}

// MARK: - Writing

extension MatterWorkspaceView {

    /// The sections' way to change the matter; nil until the actions exist.
    private func editActions(_ model: MatterWorkspaceViewModel) -> MatterEditActions? {
        guard let quick, let court else { return nil }
        return MatterEditActions(
            open: { sheet = $0 },
            quick: quick, court: court,
            reload: { await model.reload(); onChanged?(nil) },
            done: { model.toast = $0 },
            failed: { failure = $0 })
    }

    private func archive(_ archived: Bool) {
        guard let model, let quick else { return }
        Task {
            if await quick.setArchived(archived) {
                model.toast = archived ? "Matter archived" : "Matter restored to active"
                await model.reload()
                onChanged?(nil)
            } else if let error = quick.error {
                failure = error
            }
        }
    }

    @ViewBuilder
    private func sheetView(_ which: MatterSheet) -> some View {
        if let model, let detail = model.detail {
            let project = detail.project
            let reload: @MainActor () -> Void = {
                Task {
                    await model.reload()
                    onChanged?(nil)
                }
            }
            switch which {
            case .details(let focus):
                MatterDetailsSheet(project: project, focusField: focus, bannerData: model.bannerData) { message in
                    model.toast = message
                    Task {
                        await model.reload()
                        await model.loadBanner()
                        onChanged?(nil)
                    }
                }
                .pageSizedSheet()
            case .delete:
                DeleteMatterSheet(project: project) { message in
                    leaveAfterSheet = true
                    onChanged?(message)
                }
            case .entry(let entry):
                ChronologyEntrySheet(projectID: project.id, entry: entry, today: model.todayKey) { saved in
                    model.applyNextHearing(saved.nextHearingDate)
                    model.toast = entry == nil ? "Added to the chronology" : "Entry updated"
                    reload()
                }
            case .task(let task, let kind):
                TaskSheet(projectID: project.id, task: task, kind: kind) {
                    model.toast = task == nil ? "Task added" : "Task saved"
                    reload()
                }
            case .ledger(let entry, let kind):
                LedgerEntrySheet(projectID: project.id, entry: entry, kind: kind, today: model.todayKey) {
                    model.toast = entry == nil ? "Entry added" : "Entry saved"
                    reload()
                }
            case .person(let person, let role, let name):
                PersonSheet(projectID: project.id, person: person, role: role, name: name) {
                    model.toast = person == nil ? "Person added" : "Person saved"
                    reload()
                }
            case .receipt(let entry):
                ReceiptShare(
                    html: MatterPrintouts.receiptHTML(entry: entry, detail: detail, user: session.currentUser),
                    fileName: MatterPrintouts.receiptFileName(entry))
                    .pageSizedSheet()
            case .listOfDates:
                ListOfDatesShare(
                    html: MatterPrintouts.listOfDatesHTML(detail: detail),
                    fileName: MatterPrintouts.listOfDatesFileName(project))
                    .pageSizedSheet()
            case .linkCase:
                CourtSearchView(onSaved: {}, onPick: { result in
                    sheet = nil
                    link(result, matter: project)
                })
                .pageSizedSheet()
            }
        }
    }

    private func link(_ result: CourtSearchResult, matter: Project) {
        guard let model, let court else { return }
        Task {
            if await court.link(result, matter: matter) {
                model.toast = court.message
                await model.reload()
                onChanged?(nil)
            } else if let error = court.error {
                failure = error
            }
        }
    }
}

/// The banner at the head of the workspace: the name over the matter's banner, on the plate's
/// dark glass so white text reads over every preset and photograph.
private struct MatterHeaderView: View {
    let header: MatterWorkspaceViewModel.Header
    let preset: MatterVocabulary.BannerPreset
    let imageData: Data?
    let height: CGFloat

    @ScaledMetric(relativeTo: .caption) private var dot: CGFloat = 7

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(header.name)
                    .font(.display(size: 24, relativeTo: .title2))
                    .dynamicLineLimit(3)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                statusChip
            }
            if !header.parties.isEmpty {
                Text(header.parties)
                    .font(.brand(.footnote))
                    .fixedSize(horizontal: false, vertical: true)
            }
            facts
        }
        .foregroundStyle(Color.white)
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .bottomLeading)
        .background {
            MatterBannerView(preset: preset, imageData: imageData, cornerRadius: Radius.card) {
                Color(MatterBanner.plate)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("matter-header")
    }

    private var statusChip: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(Color(PaletteColor(hex: MatterBanner.statusDot[header.status] ?? 0x4ADE80)))
                .frame(width: dot, height: dot)
                .accessibilityHidden(true)
            Text(header.status.label)
        }
        .font(.brand(size: 11.5, weight: .bold, relativeTo: .caption2))
        .glassChip()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(header.status.label)")
    }

    private var facts: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) { factChips }
            VStack(alignment: .leading, spacing: Spacing.xs) { factChips }
        }
    }

    @ViewBuilder
    private var factChips: some View {
        if !header.forumLine.isEmpty {
            Label(header.forumLine, systemImage: "building.columns")
                .glassChip()
        }
        if !header.cnr.isEmpty {
            HStack(spacing: Spacing.xs) {
                Text("\(header.cnrLabel) \(header.cnr)")
                    .monospacedDigit()
                Button {
                    UIPasteboard.general.string = header.cnr
                    VoiceOver.announce("Copied")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(minWidth: Layout.touchTarget, minHeight: Layout.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(header.cnrLabel == "CNR" ? "Copy CNR" : "Copy diary number")
            }
            .glassChip()
        }
        if header.notFiled {
            Label("Not filed yet", systemImage: "clock.badge.questionmark")
                .glassChip()
        }
        Label(header.nextText, systemImage: "calendar")
            .glassChip(emphasis: header.nextTone == .danger || header.nextTone == .warn)
            .accessibilityIdentifier("matter-next-hearing")
    }
}

private extension View {
    /// White words on a pane of glass over the banner's plate.
    func glassChip(emphasis: Bool = false) -> some View {
        self
            .font(.brand(size: 12, weight: emphasis ? Font.Weight.bold : Font.Weight.semibold, relativeTo: .caption))
            .foregroundStyle(Color.white)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                Color.white.opacity(emphasis ? 0.2 : 0.1),
                in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .strokeBorder(Color(MatterBanner.plateBorder), lineWidth: 1))
    }
}
