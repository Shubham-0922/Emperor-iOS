import SwiftUI

/// A fee billed, a payment received or an expense: the kind, the amount with its words under it —
/// the cheapest check against a slipped zero — the date, how it was paid and its reference
/// (labelled for the mode), the expense's category, what it was towards, and notes.
/// `LedgerEditor` reads the amount as the web does and refuses one over the server's ceiling.
struct LedgerEntrySheet: View {
    @Environment(\.theme) private var theme
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let projectID: String
    /// The entry to edit; nil adds one of `kind`.
    var entry: LedgerEntry?
    var kind = "fee"
    let today: String
    let onSaved: () -> Void

    @State private var model: LedgerEditor?

    var body: some View {
        Group {
            if let model {
                form(model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard model == nil else { return }
            model = LedgerEditor(projectID: projectID, entry: entry, kind: kind, today: today, writes: session.projectWrites)
        }
    }

    private func form(_ model: LedgerEditor) -> some View {
        @Bindable var model = model
        return MatterFormSheet(
            title: model.title, actionTitle: model.isEdit ? "Save" : "Add", actionID: "ledger-save",
            isSaving: model.isSaving, error: model.error,
            onCancel: { dismiss() },
            onAction: { save(model) }
        ) {
            Section {
                RecordSegmentedControl(
                    label: "Kind of entry",
                    options: MatterVocabulary.LedgerKind.allCases.map { (value: $0.rawValue, title: $0.label) },
                    selection: $model.draft.kind)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                MatterField(label: "Amount (₹)") {
                    TextField("25,000", text: $model.draft.amountText)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                        .accessibilityIdentifier("ledger-amount")
                }
                Text(model.amountHint)
                    .font(.brand(.caption))
                    .foregroundStyle(model.words.isEmpty ? theme.textTertiary : theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ledger-amount-words")
                MatterDayField(label: "Date", day: $model.draft.entryDate, allowsClear: false)
            }
            .listRowBackground(theme.surface)

            Section {
                if model.draft.kind == "payment" {
                    Picker("Paid by", selection: $model.draft.mode) {
                        ForEach(MatterVocabulary.PaymentMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                }
                if model.draft.kind == "expense" {
                    Picker("Category", selection: $model.draft.category) {
                        ForEach(MatterVocabulary.ExpenseCategory.allCases, id: \.self) { category in
                            Text(category.label).tag(category.rawValue)
                        }
                    }
                }
                if let field = model.draft.referenceField {
                    MatterField(label: field.label) {
                        TextField(field.placeholder, text: $model.draft.reference)
                            .autocorrectionDisabled()
                    }
                }
                MatterField(label: model.draft.kind == "payment" ? "Towards" : "Title") {
                    TextField(model.draft.kind == "payment" ? "Professional fees" : "Drafting and filing",
                              text: $model.draft.title)
                }
                TextField("Notes", text: $model.draft.notes, axis: .vertical)
                    .lineLimit(2...6)
                    .accessibilityLabel("Notes")
            }
            .listRowBackground(theme.surface)
        }
    }

    private func save(_ model: LedgerEditor) {
        Task {
            guard await model.save() != nil else { return }
            onSaved()
            dismiss()
        }
    }
}
