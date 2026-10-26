import SwiftUI
import UIKit

/// One matter's workspace — the web's `ProjectWorkspace.jsx`: the banner with the matter's
/// name, status, parties, court and next hearing; the section bar; and the chosen section under
/// it, all in one scroll. Read-only in this build. Pull to refresh fetches the matter again and
/// keeps what is on screen if that fails.
///
/// `MatterWorkspaceViewModel` holds every rule; this lays it out.
struct MatterWorkspaceView: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass

    let route: MatterRoute
    /// The matter's file count from the list, when it came from there.
    var fileCount: Int?
    /// Opens the linked case's own page on the Matters stack.
    let onOpenCase: (String) -> Void

    @State private var model: MatterWorkspaceViewModel?
    @State private var loadedRoute: MatterRoute?

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
        .task(id: route) {
            // A fresh request for this matter (`MatterRoute.request`) is a fresh screen; coming
            // back to it from the case page is not, and keeps its section.
            guard model == nil || loadedRoute != route else { return }
            loadedRoute = route
            let created = MatterWorkspaceViewModel(
                projectID: route.projectID, service: session.projects, section: route.section,
                fileCount: fileCount)
            model = created
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
        switch model.section {
        case .overview: MatterOverviewSection(model: model)
        case .chronology: MatterChronologySection(model: model)
        case .court: MatterCourtSection(model: model, onOpenCase: onOpenCase)
        case .tasks: MatterTasksSection(model: model)
        case .fees: MatterFeesSection(model: model)
        case .people: MatterPeopleSection(model: model)
        // Not on the bar while `MatterAvailability.contentSections` is off.
        case .ask, .files, .drafts:
            EmptyStateContent(
                title: model.section.label, systemImage: "hourglass",
                message: "This part of the matter opens on the web for now.", tone: .neutral) {}
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
