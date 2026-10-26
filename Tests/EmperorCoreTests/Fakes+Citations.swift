import Foundation
@testable import EmperorCore

/// A stand-in for `/resolve-file` and `/page-words`: answers by file name and by page, and
/// records every question asked.
final class FakeCitedSources: CitedSourceResolving, @unchecked Sendable {
    struct Resolve: Equatable { var name: String; var quote: String?; var projectID: String? }

    private let lock = NSLock()
    /// The answer for a name; a name not listed is not found.
    var files: [String: ResolvedFile] = [:]
    var resolveError: Error?
    /// The placed words of a page, by 1-based page; a page not listed has none (`none`).
    var pages: [Int: PageWords] = [:]
    var pageWordsError: Error?
    /// Held back so a test can ask twice while the first answer is on its way.
    var delay: Duration?

    private var _resolves: [Resolve] = []
    private var _pageRequests: [(folder: String, file: String, page: Int)] = []
    var resolves: [Resolve] { lock.withLock { _resolves } }
    var pageRequests: [(folder: String, file: String, page: Int)] { lock.withLock { _pageRequests } }

    func resolve(name: String, quote: String?, projectID: String?) async throws -> ResolvedFile {
        lock.withLock { _resolves.append(Resolve(name: name, quote: quote, projectID: projectID)) }
        if let delay { try? await Task.sleep(for: delay) }
        if let resolveError { throw resolveError }
        return files[name] ?? ResolvedFile(found: false)
    }

    func pageWords(folderName: String, fileName: String, page: Int) async throws -> PageWords {
        lock.withLock { _pageRequests.append((folderName, fileName, page)) }
        if let pageWordsError { throw pageWordsError }
        return pages[page] ?? PageWords(status: .none)
    }
}

/// A found file, as `/resolve-file` answers.
func resolvedFile(
    _ name: String, folder: String = "Bakshi", page: Int? = nil, status: String? = nil
) -> ResolvedFile {
    ResolvedFile(found: true, folderName: folder, fileName: name, page: page, quoteStatusRaw: status)
}
