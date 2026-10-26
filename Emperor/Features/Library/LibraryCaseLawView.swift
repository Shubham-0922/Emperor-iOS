import SwiftUI

/// One judgment in the Case Law list, set like an entry in a law report's index: the court, the
/// case name, the date (or "Date unclear" for one the source dates after today), the neutral
/// citation and number, the bench, and the passage when searching inside judgments
/// (`caselaw/CaseRow.jsx`).
struct LibraryCaseRow: View {
    @Environment(\.theme) private var theme

    let doc: LibraryDoc
    var dateUnclear = false
    var showsPassage = false

    var body: some View {
        NavigationLink(value: LibraryRoute.open(doc)) {
            HStack(alignment: .top, spacing: Spacing.md) {
                seal
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(LibraryDisplay.caseTitleText(doc))
                        .font(.serif(.body, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .dynamicLineLimit(3)
                    AdaptiveStack(verticalAlignment: .center, spacing: Spacing.xs) {
                        StatusPill(text: court.short, tone: .neutral)
                        if dateUnclear {
                            StatusPill(text: "Date unclear", tone: .warning)
                        } else if let when {
                            Text(when)
                                .font(.brand(.caption, weight: .medium))
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                    if !facts.isEmpty {
                        Text(facts.joined(separator: " · "))
                            .font(.brand(.caption))
                            .foregroundStyle(theme.textTertiary)
                            .dynamicLineLimit(2)
                    }
                    if let bench = LibraryDisplay.truthy(doc.bench) {
                        Text("Bench: \(bench)")
                            .font(.brand(.caption))
                            .foregroundStyle(theme.textTertiary)
                            .dynamicLineLimit(2)
                    }
                    if showsPassage {
                        LibrarySnippetText(snippet: doc.snippet ?? LibrarySnippet())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RowChevron()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.recordRow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("library-doc-\(doc.id)")
    }

    private var court: LibraryDisplay.Court { LibraryDisplay.courtInfo(doc.court, label: doc.courtLabel) }

    private var when: String? {
        if let day = LibraryDisplay.truthy(doc.decidedOn) { return LibraryDisplay.fmtDay(day) }
        return doc.year.flatMap { $0 == 0 ? nil : String($0) }
    }

    private var facts: [String] {
        [LibraryDisplay.truthy(doc.neutralCitation), LibraryDisplay.truthy(LibraryDisplay.caseNumberText(doc))].compactMap { $0 }
    }

    /// The court's monogram in its own colour — decorative; the pill names the court.
    private var seal: some View {
        let ink = Color(LibraryDisplay.color(theme.isDark ? court.inkDark : court.ink))
        return Text(court.mono)
            .font(.brand(size: 12, weight: .bold, relativeTo: .caption2))
            .foregroundStyle(ink)
            .frame(width: 36, height: 36)
            .overlay(Circle().strokeBorder(ink, lineWidth: 1.5))
            .dynamicTypeSize(.large)
            .accessibilityHidden(true)
    }

    private var accessibilityText: String {
        var parts = [LibraryDisplay.caseTitleText(doc), court.name]
        if dateUnclear { parts.append("Date unclear") } else if let when { parts.append(when) }
        parts += facts
        if showsPassage, let text = doc.snippet?.text { parts.append(text) }
        return parts.joined(separator: ". ")
    }
}

/// The courts as chips with their counts, "All courts" first (`caselaw/CourtRail.jsx`).
struct LibraryCourtChips: View {
    let courts: [LibraryFacetOption]
    let selected: String?
    let onSelect: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                chip(title: "All courts", value: nil, count: nil)
                ForEach(courts, id: \.value) { court in
                    chip(title: LibraryDisplay.courtInfo(court.value, label: court.label).short,
                         value: court.value, count: court.count)
                }
            }
            .padding(.horizontal, Spacing.gutter)
        }
    }

    private func chip(title: String, value: String?, count: Int?) -> some View {
        let isSelected = selected == value
        return Button {
            onSelect(value)
        } label: {
            ChipLabel(title: title, count: count, isSelected: isSelected)
        }
        .buttonStyle(ChipButtonStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("library-court-\(value ?? "all")")
    }
}
