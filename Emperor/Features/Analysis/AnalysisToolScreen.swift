import SwiftUI

/// Devil's Advocate, Doc Index and List of Dates: the analysis tools run over the reader's
/// documents, one screen for the three.
///
/// A stand-in until the screen is built; `isReady` keeps their More cards inert until then.
struct AnalysisToolScreen: View {
    static let isReady = false

    let kind: AnalysisToolKind

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    init(kind: AnalysisToolKind) {
        self.kind = kind
    }

    var body: some View {
        NavigationStack {
            EmptyStateView(
                title, systemImage: systemImage,
                message: "This tool is not available in the app yet.", tone: .neutral)
                .background(theme.groupedBackground)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    private var title: String {
        switch kind {
        case .devilsAdvocate: return "Devil's Advocate"
        case .docIndex: return "Doc Index"
        case .listOfDates: return "List of Dates"
        }
    }

    private var systemImage: String {
        switch kind {
        case .devilsAdvocate: return "shield"
        case .docIndex: return "tablecells"
        case .listOfDates: return "calendar"
        }
    }
}
