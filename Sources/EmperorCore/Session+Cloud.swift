import Foundation

extension Session {
    var cloud: CloudDriveService { CloudDriveService(client: client) }
}
