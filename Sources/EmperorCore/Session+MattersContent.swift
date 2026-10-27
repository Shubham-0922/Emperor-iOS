import Foundation

extension Session {
    /// A matter's files and the writes on them, on the same authenticated client.
    var matterFiles: MatterFilesService { MatterFilesService(client: client) }

    /// Keeping a court case as a matter: tracked, made or found, and its side recorded.
    var matterCreation: MatterCreationService {
        MatterCreationService(tracking: caseTracking, writes: projectWrites, projects: projects)
    }
}
