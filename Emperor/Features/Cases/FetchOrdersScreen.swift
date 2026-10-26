import SwiftUI

/// Fetch Orders: a case's orders read from the court's own portal.
///
/// A stand-in until the screen is built; `isReady` keeps its More card inert until then.
struct FetchOrdersScreen: View {
    static let isReady = false

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EmptyStateView(
                "Fetch Orders", systemImage: "doc.text.magnifyingglass",
                message: "This tool is not available in the app yet.", tone: .neutral)
                .background(theme.groupedBackground)
                .navigationTitle("Fetch Orders")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
