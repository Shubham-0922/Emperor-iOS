import SwiftUI

/// The Devil's Advocate report (`DevilsAdvocate.jsx`, `Report`): a contents bar, the summary and
/// exposure gauge, three charts, the ranked weak spots, the questions to expect, missing papers,
/// authorities against, and a checklist to tick off. Laid out as the web's phone layout — tables
/// become stacked cards.
struct DevilsAdvocateReportView: View {
    let model: AnalysisRunModel
    let outcome: AnalysisOutcome
    let report: DevilsAdvocateReport

    @Environment(\.theme) private var theme
    @State private var open: Set<Int>
    @State private var readiness: DevilsAdvocateReport.Readiness?
    @State private var ticked: Set<String>
    /// A spot to scroll to once its card has opened.
    @State private var pendingSpot: Int?

    init(model: AnalysisRunModel, outcome: AnalysisOutcome, report: DevilsAdvocateReport) {
        self.model = model
        self.outcome = outcome
        self.report = report
        _open = State(initialValue: Set(report.weakSpots.prefix(1).map(\.id)))
        _readiness = State(initialValue: nil)
        _ticked = State(initialValue: Set(report.checklist.filter(\.done).map(\.id)))
        _pendingSpot = State(initialValue: nil)
    }

    private var madeOn: String { AnalysisHistoryFormat.madeOn(outcome.madeOn) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    AnalysisResultHeader(model: model, outcome: outcome)
                    contents(proxy)
                    summary
                        .id("da-top")
                    section(
                        "The picture at a glance", systemImage: "chart.bar", sub: report.chartsLine
                    ) {
                        charts
                    }
                    .id("da-charts")
                    section(
                        "Your weak spots, ranked", systemImage: "scope",
                        sub: "Most serious first. Open one to see why it hurts, where it sits in your papers, what they will say and how to close the gap."
                    ) {
                        weakSpots
                    }
                    .id("da-weak")
                    section(
                        "Questions you should expect", systemImage: "quote.bubble",
                        sub: "What the other side's lawyer is likely to ask, why, and the best answer or document to have in hand."
                    ) {
                        questions
                    }
                    .id("da-questions")
                    section(
                        "Papers you are missing", systemImage: "folder.badge.questionmark",
                        sub: "Documents that would close a weak spot, who holds them and how to get them."
                    ) {
                        gaps
                    }
                    .id("da-docs")
                    section(
                        "Authorities that cut against you", systemImage: "books.vertical",
                        sub: "Decisions the other side is likely to cite, what they say in general terms, and a way to answer each."
                    ) {
                        authorities
                    }
                    .id("da-law")
                    section(
                        "Your preparation checklist", systemImage: "checklist",
                        sub: "Tick items off as you close them. The count at the top keeps score."
                    ) {
                        checklist
                    }
                    .id("da-prep")
                    Button {
                        model.backToIntake()
                    } label: {
                        Label("Run again", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("da-run-again")
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.lg)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: pendingSpot) { _, id in
                guard let id else { return }
                withAnimation(Motion.easeOut(0.3)) { proxy.scrollTo("da-spot-\(id)", anchor: .top) }
                pendingSpot = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("da-report")
    }

    private func goSpot(_ id: Int) {
        open.insert(id)
        pendingSpot = id
    }

    // MARK: - Contents

    private func contents(_ proxy: ScrollViewProxy) -> some View {
        let done = report.checklist.filter { ticked.contains($0.id) }.count
        let items: [(id: String, title: String, anchor: String)] = [
            ("summary", "Summary", "da-top"),
            ("charts", "Charts", "da-charts"),
            ("weak", "Weak spots \(report.weakSpots.count)", "da-weak"),
            ("questions", "Questions \(report.questions.count)", "da-questions"),
            ("docs", "Missing papers \(report.docGaps.count)", "da-docs"),
            ("law", "Authorities \(report.authorities.count)", "da-law"),
            ("prep", "Checklist \(done)/\(report.checklist.count)", "da-prep"),
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(items, id: \.id) { item in
                    Button {
                        withAnimation(Motion.easeOut(0.3)) { proxy.scrollTo(item.anchor, anchor: .top) }
                    } label: {
                        Text(item.title)
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: false))
                    .accessibilityIdentifier("da-contents-\(item.id)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Report contents")
    }

    // MARK: - Summary

    private var summary: some View {
        let counts = report.countBySeverity
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Devil's Advocate report")
                    .recordText(RecordTokens.Typography.label)
                    .foregroundStyle(theme.textTertiary)
                SerifHeader(title: report.matter.title.isEmpty ? "Your matter" : report.matter.title)
                let meta = report.meta(madeOn: madeOn)
                if !meta.isEmpty {
                    VStack(spacing: Spacing.xs) {
                        ForEach(meta, id: \.label) { item in
                            ValueRow(item.label, value: item.value)
                        }
                    }
                }
                RecordDivider(inset: 0)
                Text("Overall exposure")
                    .recordText(RecordTokens.Typography.label)
                    .foregroundStyle(theme.textTertiary)
                Text("\(report.exposureBand) exposure")
                    .font(.display(size: 28, relativeTo: .title))
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityIdentifier("da-exposure")
                Text(report.countsLine)
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textSecondary)
                gauge
                severityStack(counts)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()

            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "info.circle")
                    .foregroundStyle(theme.warning)
                    .accessibilityHidden(true)
                (Text(DevilsAdvocateReport.disclaimerLead).bold() + Text(" ") + Text(DevilsAdvocateReport.disclaimer))
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.warnBg, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .accessibilityElement(children: .combine)

            if !report.oneMinute.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("In one minute")
                        .font(.brand(.headline))
                        .foregroundStyle(theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(report.oneMinute.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                            Text("\(index + 1)")
                                .font(.brand(.subheadline, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(theme.accentText)
                            Text(line)
                                .font(.brand(.body))
                                .foregroundStyle(theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel()
            }
        }
    }

    /// Three bands, Low to High, with a mark at the score.
    private var gauge: some View {
        VStack(spacing: Spacing.xs) {
            GeometryReader { geo in
                let width = geo.size.width
                let mark: CGFloat = min(max(0, width * CGFloat(report.exposureScore) / 100 - 2), max(0, width - 4))
                ZStack(alignment: .leading) {
                    HStack(spacing: 3) {
                        UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 5)
                            .fill(theme.successBg)
                            .overlay(UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 5).stroke(theme.success.opacity(0.35), lineWidth: 1))
                        Rectangle()
                            .fill(theme.warnBg)
                            .overlay(Rectangle().strokeBorder(theme.warning.opacity(0.4), lineWidth: 1))
                        UnevenRoundedRectangle(bottomTrailingRadius: 5, topTrailingRadius: 5)
                            .fill(theme.dangerBg)
                            .overlay(UnevenRoundedRectangle(bottomTrailingRadius: 5, topTrailingRadius: 5).stroke(theme.danger.opacity(0.35), lineWidth: 1))
                    }
                    .frame(height: 10)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.textPrimary)
                        .frame(width: 4, height: 20)
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(theme.surface, lineWidth: 1))
                        .offset(x: mark)
                }
                .frame(height: 20)
            }
            .frame(height: 20)
            HStack {
                Text("Low")
                Spacer()
                Text("Moderate")
                Spacer()
                Text("High")
            }
            .font(.brand(.caption2, weight: .semibold))
            .foregroundStyle(theme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exposure \(report.exposureScore) out of 100, \(report.exposureBand)")
        .accessibilityIdentifier("da-gauge")
    }

    private func place(_ a: DevilsAdvocateReport.Authority) -> String {
        let head: String = [a.court, a.year].filter { !$0.isEmpty }.joined(separator: ", ")
        let parts: [String] = [head, a.pinCite]
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func segment(_ w: CGFloat, _ n: Int, _ total: Int) -> CGFloat {
        let share: CGFloat = (w - 4) * CGFloat(n) / CGFloat(total)
        return max(4, share)
    }

    private func severityStack(_ counts: DevilsAdvocateReport.SeverityCounts) -> some View {
        GeometryReader { geo in
            let total = max(1, report.weakSpots.count)
            HStack(spacing: 2) {
                ForEach(DevilsAdvocateReport.Severity.allCases, id: \.self) { severity in
                    if counts[severity] > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DevilsAdvocateTone.color(severity, theme))
                            .frame(width: segment(geo.size.width, counts[severity], total))
                    }
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    // MARK: - Sections

    private func section<Content: View>(
        _ title: String, systemImage: String, sub: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                IconTile(systemImage: systemImage)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(.display(size: 22, relativeTo: .title2))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(sub)
                        .font(.brand(.footnote))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.brand(.subheadline))
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
    }

    @ViewBuilder
    private var charts: some View {
        if report.weakSpots.isEmpty {
            empty(DevilsAdvocateReport.noSpotsChart)
        } else {
            VStack(spacing: Spacing.md) {
                AdaptiveStack(verticalAlignment: .top, spacing: Spacing.md) {
                    DevilsAdvocateSeverityDonut(report: report)
                    DevilsAdvocateCategoryBars(report: report)
                }
                DevilsAdvocatePushMatrix(report: report) { goSpot($0) }
            }
        }
    }

    // MARK: - Weak spots

    @ViewBuilder
    private var weakSpots: some View {
        if report.weakSpots.isEmpty {
            empty(DevilsAdvocateReport.noSpots)
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if report.weakSpots.count > 1 {
                    HStack {
                        Spacer()
                        if open.count < report.weakSpots.count {
                            Button {
                                open = Set(report.weakSpots.map(\.id))
                            } label: {
                                Label("Expand all", systemImage: "rectangle.expand.vertical")
                            }
                            .buttonStyle(QuietButtonStyle())
                            .accessibilityIdentifier("da-expand-all")
                        } else {
                            Button {
                                open = []
                            } label: {
                                Label("Collapse all", systemImage: "rectangle.compress.vertical")
                            }
                            .buttonStyle(QuietButtonStyle())
                            .accessibilityIdentifier("da-collapse-all")
                        }
                    }
                }
                ForEach(report.weakSpots) { spot in
                    spotCard(spot)
                        .id("da-spot-\(spot.id)")
                }
            }
        }
    }

    private func spotCard(_ spot: DevilsAdvocateReport.WeakSpot) -> some View {
        let isOpen = Binding(
            get: { open.contains(spot.id) },
            set: { if $0 { open.insert(spot.id) } else { open.remove(spot.id) } })
        return DisclosureGroup(isExpanded: isOpen) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if !spot.why.isEmpty {
                    labelled("Why it hurts", systemImage: "exclamationmark.triangle") {
                        Text(spot.why)
                    }
                }
                if !spot.where.isEmpty {
                    labelled("Where in your papers", systemImage: "mappin") {
                        Text(spot.where.joined(separator: " · "))
                    }
                }
                if !spot.say.isEmpty {
                    labelled("What they will say", systemImage: "quote.bubble") {
                        Text("“\(spot.say)”").italic()
                    }
                }
                if !spot.fix.isEmpty {
                    labelled("How to close the gap", systemImage: "lightbulb") {
                        Text(spot.fix)
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.successBg, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                }
            }
            .padding(.top, Spacing.sm)
        } label: {
            HStack(alignment: .top, spacing: Spacing.md) {
                Text("\(spot.id)")
                    .font(.brand(.subheadline, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .frame(minWidth: 32, minHeight: 32)
                    .background(theme.surface2, in: Circle())
                    .overlay(Circle().strokeBorder(DevilsAdvocateTone.color(spot.severity, theme), lineWidth: 2))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.sm) {
                        StatusPill(
                            text: spot.severity.label, tone: DevilsAdvocateTone.pill(spot.severity),
                            systemImage: DevilsAdvocateTone.symbol(spot.severity))
                        Text(DevilsAdvocateReport.categoryLabel(spot.category))
                            .font(.brand(.caption))
                            .foregroundStyle(theme.textSecondary)
                    }
                    Text(spot.title)
                        .font(.brand(.body, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Weak spot \(spot.id), \(spot.severity.label): \(spot.title)")
        }
        .tint(theme.textSecondary)
        .padding(Spacing.md)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: Radius.card, bottomLeadingRadius: Radius.card)
                .fill(DevilsAdvocateTone.color(spot.severity, theme))
                .frame(width: 4)
                .accessibilityHidden(true)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(theme.separator, lineWidth: 1))
        .accessibilityIdentifier("da-spot-\(spot.id)")
    }

    private func labelled<Content: View>(
        _ title: String, systemImage: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(title, systemImage: systemImage)
                .recordText(RecordTokens.Typography.label)
                .foregroundStyle(theme.textTertiary)
            content()
                .font(.brand(.subheadline))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func spotLink(_ id: Int?) -> some View {
        Group {
            if let id {
                Button("#\(id)") { goSpot(id) }
                    .font(.brand(.caption, weight: .bold))
                    .foregroundStyle(theme.accentText)
                    .padding(.horizontal, Spacing.sm)
                    .frame(minWidth: Layout.touchTarget, minHeight: Layout.touchTarget)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .accessibilityLabel("See weak spot \(id)")
            }
        }
    }

    // MARK: - Questions

    @ViewBuilder
    private var questions: some View {
        if report.questions.isEmpty {
            empty(DevilsAdvocateReport.noQuestions)
        } else {
            let counts = report.readinessCounts
            let shown = report.questions(readiness)
            let filterOptions: [(value: DevilsAdvocateReport.Readiness?, title: String)] = [
                (nil, "All \(counts.all)"),
                (.ready, "Ready \(counts.ready)"),
                (.work, "Needs work \(counts.work)"),
                (.gap, "Gap \(counts.gap)"),
            ]
            VStack(alignment: .leading, spacing: Spacing.md) {
                RecordSegmentedControl(
                    label: "Filter questions by readiness",
                    options: filterOptions,
                    selection: $readiness)
                    .accessibilityIdentifier("da-question-filter")
                if shown.isEmpty {
                    empty("No questions in this group.")
                }
                ForEach(Array(shown.enumerated()), id: \.offset) { _, q in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(alignment: .top) {
                            Text("“\(q.q)”")
                                .font(.brand(.body, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: Spacing.sm)
                            StatusPill(text: q.readiness.label, tone: DevilsAdvocateTone.pill(q.readiness))
                        }
                        if !q.why.isEmpty {
                            labelled("Why they ask", systemImage: "questionmark.circle") { Text(q.why) }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                            labelled("Your best answer or paper to have ready", systemImage: "checkmark.seal") { Text(q.answer) }
                            spotLink(q.spot)
                        }
                    }
                    .padding(Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()
                }
                Text("Showing \(shown.count) of \(report.questions.count). The #number links to the matching weak spot.")
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textSecondary)
                    .accessibilityIdentifier("da-question-count")
            }
        }
    }

    // MARK: - Missing papers

    @ViewBuilder
    private var gaps: some View {
        if report.docGaps.isEmpty {
            empty(DevilsAdvocateReport.noGaps)
        } else {
            VStack(spacing: Spacing.sm) {
                ForEach(Array(report.docGaps.enumerated()), id: \.offset) { _, gap in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(gap.doc)
                                .font(.brand(.body, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: Spacing.sm)
                            spotLink(gap.spot)
                        }
                        ValueRow("Who has it", value: gap.who.isEmpty ? "—" : gap.who)
                        ValueRow("How to get it", value: gap.how.isEmpty ? "—" : gap.how)
                        ValueRow("By when", value: gap.when.isEmpty ? "—" : gap.when)
                    }
                    .font(.brand(.subheadline))
                    .padding(Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()
                }
            }
        }
    }

    // MARK: - Authorities

    private var authorities: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if report.authorities.isEmpty {
                empty(DevilsAdvocateReport.noAuthorities)
            }
            ForEach(Array(report.authorities.enumerated()), id: \.offset) { _, a in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        (Text("See e.g. ").foregroundStyle(theme.textSecondary) + Text(a.name).bold().foregroundStyle(theme.textPrimary))
                            .font(.brand(.body))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Spacing.sm)
                        spotLink(a.against)
                    }
                    let placeText: String = place(a)
                    if !placeText.isEmpty {
                        Text(placeText)
                            .font(.brand(.caption))
                            .foregroundStyle(theme.textSecondary)
                    }
                    if a.verify {
                        StatusPill(text: DevilsAdvocateReport.verifyBadge, tone: .warning, systemImage: "exclamationmark.circle")
                    }
                    if !a.holds.isEmpty {
                        labelled("What it generally holds", systemImage: "text.book.closed") { Text(a.holds) }
                    }
                    if !a.distinguish.isEmpty {
                        labelled("How to distinguish it", systemImage: "arrow.triangle.branch") { Text(a.distinguish) }
                    }
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel()
            }
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "info.circle")
                    .foregroundStyle(theme.warning)
                    .accessibilityHidden(true)
                (Text(DevilsAdvocateReport.verifyLead).bold() + Text(" ") + Text(DevilsAdvocateReport.verifyNote))
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.warnBg, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Checklist

    @ViewBuilder
    private var checklist: some View {
        if report.checklist.isEmpty {
            empty(DevilsAdvocateReport.noChecklist)
        } else {
            let done = report.checklist.filter { ticked.contains($0.id) }.count
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    Text("\(done) of \(report.checklist.count) done")
                        .font(.brand(.subheadline, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .accessibilityIdentifier("da-checklist-count")
                    ProgressView(value: Double(done), total: Double(report.checklist.count))
                        .tint(theme.success)
                        .accessibilityLabel("Preparation progress")
                }
                RecordGroup {
                    ForEach(Array(report.checklist.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { RecordDivider(inset: 14) }
                        Toggle(isOn: Binding(
                            get: { ticked.contains(item.id) },
                            set: { if $0 { ticked.insert(item.id) } else { ticked.remove(item.id) } })
                        ) {
                            Text(item.text)
                                .font(.brand(.subheadline))
                                .foregroundStyle(ticked.contains(item.id) ? theme.textSecondary : theme.textPrimary)
                                .strikethrough(ticked.contains(item.id))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .tint(theme.success)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .accessibilityIdentifier("da-check-\(item.id)")
                    }
                }
            }
        }
    }
}
