import SwiftUI

/// Filing Assembly: the index, annexures and paper-book for an e-filing.
///
/// A stand-in until the screen is built; `isReady` keeps its More card inert until then.
struct FilingAssemblyScreen: View {
    static let isReady = false

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EmptyStateView(
                "Filing Assembly", systemImage: "books.vertical.fill",
                message: "This tool is not available in the app yet.", tone: .neutral)
                .background(theme.groupedBackground)
                .navigationTitle("Filing Assembly")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
