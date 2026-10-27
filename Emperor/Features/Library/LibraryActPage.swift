import SwiftUI

/// The statute reading room: one Act with everything made under it — its Rules, Regulations,
/// Notifications, Amendments, other editions — a tab each, the tab's instruments as a list, and the
/// one chosen read below it (iPhone) or beside it (iPad) (`act/ActPage.jsx`).
///
/// The Act's text is a PDF; there are no sections on the server, so the tabs and the instrument
/// list are its table of contents.
struct LibraryActPage: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass

    let id: Int
    var seed: LibraryDoc?

    @State private var model: LibraryActViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.groupedBackground)
        .navigationTitle(model?.title.isEmpty == false ? (model?.title ?? "") : (seed.map(LibraryDisplay.actTitle) ?? "Act"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Link(destination: LibraryLinks.act(id: id, apiBaseURL: APIConfig.current.baseURL)) {
                    Label("Open on the web", systemImage: "safari")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-act")
        .task {
            guard model == nil else { return }
            let created = LibraryActViewModel(id: id, seed: seed, service: session.library)
            model = created
            await created.load()
        }
    }

    @ViewBuilder
    private func content(_ model: LibraryActViewModel) -> some View {
        if let failure = model.state.failure {
            EmptyStateView(model.failureTitle, systemImage: "scroll",
                           message: model.isNotFound ? "The link may be old. Find the Act in the index instead." : failure.message,
                           tone: .neutral) {
                if failure.isRetryable, !model.isNotFound {
                    Button("Try again") { Task { await model.load() } }
                        .buttonStyle(.primaryAction)
                }
            }
        } else if model.bundle == nil {
            VStack(spacing: 0) {
                header(model)
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if sizeClass == .regular {
            VStack(spacing: 0) {
                header(model)
                tabBar(model)
                HStack(spacing: 0) {
                    ScrollView {
                        instrumentList(model)
                            .padding(Spacing.md)
                    }
                    .frame(width: 360)
                    Rectangle().fill(theme.separator).frame(width: 1)
                    pane(model)
                }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    header(model)
                    tabBar(model)
                    instrumentList(model)
                        .padding(.horizontal, Spacing.gutter)
                }
                .padding(.bottom, Spacing.xxl)
            }
        }
    }

    // MARK: - Header

    private func header(_ model: LibraryActViewModel) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            if let act = model.act {
                LibraryCoverView(doc: act, width: 56, showsImage: false)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if !model.kicker.isEmpty {
                    Text(model.kicker.joined(separator: " · "))
                        .recordText(RecordTokens.Typography.label)
                        .foregroundStyle(theme.textTertiary)
                }
                Text(model.title)
                    .font(.serif(.title3, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: Spacing.xs) {
                    if model.isRepealed { StatusPill(text: "Repealed", tone: .danger) }
                    if let notice = model.notice { StatusPill(text: notice, tone: .neutral) }
                }
                if !model.holds.isEmpty {
                    Text(model.holds)
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textSecondary)
                }
                if model.activeTab?.key == "act", !model.editions.isEmpty, let tab = model.activeTab {
                    editionPicker(model, tab: tab)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.md)
        .accessibilityElement(children: .contain)
    }

    private func editionPicker(_ model: LibraryActViewModel, tab: LibraryActTab) -> some View {
        Picker("Edition", selection: Binding(
            get: { model.currentDoc(for: tab)?.id ?? model.act?.id ?? 0 },
            set: { id in
                if let doc = model.choices(for: tab).first(where: { $0.id == id }) { model.select(doc: doc) }
            }
        )) {
            if let act = model.act {
                Text("Current edition" + (act.fileSize.map { " · \(LibraryDisplay.actSize($0))" } ?? "")).tag(act.id)
            }
            ForEach(Array(model.editions.enumerated()), id: \.element.id) { index, doc in
                Text(LibraryActViewModel.editionLabel(doc, index: index)).tag(doc.id)
            }
        }
        .pickerStyle(.menu)
        .tint(theme.accentText)
        .accessibilityIdentifier("library-act-edition")
    }

    // MARK: - Tabs

    @ViewBuilder
    private func tabBar(_ model: LibraryActViewModel) -> some View {
        let tabs = model.tabs
        if tabs.count > 1 {
            if model.usesSegments {
                RecordSegmentedControl(
                    label: "Parts of this Act",
                    options: tabs.map { (value: $0.key, title: tabTitle($0)) },
                    selection: Binding(
                        get: { model.activeTab?.key ?? "act" },
                        set: { model.select(tab: $0) }))
                    .padding(.horizontal, Spacing.gutter)
                    .accessibilityIdentifier("library-act-tabs")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(tabs) { tab in
                            let isSelected = model.activeTab?.key == tab.key
                            Button {
                                model.select(tab: tab.key)
                            } label: {
                                ChipLabel(title: tab.label, count: tab.key == "act" && tab.count <= 1 ? nil : tab.count,
                                          isSelected: isSelected)
                            }
                            .buttonStyle(ChipButtonStyle(isSelected: isSelected))
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                            .accessibilityIdentifier("library-act-tab-\(tab.key)")
                        }
                    }
                    .padding(.horizontal, Spacing.gutter)
                }
            }
        }
    }

    private func tabTitle(_ tab: LibraryActTab) -> String {
        tab.key == "act" && tab.count <= 1 ? tab.label : "\(tab.label) \(LibraryDisplay.fmtCount(tab.count))"
    }

    // MARK: - Instruments

    @ViewBuilder
    private func instrumentList(_ model: LibraryActViewModel) -> some View {
        if let tab = model.activeTab {
            let latest = model.latestID(in: tab)
            let current = model.currentDoc(for: tab)
            let docs = model.choices(for: tab)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: tab.label, detail: LibraryDisplay.fmtCount(tab.docs.count))
                RecordGroup {
                    ForEach(Array(docs.enumerated()), id: \.element.id) { index, doc in
                        if index > 0 { RecordDivider(inset: 14) }
                        instrumentRow(doc, tab: tab, model: model,
                                      isLatest: doc.id == latest, isCurrent: doc.id == current?.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func instrumentRow(
        _ doc: LibraryDoc, tab: LibraryActTab, model: LibraryActViewModel, isLatest: Bool, isCurrent: Bool
    ) -> some View {
        let label = rowLabel(doc, tab: tab, model: model, isLatest: isLatest)
        if sizeClass == .regular {
            Button {
                model.select(doc: doc)
            } label: {
                label
                    .background(isCurrent ? Color(theme.palette.openRowWash) : Color.clear)
            }
            .buttonStyle(.recordRow)
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
            .accessibilityIdentifier("library-instrument-\(doc.id)")
        } else {
            NavigationLink {
                LibraryInstrumentPane(model: model.file(for: doc), doc: doc, kind: tab.label)
            } label: {
                label
            }
            .buttonStyle(.recordRow)
            .accessibilityIdentifier("library-instrument-\(doc.id)")
        }
    }

    private func rowLabel(_ doc: LibraryDoc, tab: LibraryActTab, model: LibraryActViewModel, isLatest: Bool) -> some View {
        let repealed = LibraryDisplay.isRepealed(doc)
        let facts = model.rowFacts(doc, in: tab)
        return HStack(alignment: .top, spacing: Spacing.md) {
            if tab.key == "amendments" {
                Text(doc.year.map(String.init) ?? "—")
                    .font(.brand(.subheadline, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
                    .frame(minWidth: 44, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(LibraryDisplay.actTitle(doc))
                    .font(.brand(.subheadline, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .dynamicLineLimit(3)
                HStack(spacing: Spacing.xs) {
                    if !facts.isEmpty {
                        Text(facts.joined(separator: " · "))
                            .font(.brand(.caption))
                            .foregroundStyle(theme.textTertiary)
                    }
                    if isLatest { StatusPill(text: "Latest", tone: .success) }
                    if repealed { StatusPill(text: "Repealed", tone: .danger) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RowChevron()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: Layout.listRow)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - The pane (iPad)

    @ViewBuilder
    private func pane(_ model: LibraryActViewModel) -> some View {
        if let doc = model.currentDoc, let tab = model.activeTab {
            LibraryPaneBody(model: model.file(for: doc), doc: doc, kind: tab.label)
                .id(doc.id)
        } else {
            DetailPlaceholder(placeholder: nil)
        }
    }
}

/// One instrument, read: its kind and title over the PDF (`act/ReadingPane.jsx`). Pushed on a
/// phone.
struct LibraryInstrumentPane: View {
    @Environment(\.theme) private var theme

    let model: LibraryFileViewModel
    let doc: LibraryDoc
    let kind: String

    var body: some View {
        LibraryPaneBody(model: model, doc: doc, kind: kind)
            .background(theme.canvas)
            .navigationTitle(LibraryDisplay.actTitle(doc))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("library-room")
    }
}

/// The reading pane's bar and the file under it.
struct LibraryPaneBody: View {
    @Environment(\.theme) private var theme

    let model: LibraryFileViewModel
    let doc: LibraryDoc
    let kind: String

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(kind.uppercased())
                    .recordText(RecordTokens.Typography.label)
                    .foregroundStyle(theme.textTertiary)
                Text(LibraryDisplay.actTitle(doc))
                    .font(.brand(.subheadline, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .dynamicLineLimit(2)
                let facts = [doc.year.map(String.init), LibraryDisplay.truthy(LibraryDisplay.actSize(doc.fileSize))].compactMap { $0 }
                if !facts.isEmpty {
                    Text(facts.joined(separator: " · "))
                        .font(.brand(.caption))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.sm)
            .background(theme.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1) }
            .accessibilityElement(children: .combine)
            LibraryFileView(model: model, docID: doc.id, shareName: LibraryDisplay.actTitle(doc) + ".pdf")
        }
    }
}
