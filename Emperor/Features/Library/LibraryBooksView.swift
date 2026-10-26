import SwiftUI

/// Books & law reports, shelved like a library: one shelf per series in volume order, the
/// standalone books, and an index of every series; "All books" is the A–Z grid
/// (`categories/BooksAndReports.jsx`).
struct LibraryBooksView: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass

    let category: LibraryCategory

    @State private var model: LibraryBooksViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.groupedBackground)
        .navigationTitle(category.displayLabel)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard model == nil else { return }
            let created = LibraryBooksViewModel(service: session.library)
            model = created
            await created.load()
        }
    }

    private var coverWidth: CGFloat { sizeClass == .regular ? 132 : 104 }

    private func content(_ model: LibraryBooksViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SerifHeader(
                    title: category.displayLabel,
                    subtitle: [category.count.map { "\(LibraryDisplay.fmtCount($0)) volumes." },
                               "Law reports and journals stand together by series, in volume order."]
                        .compactMap { $0 }.joined(separator: " "))
                    .padding(.horizontal, Spacing.gutter)

                NavigationLink(value: LibraryRoute.allBooks(category, query: "")) {
                    Label("All books, A–Z", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.secondaryAction)
                .padding(.horizontal, Spacing.gutter)
                .accessibilityIdentifier("library-books-all")

                if let failure = model.state.failure {
                    EmptyStateContent(title: "The shelves could not be loaded", systemImage: "exclamationmark.triangle",
                                      message: failure.message, tone: .warning) {
                        Button("Try again") { Task { await model.load() } }
                            .buttonStyle(.secondaryAction)
                    }
                } else if let shelves = model.shelves {
                    ForEach(shelves.shelves) { shelf in
                        row(title: LibraryDisplay.seriesName(shelf.series),
                            detail: LibraryBooksViewModel.shelfBlurb(shelf),
                            route: .series(shelf.series), items: shelf.items, series: shelf.series)
                    }
                    if let standalone = shelves.standalone, !standalone.items.isEmpty {
                        row(title: "Standalone books",
                            detail: LibraryBooksViewModel.standaloneBlurb,
                            route: .allBooks(category, query: ""), items: standalone.items, series: nil)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xxl)
                }

                if !model.seriesIndex.isEmpty {
                    seriesIndex(model.seriesIndex)
                }
            }
            .padding(.vertical, Spacing.lg)
        }
        .refreshable { await model.load() }
    }

    private func row(title: String, detail: String, route: LibraryRoute, items: [LibraryDoc], series: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: Spacing.sm) {
                SectionHeader(title: title)
                NavigationLink(value: route) {
                    Text("See all")
                }
                .buttonStyle(.quietAction)
                .accessibilityLabel("See all of \(title)")
            }
            .padding(.horizontal, Spacing.gutter)
            if !detail.isEmpty {
                Text(detail)
                    .font(.brand(.footnote))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, Spacing.gutter)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Spacing.md) {
                    ForEach(items) { doc in
                        LibraryDocCard(
                            doc: doc, width: coverWidth,
                            title: series.map { LibraryDisplay.volumeTitle(doc, series: $0) },
                            meta: LibraryDisplay.captionMeta(doc, withSeries: series == nil))
                    }
                }
                .padding(.horizontal, Spacing.gutter)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func seriesIndex(_ series: [LibrarySeriesFacet]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Every series", detail: "\(LibraryDisplay.fmtCount(series.count)) runs of two or more volumes")
            RecordGroup {
                ForEach(Array(series.enumerated()), id: \.element.value) { index, item in
                    if index > 0 { RecordDivider(inset: 14) }
                    NavigationLink(value: LibraryRoute.series(item.value)) {
                        RecordRow(title: LibraryDisplay.seriesName(item.value), titleLines: 2) {
                            EmptyView()
                        } trailing: {
                            HStack(spacing: Spacing.sm) {
                                if let count = item.count {
                                    Text(LibraryDisplay.fmtCount(count))
                                        .font(.brand(.caption, weight: .medium))
                                        .monospacedDigit()
                                        .foregroundStyle(theme.textTertiary)
                                }
                                RowChevron()
                            }
                        }
                    }
                    .buttonStyle(.recordRow)
                }
            }
        }
        .padding(.horizontal, Spacing.gutter)
    }
}

/// One series: every volume, grouped by decade, in volume order (`SeriesPage`).
struct LibrarySeriesView: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass

    let series: String

    @State private var model: LibrarySeriesViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.groupedBackground)
        .navigationTitle(LibraryDisplay.seriesName(series))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard model == nil else { return }
            let created = LibrarySeriesViewModel(series: series, service: session.library)
            model = created
            await created.load()
        }
    }

    private var coverWidth: CGFloat { sizeClass == .regular ? 132 : 104 }

    private func content(_ model: LibrarySeriesViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SerifHeader(eyebrow: "Series", title: model.title, subtitle: model.summary)
                    .padding(.horizontal, Spacing.gutter)
                if let failure = model.state.failure {
                    EmptyStateContent(title: "This series could not be loaded", systemImage: "exclamationmark.triangle",
                                      message: failure.message, tone: .warning) {
                        Button("Try again") { Task { await model.load() } }
                            .buttonStyle(.secondaryAction)
                    }
                } else if model.state.hasLoaded, model.volumes.isEmpty {
                    EmptyStateContent(title: "No volumes in this series", systemImage: "books.vertical",
                                      message: "The series name may have changed. Go back to the shelves.", tone: .neutral) {
                        EmptyView()
                    }
                } else if !model.state.hasLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xxl)
                } else {
                    let decades = model.decades
                    ForEach(decades) { decade in
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            if decades.count > 1 {
                                SectionHeader(title: decade.label,
                                              detail: "\(decade.items.count) vol\(decade.items.count == 1 ? "" : "s").")
                                    .padding(.horizontal, Spacing.gutter)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: coverWidth), spacing: Spacing.md, alignment: .top)],
                                      alignment: .leading, spacing: Spacing.lg) {
                                ForEach(decade.items) { doc in
                                    LibraryDocCard(doc: doc, width: coverWidth,
                                                   title: LibraryDisplay.volumeTitle(doc, series: series),
                                                   meta: LibraryDisplay.captionMeta(doc, withSeries: false, withSize: true))
                                }
                            }
                            .padding(.horizontal, Spacing.gutter)
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.lg)
        }
        .refreshable { await model.load() }
    }
}
