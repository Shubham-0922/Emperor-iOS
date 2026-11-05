import SwiftUI

/// A small dropdown menu for filter chips — shows options with optional counts,
/// highlights the current selection with a checkmark.
struct FilterDropdown: View {
    let title: String
    let options: [(label: String, count: Int?)]
    @Binding var selected: String
    
    var body: some View {
        Menu {
            ForEach(options, id: \.label) { option in
                Button {
                    selected = option.label
                } label: {
                    HStack {
                        Text(option.label)
                        if option.label == selected {
                            Image(systemName: "checkmark")
                        }
                        if let count = option.count {
                            Text("\(count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(selected)
                Image(systemName: "chevron.down")
            }
        }
    }
}