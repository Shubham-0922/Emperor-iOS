import Foundation

extension Session {
    /// The matter writes, on the same authenticated client as the reads.
    var projectWrites: ProjectWriteService { ProjectWriteService(client: client) }
}
