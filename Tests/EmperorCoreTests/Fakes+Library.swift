import Foundation
@testable import EmperorCore

// Moved out of `Fakes.swift` unchanged; each area's stand-ins live in a file of their own.

final class FakeLibrary: LibraryProviding, @unchecked Sendable {
    var categories: [LibraryCategory] = []
    var subFilters: [String] = []
    var pages: [[LibraryDocument]] = []
    var total = 0
    var error: Error?
    var documentData = Data("%PDF-1.4".utf8)
    private(set) var browseCalls: [(category: String, page: Int, search: String?, sort: LibrarySort)] = []

    func categories() async throws -> [LibraryCategory] {
        if let error { throw error }
        return categories
    }

    func subFilters(category: String) async throws -> [String] {
        if let error { throw error }
        return subFilters
    }

    func browse(
        category: String, subFilter: String?, search: String?,
        sort: LibrarySort, page: Int, pageSize: Int
    ) async throws -> (items: [LibraryDocument], total: Int) {
        browseCalls.append((category, page, search, sort))
        if let error { throw error }
        let index = page - 1
        return (index < pages.count ? pages[index] : [], total)
    }

    func document(id: Int) async throws -> Data {
        if let error { throw error }
        return documentData
    }
}
