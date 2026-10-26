import Foundation

/// What the reader has done to a Doc Index on screen: the search, the filter chip, the sort, the
/// hidden columns and the row spacing. The CSV is of exactly this view (`DocIndexPage.jsx`).
struct DocIndexViewState: Equatable, Sendable {
    var query = ""
    var filter: String?
    var sortKey: String?
    var descending = false
    var hidden: Set<String> = []
    var compact = false

    /// Ascending, then descending, then unsorted, as a header tap goes.
    mutating func toggleSort(_ key: String) {
        if sortKey != key {
            sortKey = key
            descending = false
        } else if !descending {
            descending = true
        } else {
            sortKey = nil
            descending = false
        }
    }

    /// Sets the sort from a menu: a column and a direction, or no sort.
    mutating func sort(_ key: String?, descending: Bool) {
        sortKey = key
        self.descending = key == nil ? false : descending
    }

    /// Hides or shows a column; the last column shown stays.
    mutating func toggleColumn(_ key: String, in index: DocIndex) {
        if hidden.contains(key) {
            hidden.remove(key)
        } else if index.columns.count - hidden.count > 1 {
            hidden.insert(key)
        }
    }

    /// A filter chip: `nil` is All; tapping the chosen one again clears it.
    mutating func toggleFilter(_ value: String?) {
        filter = (value == nil || filter == value) ? nil : value
    }

    mutating func clearSearchAndFilters() {
        query = ""
        filter = nil
    }

    func columns(_ index: DocIndex) -> [DocIndex.Column] {
        index.columns.filter { !hidden.contains($0.key) }
    }

    func rows(_ index: DocIndex) -> [DocIndex.Row] {
        index.rows(query: query, filter: filter, sortKey: sortKey, descending: descending)
    }

    var isFiltered: Bool { !AnalysisJS.trim(query).isEmpty || filter != nil }

    /// "Showing 3 of 18 documents".
    func showingLine(_ index: DocIndex) -> String {
        "Showing \(rows(index).count) of \(index.rows.count) documents"
    }

    func csv(_ index: DocIndex) -> String {
        DocIndex.toCSV(columns: columns(index), rows: rows(index))
    }
}

/// What the reader has done to a List of Dates on screen: the category chip and the search. Copy
/// and the Word and PDF exports are of exactly what is shown (`ListOfDatesPage.jsx`).
struct DateChartViewState: Equatable, Sendable {
    var category: DateChart.Category?
    var query = ""

    func shown(_ chart: DateChart) -> [DateChart.Entry] {
        chart.shown(category: category, query: query)
    }

    /// "4 of 26".
    func countLine(_ chart: DateChart) -> String {
        "\(shown(chart).count) of \(chart.entries.count)"
    }

    /// Makes an entry visible before the chart scrolls to it: a timeline pick that the chip or
    /// the search hides clears them. Answers whether anything was cleared.
    @discardableResult
    mutating func reveal(_ id: String, in chart: DateChart) -> Bool {
        guard !shown(chart).contains(where: { $0.id == id }) else { return false }
        category = nil
        query = ""
        return true
    }

    /// The year row an entry sits in.
    static func year(of id: String, in chart: DateChart) -> String? {
        guard let e = chart.entries.first(where: { $0.id == id }) else { return nil }
        let y = DateChart.yearOf(e.day)
        return y.isEmpty ? "Undated" : y
    }

    /// The count on a chip: every entry for All, else the category's.
    static func count(_ category: DateChart.Category?, in chart: DateChart) -> Int {
        category.map { chart.sum[$0] } ?? chart.entries.count
    }
}
