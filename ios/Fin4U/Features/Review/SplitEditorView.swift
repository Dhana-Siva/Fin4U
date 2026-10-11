import SwiftUI

/// Edits who shares something and in what percentages. Used for the
/// receipt's default split and, as an override, for a single item.
/// Percentages must total exactly 100% before it can be saved.
struct SplitEditorView: View {
    let title: String
    let subtitle: String
    let everyone: [Participant]
    /// Offered only when editing one item: go back to the receipt's split.
    let canUseDefault: Bool
    /// nil means "use the receipt's default split".
    let onSave: ([ShareEntry]?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var included: Set<String>
    @State private var basisPoints: [String: Int]

    init(
        title: String,
        subtitle: String,
        everyone: [Participant],
        current: [ShareEntry],
        canUseDefault: Bool,
        onSave: @escaping ([ShareEntry]?) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.everyone = everyone
        self.canUseDefault = canUseDefault
        self.onSave = onSave
        _included = State(initialValue: Set(current.filter { $0.basisPoints > 0 }.map(\.personID)))
        _basisPoints = State(initialValue: Dictionary(uniqueKeysWithValues: current.map { ($0.personID, $0.basisPoints) }))
    }

    private var total: Int { everyone.reduce(0) { $0 + (included.contains($1.id) ? (basisPoints[$1.id] ?? 0) : 0) } }
    private var isComplete: Bool { total == ExpenseMath.whole && !included.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(everyone) { person in
                        HStack(spacing: 12) {
                            Toggle(isOn: includedBinding(person)) {
                                Text(person.name)
                            }
                            if included.contains(person.id) {
                                CentsField(cents: percentBinding(person))
                                    .frame(width: 64)
                                Text("%").foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(subtitle)
                        .textCase(nil)
                } footer: {
                    HStack {
                        Image(systemName: isComplete ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        Text(isComplete
                             ? "Adds up to 100%."
                             : "Adds up to \(ExpenseMath.percentText(total)) -- needs to be 100%.")
                    }
                    .foregroundStyle(isComplete ? Color.green : Color.orange)
                }

                Section {
                    Button("Split evenly among the ticked people") { spreadEvenly() }
                        .disabled(included.isEmpty)
                    if canUseDefault {
                        Button("Use the receipt's split") {
                            onSave(nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(everyone.compactMap { person in
                            guard included.contains(person.id), let bp = basisPoints[person.id], bp > 0 else { return nil }
                            return ShareEntry(personID: person.id, name: person.name, basisPoints: bp)
                        })
                        dismiss()
                    }
                    .disabled(!isComplete)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func includedBinding(_ person: Participant) -> Binding<Bool> {
        Binding(
            get: { included.contains(person.id) },
            set: { isOn in
                if isOn { included.insert(person.id) } else { included.remove(person.id) }
                spreadEvenly()
            }
        )
    }

    private func percentBinding(_ person: Participant) -> Binding<Int> {
        Binding(
            get: { basisPoints[person.id] ?? 0 },
            set: { basisPoints[person.id] = $0 }
        )
    }

    /// Ticking or unticking someone re-spreads evenly; the percentages can
    /// then be nudged by hand.
    private func spreadEvenly() {
        let people = everyone.filter { included.contains($0.id) }
        let shares = ExpenseMath.allocate(ExpenseMath.whole, weights: Array(repeating: 1, count: people.count))
        for person in everyone { basisPoints[person.id] = 0 }
        for (person, share) in zip(people, shares) { basisPoints[person.id] = share }
    }
}
