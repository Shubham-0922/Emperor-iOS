import Foundation

extension Session {
    /// Devil's Advocate, Doc Index and List of Dates: their jobs and their history. Stateless.
    var analysis: AnalysisService { AnalysisService(client: client) }
}
