import Foundation
@testable import EmperorCore

struct FakeBillingAccount: BillingAccountProviding {
    var status: BillingPlanStatus?
    var error: Error?

    func planStatus() async throws -> BillingPlanStatus? {
        if let error { throw error }
        return status
    }
}

struct FakeUsageProvider: UsageProviding {
    var usage: AccountUsage?
    var error: Error?

    func usage() async throws -> AccountUsage {
        if let error { throw error }
        return usage!
    }
}
