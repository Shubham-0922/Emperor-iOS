import SafariServices
import SwiftUI
import UIKit

/// A case read from its court, laid out for someone who has never opened a court website — the
/// web's `Dossier.jsx`: the header with the one action that matters (Add to Matters, or Open in
/// Matters), four facts at a glance, the orders, the hearings, any applications, the parties, the
/// case as a timeline, connected matters and fees, and the offer again at the foot.
///
/// Nothing here is saved: it is a read-only view of the court's record.
struct LookupDossierView: View {
    @Environment(\.theme) private var theme
    @Environment(\.navigator) private var navigator
    @Environment(\.horizontalSizeClass) private var sizeClass

    let model: FetchOrdersViewModel
    let record: LookupRecord
    /// The matter has been opened in Matters; the host closes itself.
    let onMatterOpened: () -> Void

    @State private var toast: String?
    @State private var showsAdd = false
    @State private var matterOpened = false
    @State private var reading: ReadableOrder?
    @State private var showsAllHearings = false

    private static let hearingsShown = 8

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                glance
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: Spacing.lg) {
                        VStack(alignment: .leading, spacing: Spacing.lg) { mainColumn }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        VStack(alignment: .leading, spacing: Spacing.lg) { sideColumn }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                } else {
                    mainColumn
                    sideColumn
                }
                closing
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.groupedBackground)
        .recordToast($toast)
        .sheet(isPresented: $showsAdd, onDismiss: {
            if matterOpened { onMatterOpened() }
        }) {
            addSheet
        }
        .sheet(item: $reading) { order in
            OrderSafariView(url: order.url)
                .ignoresSafeArea()
        }
    }

    // MARK: - Computed facts

    private var kase: LookupRecord.Case { record.case }
    private var today: String { model.todayKey }
    private var disposed: Bool { LookupModel.isDisposed(kase.status) }

    @ViewBuilder
    private var addSheet: some View {
        if let request = model.addRequest() {
            AddToMattersSheet(request: request) { made in
                model.added(made)
                matterOpened = true
                VoiceOver.announce(made.toast)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            headerChips
            Text(LookupModel.titleOf(kase))
                .font(.display(size: 26, relativeTo: .title))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("fetch-dossier-title")
            ctaButton
            AdaptiveStack(horizontalAlignment: .leading, spacing: Spacing.sm) {
                Button {
                    copySummary()
                } label: {
                    Label(FetchOrdersViewModel.Copy.copySummary, systemImage: "doc.on.doc")
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("fetch-copy-summary")
                Button {
                    model.reset()
                } label: {
                    Label(FetchOrdersViewModel.Copy.another, systemImage: "magnifyingglass")
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("fetch-another")
            }
            Label(LookupModel.readFootnote(cached: model.cached), systemImage: "checkmark.shield")
                .font(.brand(.caption))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(tinted: true)
    }

    private var headerChips: some View {
        let courtName: String = (kase.courtName?.isEmpty == false) ? kase.courtName! : "Court"
        let number: String = LookupModel.caseNumberOf(kase)
        let statusText: String = LookupModel.statusWord(kase.status) ?? "Status not given"
        let statusTone: StatusPill.Tone = disposed ? .neutral : .success
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            AdaptiveStack(horizontalAlignment: .leading, spacing: Spacing.sm) {
                StatusPill(text: courtName, tone: .neutral, systemImage: "building.columns")
                if !number.isEmpty {
                    StatusPill(text: number, tone: .neutral, systemImage: "hammer")
                }
            }
            AdaptiveStack(horizontalAlignment: .leading, spacing: Spacing.sm) {
                identityChip
                StatusPill(text: statusText, tone: statusTone)
            }
        }
    }

    @ViewBuilder
    private var identityChip: some View {
        let identity: String = (kase.cnr?.isEmpty == false) ? kase.cnr! : (kase.diaryNumber ?? "")
        if !identity.isEmpty {
            let label: String = MatterRecord.cnrLabel(identity)
            Button {
                UIPasteboard.general.string = identity
                toast = "\(label) copied"
            } label: {
                StatusPill(text: "\(label) \(identity)", tone: .accent, systemImage: "doc.on.doc")
                    .frame(minHeight: Layout.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Copy \(label) \(identity)"))
            .accessibilityIdentifier("fetch-copy-identity")
        }
    }

    private var ctaButton: some View {
        let title: String = model.ctaTitle
        let symbol: String = model.matterID == nil ? "folder.badge.plus" : "folder"
        return Button {
            act()
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityIdentifier("fetch-cta")
    }

    private func act() {
        if let id = model.matterID {
            navigator.openMatter(id)
            onMatterOpened()
        } else {
            showsAdd = true
        }
    }

    private func copySummary() {
        UIPasteboard.general.string = LookupModel.summaryText(record, today: today)
        toast = FetchOrdersViewModel.Copy.copied
    }

    // MARK: - At a glance

    private var glance: some View {
        let columns: [GridItem] = [
            GridItem(.flexible(), spacing: Spacing.md, alignment: .top),
            GridItem(.flexible(), spacing: Spacing.md, alignment: .top),
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.md) {
            nextTile
            standsTile
            lastOrderTile
            holdsTile
        }
    }

    private var nextTile: some View {
        let next: String? = LookupModel.upcoming(kase, today: today)
        if let next {
            let days: Int = MatterRecord.daysFromToday(next, today: today) ?? 0
            let due: String = LookupModel.dueWords(days)
            let weekday: String = MatterRecord.weekdayOf(next)
            var lines: [String] = ["\(due) · \(weekday)"]
            if let hearing = record.hearings.first(where: { $0.date == next }) {
                let room: String = LookupModel.roomOf(hearing.courtNo)
                let purpose: String = MatterRecord.plainCourtText(hearing.purpose)
                let place: String = [room, purpose].filter { !$0.isEmpty }.joined(separator: " · ")
                if !place.isEmpty { lines.append(place) }
            }
            let tone: Color = days <= 1 ? theme.danger : (days <= 7 ? theme.warning : theme.accentText)
            return GlanceTile(
                label: "Next hearing", symbol: "calendar.badge.clock",
                value: MatterRecord.fmtDay(next), valueColor: tone, lines: lines)
        }
        let value: String = disposed ? "Decided" : "No date yet"
        let line: String = disposed
            ? "The case is over, so no further hearing is listed."
            : "The court has not listed the next hearing yet."
        return GlanceTile(
            label: "Next hearing", symbol: "calendar.badge.clock",
            value: value, valueColor: theme.textSecondary, lines: [line])
    }

    private var standsTile: some View {
        var lines: [String] = []
        let stage: String = MatterRecord.plainCourtText(kase.stage)
        if !stage.isEmpty { lines.append("Stage: \(stage)") }
        let bench: String = MatterRecord.plainCourtText(kase.bench)
        if !bench.isEmpty { lines.append("Before: \(bench)") }
        let firstListed: String? = record.hearings.last?.date
        let filed: String? = (kase.filingDate?.isEmpty == false) ? kase.filingDate : nil
        if let since = filed ?? firstListed {
            let word: String = filed == nil ? "First listed" : "Filed"
            let ago: String = LookupModel.ago(since, today: today)
            lines.append("\(word) \(MatterRecord.fmtDay(since)) · \(ago)")
        }
        let value: String = LookupModel.statusWord(kase.status) ?? "—"
        let tone: Color = disposed ? theme.textSecondary : theme.success
        return GlanceTile(
            label: "Where it stands", symbol: "scalemass", value: value, valueColor: tone, lines: lines)
    }

    private var lastOrderTile: some View {
        guard let order = record.orders.first else {
            return GlanceTile(
                label: "Latest order", symbol: "scroll", value: "None yet", valueColor: theme.textSecondary,
                lines: ["The court has not put up any order for this case."])
        }
        let raw: String = MatterRecord.orderTitle(order.title)
        let title: String = raw.isEmpty ? "Order" : raw
        let ago: String = LookupModel.ago(order.date, today: today)
        let line: String = "\(title) · \(ago)"
        let total: String = "\(record.orders.count) in all"
        return GlanceTile(
            label: "Latest order", symbol: "scroll", value: MatterRecord.fmtDay(order.date),
            valueColor: theme.textPrimary, lines: [line, total])
    }

    private var holdsTile: some View {
        let parties: Int = record.parties.petitioners.count + record.parties.respondents.count
        let lines: [String] = [
            "\(record.orders.count) orders & judgments",
            "\(record.hearings.count) hearings",
            "\(record.applications.count) applications",
            "\(parties) parties",
        ]
        return GlanceTile(
            label: "On the record", symbol: "checklist", value: nil, valueColor: theme.textPrimary, lines: lines)
    }

    // MARK: - Columns

    @ViewBuilder
    private var mainColumn: some View {
        ordersSection
        hearingsSection
        if !record.applications.isEmpty {
            applicationsSection
        }
    }

    @ViewBuilder
    private var sideColumn: some View {
        partiesSection
        timelineSection
        if !record.connected.isEmpty || !record.courtFees.isEmpty {
            extrasSection
        }
    }

    // MARK: - Orders

    private var ordersSection: some View {
        let count: String = "\(record.orders.count)"
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Orders & judgments", detail: count)
            if model.orderYears.count > 1 {
                yearChips
            }
            if record.orders.isEmpty {
                quietLine("The court has not published any order for this case yet. Add it to Matters and we will tell you the moment one appears.")
            } else {
                RecordGroup {
                    ForEach(Array(model.visibleOrders.enumerated()), id: \.offset) { pair in
                        if pair.offset > 0 { RecordDivider(inset: 14) }
                        orderRow(pair.element, index: pair.offset)
                    }
                }
            }
            if let toggle = model.ordersToggleTitle {
                Button(toggle) { model.showsAllOrders.toggle() }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("fetch-orders-toggle")
            }
        }
    }

    private var yearChips: some View {
        let years: [String] = [""] + model.orderYears
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(years, id: \.self) { year in
                    yearChip(year)
                }
            }
        }
    }

    private func yearChip(_ year: String) -> some View {
        let selected: Bool = model.orderYear == year
        let title: String = year.isEmpty ? "All" : year
        return Button {
            model.orderYear = year
        } label: {
            ChipLabel(title: title, isSelected: selected)
        }
        .buttonStyle(ChipButtonStyle(isSelected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("fetch-year-\(title)")
    }

    private func orderRow(_ order: LookupRecord.Order, index: Int) -> some View {
        let title: String = MatterRecord.orderTitle(order.title)
        let day: String = MatterRecord.fmtDay(order.date)
        let ago: String = LookupModel.ago(order.date, today: today)
        let when: String = day.isEmpty ? "" : "\(day) · \(ago)"
        let latest: Bool = index == 0 && model.orderYear.isEmpty
        return HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                AdaptiveStack(horizontalAlignment: .leading, spacing: Spacing.sm) {
                    Text(title.isEmpty ? "Order" : title)
                        .font(.brand(.body, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if latest {
                        StatusPill(text: "Latest", tone: .accent)
                    }
                }
                if !when.isEmpty {
                    Text(when)
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            orderAction(order, day: day)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fetch-order-\(index)")
    }

    @ViewBuilder
    private func orderAction(_ order: LookupRecord.Order, day: String) -> some View {
        if let url = order.webURL {
            Button {
                reading = ReadableOrder(url: url)
            } label: {
                Label("Read", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(SecondaryButtonStyle(compact: true))
            .accessibilityLabel(Text(day.isEmpty ? "Read the order" : "Read the order of \(day)"))
        } else {
            Text("No copy online")
                .font(.brand(.caption))
                .foregroundStyle(theme.textTertiary)
        }
    }

    // MARK: - Hearings

    private var hearingsSection: some View {
        let all: [LookupRecord.Hearing] = record.hearings
        let rows: [LookupRecord.Hearing] = showsAllHearings ? all : Array(all.prefix(Self.hearingsShown))
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Hearing history", detail: "\(all.count)")
            if all.isEmpty {
                quietLine("No hearings are listed for this case.")
            } else {
                RecordGroup {
                    ForEach(Array(rows.enumerated()), id: \.offset) { pair in
                        if pair.offset > 0 { RecordDivider(inset: 14) }
                        hearingRow(pair.element)
                    }
                }
            }
            if all.count > Self.hearingsShown {
                let toggle: String = showsAllHearings ? "Show fewer" : "Show all \(all.count)"
                Button(toggle) { showsAllHearings.toggle() }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private func hearingRow(_ h: LookupRecord.Hearing) -> some View {
        let day: String = MatterRecord.fmtDay(h.date)
        let future: Bool = (h.date ?? "") > today
        let purposeText: String = MatterRecord.plainCourtText(h.purpose)
        let stageText: String = MatterRecord.plainCourtText(h.stage)
        let purpose: String = purposeText.isEmpty ? "Listed before the court" : purposeText
        let what: String = stageText.isEmpty ? purpose : "\(purpose) · \(stageText)"
        let room: String = roomLine(h)
        return VStack(alignment: .leading, spacing: Spacing.xxs) {
            AdaptiveStack(horizontalAlignment: .leading, spacing: Spacing.sm) {
                Text(day)
                    .font(.brand(.subheadline, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                if future {
                    StatusPill(text: "Upcoming", tone: .accent)
                }
            }
            Text(what)
                .font(.brand(.footnote))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(room)
                .font(.brand(.caption))
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    /// "Court 51 · Item 12", else the bench, else a dash.
    private func roomLine(_ h: LookupRecord.Hearing) -> String {
        var parts: [String] = []
        let room: String = LookupModel.roomOf(h.courtNo)
        if !room.isEmpty { parts.append(room) }
        if let item = h.itemNo, !item.isEmpty { parts.append("Item \(item)") }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        let bench: String = MatterRecord.plainCourtText(h.bench)
        return bench.isEmpty ? "—" : bench
    }

    // MARK: - Applications

    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Applications", detail: "\(record.applications.count)")
            RecordGroup {
                ForEach(Array(record.applications.enumerated()), id: \.offset) { pair in
                    if pair.offset > 0 { RecordDivider(inset: 14) }
                    applicationRow(pair.element)
                }
            }
        }
    }

    private func applicationRow(_ a: LookupRecord.Application) -> some View {
        let particular: String = MatterRecord.plainCourtText(a.particular)
        let filed: String = (a.filedOn?.isEmpty == false) ? MatterRecord.fmtDay(a.filedOn) : "—"
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(particular.isEmpty ? "Application" : particular)
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(filed)
                    .font(.brand(.caption))
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let status = a.status, !status.isEmpty {
                StatusPill(text: status)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Parties

    private var partiesSection: some View {
        let sides = LookupModel.sidesOf(record.parties)
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Parties & advocates")
            partySide(title: "Petitioner / plaintiff side", side: sides.first)
            partySide(title: "Respondent / defendant side", side: sides.second)
        }
    }

    private func partySide(title: String, side: LookupModel.Side) -> some View {
        let shown: [String] = Array(side.names.prefix(6))
        let more: Int = side.names.count - shown.count
        let counselWord: String = side.counsel.count > 1 ? "Advocates" : "Advocate"
        return RecordGroup {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .recordText(RecordTokens.Typography.label)
                    .foregroundStyle(theme.textTertiary)
                    .accessibilityAddTraits(.isHeader)
                if shown.isEmpty {
                    Text("Not listed")
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textTertiary)
                }
                ForEach(Array(shown.enumerated()), id: \.offset) { pair in
                    Label(pair.element, systemImage: "person")
                        .font(.brand(.subheadline, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                }
                if more > 0 {
                    Text("and \(more) more")
                        .font(.brand(.caption))
                        .foregroundStyle(theme.textTertiary)
                }
                if !side.counsel.isEmpty {
                    Text("\(counselWord): \(side.counsel.joined(separator: ", "))")
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        let rows: [LookupModel.TimelineRow] = LookupModel.timelineOf(record, today: today)
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Timeline")
            if rows.isEmpty {
                quietLine("Nothing on the record yet.")
            } else {
                RecordGroup {
                    ForEach(Array(rows.enumerated()), id: \.offset) { pair in
                        if pair.offset > 0 { RecordDivider(inset: 14) }
                        timelineRow(pair.element, newYear: Self.startsYear(rows, at: pair.offset))
                    }
                }
            }
        }
    }

    /// Whether the row at `index` is the first of its year, so the year is marked above it.
    private static func startsYear(_ rows: [LookupModel.TimelineRow], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let year: String = String(rows[index].day.prefix(4))
        let before: String = String(rows[index - 1].day.prefix(4))
        return year != before
    }

    private func timelineRow(_ row: LookupModel.TimelineRow, newYear: Bool) -> some View {
        let year: String = String(row.day.prefix(4))
        let kindWord: String = Self.kindWord(row.kind)
        let symbol: String = Self.kindSymbol(row.kind)
        let dayColor: Color = row.kind == .next ? theme.accentText : theme.textPrimary
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            if newYear {
                StatusPill(text: year)
            }
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: symbol)
                    .foregroundStyle(theme.accentText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("\(MatterRecord.fmtDay(row.day)) · \(kindWord)")
                        .font(.brand(.caption, weight: .semibold))
                        .foregroundStyle(dayColor)
                    Text(row.title)
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !row.sub.isEmpty {
                        Text(row.sub)
                            .font(.brand(.caption))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private static func kindWord(_ kind: LookupModel.TimelineRow.Kind) -> String {
        switch kind {
        case .next: return "Upcoming"
        case .order: return "Order"
        case .hearing: return "Hearing"
        }
    }

    private static func kindSymbol(_ kind: LookupModel.TimelineRow.Kind) -> String {
        switch kind {
        case .next: return "calendar.badge.clock"
        case .order: return "scroll"
        case .hearing: return "building.columns"
        }
    }

    // MARK: - Also on the record

    private var extrasSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Also on the record")
            RecordGroup {
                ForEach(Array(record.connected.enumerated()), id: \.offset) { pair in
                    if pair.offset > 0 { RecordDivider(inset: 14) }
                    Text(LookupModel.connectedText(pair.element))
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                ForEach(Array(record.courtFees.enumerated()), id: \.offset) { pair in
                    if pair.offset > 0 || !record.connected.isEmpty { RecordDivider(inset: 14) }
                    feeRow(pair.element)
                }
            }
        }
    }

    private func feeRow(_ fee: LookupRecord.CourtFee) -> some View {
        let head: String = (fee.head?.isEmpty == false) ? fee.head! : "Court fee"
        return ValueRow(head, value: LookupModel.feeText(fee.amount))
            .font(.brand(.footnote))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }

    // MARK: - Closing offer

    private var closing: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(model.closingTitle)
                .font(.display(size: 22, relativeTo: .title2))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ForEach(FetchOrdersViewModel.Copy.keepPoints, id: \.self) { point in
                Label(point, systemImage: "checkmark.circle")
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                act()
            } label: {
                Text(model.ctaTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("fetch-cta-closing")
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func quietLine(_ text: String) -> some View {
        Text(text)
            .font(.brand(.footnote))
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
    }
}

/// One of the four facts at the head of the dossier: what it is, the figure, a line or two under.
private struct GlanceTile: View {
    @Environment(\.theme) private var theme

    let label: String
    let symbol: String
    let value: String?
    let valueColor: Color
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(label, systemImage: symbol)
                .recordText(RecordTokens.Typography.label)
                .foregroundStyle(theme.textTertiary)
            if let value {
                Text(value)
                    .font(.display(size: 22, relativeTo: .title2))
                    .foregroundStyle(valueColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .panel()
        .accessibilityElement(children: .combine)
    }
}

/// An order's copy to open in Safari's reader, inside the app.
private struct ReadableOrder: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// `SFSafariViewController` for an order's copy: the court's own PDF, read without leaving the
/// case.
private struct OrderSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
