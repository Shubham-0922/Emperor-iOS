import Foundation

extension Session {
    /// Opening the documents an answer cites: `/resolve-file` and `/page-words`.
    var citedSources: CitedSourceService { CitedSourceService(client: client) }
}
