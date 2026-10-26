import SwiftUI

/// Teams: the colleagues matters are shared with.
///
/// A stand-in until the screen is built; `isReady` keeps its More row hidden until then.
struct TeamsScreen: View {
    static let isReady = false

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EmptyStateView(
                "Team", systemImage: "person.2",
                message: "Teams are not available in the app yet.", tone: .neutral)
                .background(theme.groupedBackground)
                .navigationTitle("Team")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
