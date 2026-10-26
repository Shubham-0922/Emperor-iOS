import Foundation

/// The matter's setup checklist — the web's `SetupStrip` (`setupSteps`): six things a matter
/// needs before it runs itself, each done, not done, or not yet knowable.
enum MatterSetup {

    struct Step: Equatable, Identifiable, Sendable {
        let key: String
        let label: String
        let short: String
        /// `nil` while it cannot be known — the documents, before their count is in.
        let done: Bool?
        var id: String { key }

        /// What the step asks for, as the web's chip title says it.
        var hint: String { MatterSetup.hints[key] ?? label }
    }

    static let hints: [String: String] = [
        "court": "Find the case in court records, or mark the matter as not filed yet",
        "side": "Which side you act for",
        "parties": "The client and the opposite party",
        "practice": "Set the practice area",
        "documents": "Attach the matter’s documents from My Files",
        "contact": "Add your client’s phone number or email",
    ]

    /// The six steps, in the web's order. `fileCount` is nil when the matter's files have not
    /// been counted.
    static func steps(project: Project, people: [ProjectPerson], fileCount: Int?) -> [Step] {
        func has(_ v: String?) -> Bool { !(v ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let clientReachable = people.contains { $0.role == "client" && (has($0.phone) || has($0.email)) }
        return [
            Step(key: "court", label: "Court case", short: "Court case",
                 done: !(project.linkedCaseID ?? "").isEmpty || project.courtStatus == "not_filed"),
            Step(key: "side", label: "Your side", short: "Your side", done: has(project.ourSide)),
            Step(key: "parties", label: "Client & opposite party", short: "Parties",
                 done: has(project.client) && has(project.oppositeParty)),
            Step(key: "practice", label: "Practice area", short: "Practice area", done: has(project.practiceArea)),
            Step(key: "documents", label: "Documents", short: "Documents", done: fileCount.map { $0 > 0 }),
            Step(key: "contact", label: "Client contact", short: "Contact", done: clientReachable),
        ]
    }

    /// `Math.round(done / steps * 100)`: the share of steps known to be done.
    static func percent(_ steps: [Step]) -> Int {
        guard !steps.isEmpty else { return 0 }
        let done = steps.filter { $0.done == true }.count
        return Int((Double(done) / Double(steps.count) * 100).rounded())
    }
}
