import Foundation

extension Session {
    /// Filing assembly. Stateless, so built on demand.
    var filing: FilingService { FilingService(client: client) }
}
