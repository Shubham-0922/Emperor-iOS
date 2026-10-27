import Foundation

extension Session {
    /// Fetch Orders: a case read from its court, saved nowhere. Stateless, so built on demand.
    var fetchOrders: FetchOrdersService { FetchOrdersService(client: client) }

    /// The signed-in account's recent lookups, kept in the response cache's store so that
    /// signing out forgets them with the rest.
    var lookupHistory: LookupHistory {
        var userID = ""
        if case .signedIn(let user) = state { userID = String(user.id) }
        return LookupHistory(store: cache.store, userID: userID)
    }
}
