import SwiftUI

/// The draft's earlier bundles, newest first — so a bundle assembled while the phone was away,
/// or before a sheet was closed, can still be opened.
struct FilingBundlesSection: View {
    @Environment(\.theme) private var theme

    let model: FilingAssemblyViewModel
    let onOpen: (FilingBundle) -> Void

    var body: some View {
        Section {
            if model.bundles.isEmpty {
                Text("No bundles assembled for this draft yet.")
                    .font(.brand(.subheadline))
                    .foregroundStyle(theme.textSecondary)
            }
            ForEach(model.bundles) { bundle in
                Button {
                    onOpen(bundle)
                } label: {
                    RecordRow(
                        title: bundle.title,
                        subtitle: bundle.createdDate.map(FileBrowser.shortDate),
                        leading: { IconTile(systemImage: "books.vertical") },
                        trailing: {
                            StatusPill(
                                text: bundle.isReady ? "Ready" : "Failed",
                                tone: bundle.isReady ? .success : .danger)
                        })
                }
                .buttonStyle(.recordRow)
                .disabled(!bundle.isReady)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("filing-bundle-\(bundle.id)")
            }
        } header: {
            SectionHeader(title: "Previous bundles", detail: model.bundles.isEmpty ? nil : "\(model.bundles.count)")
        }
    }
}

/// One bundle's PDF, with a way to share it.
struct FilingBundleViewer: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    let model: FilingAssemblyViewModel
    let bundle: FilingBundle

    @State private var data: Data?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Group {
                if let data {
                    PDFDataView(data: data)
                        .background(theme.surface2)
                } else if let failure {
                    EmptyStateView(
                        "Could not open the bundle", systemImage: "exclamationmark.triangle",
                        message: failure, tone: .warning)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(theme.groupedBackground)
            .navigationTitle("Bundle #\(bundle.id)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if let data, let url = ShareableFile.url(
                        for: data, named: model.shareName(for: bundle)) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share")
                        .accessibilityIdentifier("filing-share-bundle")
                    }
                }
            }
            .task {
                guard data == nil else { return }
                do {
                    data = try await model.pdf(for: bundle)
                } catch {
                    failure = DisplayText.message(for: error)
                }
            }
        }
        .accessibilityIdentifier("filing-bundle-viewer")
    }
}
