import Foundation

extension Session {
    /// The plan's source and expiry, for the plan sheet.
    var billingAccount: BillingAccountService { BillingAccountService(client: client) }
}
