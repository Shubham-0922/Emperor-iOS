import Foundation

extension Session {
    var fileRoutes: FileRouteService { FileRouteService(client: client) }
}
