import Foundation

extension Session {
    /// The Limitation Landmine Radar. Stateless, so built on demand.
    var limitationRadar: LimitationRadarService { LimitationRadarService(client: client) }
}
