import SwiftUI

/// "Open as matter" on a tracked case's page — the web's `/cases/:caseId`: the user's matter for
/// the case, made now if there is none, opened on its Court section. A refusal is said in the web's
/// words, with Try again where another try could help.
struct OpenAsMatterButton: View {
    @Environment(Session.self) private var session
    @Environment(\.navigator) private var navigator

    let caseID: String

    @State private var model: CaseToMatterViewModel?

    var body: some View {
        let opening = model?.isOpening == true
        Button {
            open()
        } label: {
            if opening {
                ProgressView()
                    .accessibilityLabel(CaseToMatterViewModel.opening)
            } else {
                Label("Open as matter", systemImage: "folder")
                    .labelStyle(.titleAndIcon)
            }
        }
        .disabled(opening)
        .accessibilityIdentifier("case-open-as-matter")
        .alert(
            model?.failure?.title ?? "",
            isPresented: Binding(
                get: { model?.failure != nil },
                set: { if !$0 { clearFailure() } })
        ) {
            if model?.failure?.canRetry == true {
                Button("Try again") {
                    clearFailure()
                    open()
                }
            }
            Button("OK", role: .cancel) { clearFailure() }
        } message: {
            Text(model?.failure?.message ?? "")
        }
    }

    private func clearFailure() {
        if let model { model.failure = nil }
    }

    private func open() {
        let current = model ?? CaseToMatterViewModel(caseID: caseID, service: session.matterCreation)
        model = current
        Task {
            guard let made = await current.open() else { return }
            navigator.openMatter(made.projectID, section: CaseToMatter.section)
        }
    }
}
