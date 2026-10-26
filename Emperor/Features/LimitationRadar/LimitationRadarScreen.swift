import SwiftUI

/// Limitation Landmine Radar: whether a suit's limitation period has shut, and by how much.
///
/// The audit is the platform's (`POST /limitation-radar`); this draws the form and the answer, in
/// the words the web page uses. Every sentence and rule lives in `LimitationRadarViewModel`.
struct LimitationRadarScreen: View {
    static let isReady = true

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(Session.self) private var session

    @State private var model: LimitationRadarViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(theme.groupedBackground)
            .navigationTitle("Limitation Radar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                guard model == nil else { return }
                model = LimitationRadarViewModel(service: session.limitationRadar)
            }
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private func content(_ model: LimitationRadarViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    SerifHeader(
                        title: "Limitation Landmine Radar",
                        subtitle: LimitationRadarViewModel.subtitle)
                    if sizeClass == .regular {
                        HStack(alignment: .top, spacing: Spacing.xl) {
                            form(model)
                                .frame(maxWidth: 380)
                            results(model)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        form(model)
                        results(model)
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.result) {
                guard model.result != nil, sizeClass != .regular else { return }
                withAnimation { proxy.scrollTo("radar-banner-anchor", anchor: .top) }
            }
        }
    }

    // MARK: - Form

    @ViewBuilder
    private func form(_ model: LimitationRadarViewModel) -> some View {
        @Bindable var bindable = model

        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Dispute timeline")
                .font(.brand(.headline))
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            RecordGroup {
                profileRow(model)
                RecordDivider(inset: 14)
                dateRow(
                    title: "Date time began to run", required: true,
                    hint: model.causeHint, id: "radar-cause", date: $bindable.causeOfAction,
                    disabled: model.isRunning)
                RecordDivider(inset: 14)
                dateRow(
                    title: "Date of filing the suit", required: true,
                    hint: LimitationRadarViewModel.filingHint, id: "radar-filing",
                    date: $bindable.intendedFiling, disabled: model.isRunning)
            }

            Text("Pre-institution mediation (optional)")
                .font(.brand(.headline))
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Spacing.sm)
            Text(LimitationRadarViewModel.mediationExplanation)
                .font(.brand(.caption))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            RecordGroup {
                dateRow(
                    title: "Mediation application made", required: false, hint: nil,
                    id: "radar-med-start", date: $bindable.mediationStart,
                    disabled: model.isRunning)
                RecordDivider(inset: 14)
                dateRow(
                    title: "Mediation concluded", required: false,
                    hint: LimitationRadarViewModel.mediationEndHint, id: "radar-med-end",
                    date: $bindable.mediationEnd, disabled: model.isRunning)
            }

            Button {
                Task { await model.run() }
            } label: {
                HStack(spacing: Spacing.sm) {
                    if model.isRunning { ProgressView().tint(theme.onAccent) }
                    Text(model.isRunning ? "Running limitation audit…" : "Run Limitation Audit")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isRunning)
            .accessibilityIdentifier("radar-run")

            if let message = model.errorMessage {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .accessibilityHidden(true)
                    Text(message)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.brand(.footnote))
                .foregroundStyle(theme.danger)
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    theme.dangerBg,
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("radar-error")
            }
        }
    }

    private func profileRow(_ model: LimitationRadarViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            fieldTitle("Nature of the suit", required: true)
            Menu {
                Picker(
                    "Nature of the suit",
                    selection: Binding(
                        get: { model.profileKey },
                        set: { model.selectProfile($0) })
                ) {
                    ForEach(LimitationProfile.all) { profile in
                        Text(profile.pickerLabel).tag(profile.key)
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(model.profile.pickerLabel)
                        .font(.brand(.body))
                        .foregroundStyle(theme.accentText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                        .foregroundStyle(theme.textTertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .disabled(model.isRunning)
            .accessibilityLabel("Nature of the suit")
            .accessibilityValue(model.profile.pickerLabel)
            .accessibilityIdentifier("radar-profile")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fieldTitle(_ title: String, required: Bool) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(title)
                .font(.brand(.subheadline, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            if required {
                // Said in words, not only in colour.
                Text("Required")
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func dateRow(
        title: String, required: Bool, hint: String?, id: String,
        date: Binding<Date?>, disabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            fieldTitle(title, required: required)
            HStack(spacing: Spacing.sm) {
                if date.wrappedValue == nil {
                    Button("Add date") { date.wrappedValue = Date() }
                        .font(.brand(.body, weight: .medium))
                        .foregroundStyle(theme.accentText)
                        .disabled(disabled)
                        .accessibilityLabel("Add \(title)")
                        .accessibilityIdentifier(id)
                } else {
                    DatePicker(
                        title,
                        selection: Binding(
                            get: { date.wrappedValue ?? Date() },
                            set: { date.wrappedValue = $0 }),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    // The day the person picked is the day that is sent: `WireDate.dayKey` reads
                    // it in India, so the picker is drawn there too.
                    .environment(\.timeZone, WireDate.india)
                    .disabled(disabled)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier(id)
                    Button {
                        date.wrappedValue = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.textTertiary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(disabled)
                    .accessibilityLabel("Clear \(title)")
                    .accessibilityIdentifier("\(id)-clear")
                }
                Spacer(minLength: 0)
            }
            if let hint {
                Text(hint)
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Results

    @ViewBuilder
    private func results(_ model: LimitationRadarViewModel) -> some View {
        if let result = model.result {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                banner(model, result)
                    .id("radar-banner-anchor")
                framework(model, result)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Audit findings")
                        .font(.brand(.headline))
                        .foregroundStyle(theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(result.fatalFlaw)
                        .font(.brand(.body))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("radar-findings")
                }
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Next steps")
                        .font(.brand(.headline))
                        .foregroundStyle(theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(model.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                            Text("\(index + 1)")
                                .font(.brand(.subheadline, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(theme.accentText)
                            Text(step)
                                .font(.brand(.subheadline))
                                .foregroundStyle(theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            theme.surface,
                            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("radar-step-\(index + 1)")
                    }
                }
                Text(LimitationRadarViewModel.disclaimer)
                    .font(.brand(.caption))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if model.isRunning {
            VStack(spacing: Spacing.md) {
                ProgressView()
                Text("Computing the limitation period")
                    .font(.brand(.headline))
                    .foregroundStyle(theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xxxl)
            .accessibilityElement(children: .combine)
        } else {
            EmptyStateContent(
                title: "No audit has been run yet",
                systemImage: "calendar.badge.clock",
                message: LimitationRadarViewModel.emptyMessage, tone: .neutral
            ) { EmptyView() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("radar-empty")
        }
    }

    private func tone(_ outcome: LimitationOutcome) -> StatusPill.Tone {
        switch outcome {
        case .safe: return .success
        case .mediation: return .warning
        case .barred: return .danger
        }
    }

    private func wash(_ outcome: LimitationOutcome) -> Color {
        switch outcome {
        case .safe: return theme.successBg
        case .mediation: return theme.warnBg
        case .barred: return theme.dangerBg
        }
    }

    private func banner(_ model: LimitationRadarViewModel, _ result: LimitationAudit) -> some View {
        let outcome = model.bannerTone
        let symbol: String
        switch outcome {
        case .safe: symbol = "checkmark.shield"
        case .mediation: symbol = "questionmark.diamond"
        case .barred: symbol = "exclamationmark.shield"
        }
        return AdaptiveStack(horizontalAlignment: .leading, spacing: Spacing.md) {
            Image(systemName: symbol)
                .font(.brand(.title2))
                .foregroundStyle(theme.textPrimary)
                .accessibilityHidden(true)
            StatusPill(text: result.status, tone: tone(outcome))
            if let headline = model.headline {
                Text(headline)
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            wash(outcome), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("radar-banner")
    }

    private func framework(_ model: LimitationRadarViewModel, _ result: LimitationAudit) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Statutory framework")
                .font(.brand(.headline))
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(result.statuteApplied)
                .font(.brand(.body))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Time runs from: \(result.periodRunsFrom)")
                .font(.brand(.caption))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            RecordGroup {
                VStack(spacing: 0) {
                    ValueRow("Last day to file", value: model.lastDayText ?? "")
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    if let mediation = model.mediationText {
                        RecordDivider(inset: 14)
                        ValueRow("Mediation excluded", value: mediation)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    if let adjusted = model.adjustedText {
                        RecordDivider(inset: 14)
                        ValueRow("With the exclusion", value: adjusted)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                }
            }
            .accessibilityIdentifier("radar-framework")
        }
    }
}
