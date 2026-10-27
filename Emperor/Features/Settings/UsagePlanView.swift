import SwiftUI

/// "Usage & plan": the account's plan, its standing and this month's allowances — the screen
/// the **Usage** row on Account & Profile pushes. The body is `PlanUsageSection`, also behind
/// Home's plan pill, so both entrances read one model's answer; see that section for the
/// plans-page switch and the reloads that keep it in step.
struct UsagePlanView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        List {
            PlanUsageSection()
        }
        .font(.brand(.body))
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(theme.groupedBackground)
        .navigationTitle("Usage & plan")
        .navigationBarTitleDisplayMode(.inline)
    }
}
