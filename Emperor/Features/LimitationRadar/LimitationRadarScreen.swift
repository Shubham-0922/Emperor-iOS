import SwiftUI

/// Limitation Radar: limitation periods and the risk a delay needs condoning.
///
/// A stand-in until the screen is built; `isReady` keeps its More card inert until then.
struct LimitationRadarScreen: View {
    static let isReady = false

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EmptyStateView(
                "Limitation Radar", systemImage: "exclamationmark.triangle",
                message: "This tool is not available in the app yet.", tone: .neutral)
                .background(theme.groupedBackground)
                .navigationTitle("Limitation Radar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
