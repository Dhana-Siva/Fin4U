import SwiftUI
import SwiftData

/// Check and correct what was read from the receipt, then save it. Also
/// used to edit an already-saved expense (the draft is initialised from it).
struct ReviewView: View {
    @Bindable var draft: ExpenseDraft
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Person.name) private var people: [Person]
    @State private var showingPhoto = false
    @State private var newPersonName = ""
    @State private var splitTarget: SplitTarget?

    private enum SplitTarget: Identifiable {
        case receipt
        case item(UUID)

        var id: String {
            switch self {
            case .receipt: "receipt"
            case .item(let id): id.uuidString
            }
        }
    }

    var body: some View {
        Form {
            if !draft.checks.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Something may have been misread", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)
                        ForEach(draft.checks, id: \.self) { message in
                            Text(message).font(.footnote)
                        }
                        Text("Compare with your receipt and fix any item below. This disappears once the numbers add up.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            sharingSection

            Section("Receipt") {
                TextField("Merchant", text: $draft.merchant)
                DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                Picker("Category", selection: Binding(
                    get: { draft.category },
                    set: { draft.setCategoryForAll($0) }
                )) {
                    ForEach(ExpenseCategory.allCases) { category in
                        Label(category.title, systemImage: category.symbol).tag(category)
                    }
                }
            }

            Section {
                ForEach($draft.items) { $item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            TextField("Item", text: $item.name)
                            if item.quantity > 1 {
                                Text("×\(item.quantity)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            CentsField(cents: $item.cents)
                                .frame(width: 84)
                        }
                        HStack(spacing: 8) {
                            categoryChip($item.category)
                            if draft.plan.isShared {
                                splitChip(for: item)
                            }
                        }
                    }
                }
                .onDelete { draft.items.remove(atOffsets: $0) }

                Button {
                    draft.items.append(DraftItem(name: "", quantity: 1, cents: 0, category: draft.category))
                } label: {
                    Label("Add item", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Items")
            } footer: {
                Text(draft.plan.isShared
                     ? "Tap an item's category or split to change it."
                     : "Tap an item's category to change it, for example vitamins on a grocery receipt.")
            }

            Section("Totals") {
                totalRow("Subtotal", draft.subtotalCents)
                HStack {
                    Text("Tax")
                    Spacer()
                    CentsField(cents: $draft.taxCents).frame(width: 100)
                }
                HStack {
                    Text("Tip / service")
                    Spacer()
                    CentsField(cents: $draft.tipCents).frame(width: 100)
                }
                totalRow("Total", draft.totalCents, bold: true)
            }

            if draft.plan.isShared {
                Section {
                    ForEach(draft.personTotals) { person in
                        totalRow(person.name, person.cents)
                    }
                } header: {
                    Text("Who owes what")
                } footer: {
                    Text("Tax and tip are shared in proportion to each person's items. Only your share counts toward your monthly total.")
                }
            }

            if draft.printedTotalCents > 0 {
                Section {
                    Text("The receipt itself says: subtotal \(Money.format(draft.printedSubtotalCents, currency: draft.currency)), total \(Money.format(draft.printedTotalCents, currency: draft.currency)).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !draft.notes.isEmpty {
                Section("Notes") {
                    ForEach(Array(draft.notes.enumerated()), id: \.offset) { _, note in
                        Text(note).font(.footnote)
                    }
                }
            }

            if let data = draft.receiptImage, let image = UIImage(data: data) {
                Section("Receipt photo") {
                    Button { showingPhoto = true } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(draft.existing == nil ? "Review" : "Edit expense")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onClose)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    draft.save(in: context)
                    try? context.save()
                    onClose()
                }
                .disabled(!draft.canSave)
            }
        }
        .sheet(item: $splitTarget) { target in
            splitEditor(for: target)
        }
        .sheet(isPresented: $showingPhoto) {
            if let data = draft.receiptImage, let image = UIImage(data: data) {
                NavigationStack {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image).resizable().scaledToFit()
                    }
                    .navigationTitle("Receipt photo")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingPhoto = false }
                        }
                    }
                }
            }
        }
    }

    // MARK: Sharing

    private var sharingSection: some View {
        Section {
            Toggle(isOn: $draft.plan.isShared.animation()) {
                Label("Shared expense", systemImage: "person.2.fill")
            }

            if draft.plan.isShared {
                ForEach(people) { person in
                    Button {
                        draft.plan.toggle(person.participant)
                    } label: {
                        HStack {
                            Text(person.name).foregroundStyle(.primary)
                            Spacer()
                            if draft.plan.isParticipating(person.participant) {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
                .onDelete(perform: deletePeople)

                HStack {
                    TextField("Add a person", text: $newPersonName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(addPerson)
                    Button("Add", action: addPerson)
                        .disabled(newPersonName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.borderless)
                }

                if !draft.plan.participants.isEmpty {
                    Button {
                        splitTarget = .receipt
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Default split").foregroundStyle(.primary)
                                Text(ExpenseMath.describe(draft.plan.defaultSplit))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        } footer: {
            if draft.plan.isShared {
                Text(draft.plan.participants.isEmpty
                     ? "Add the people you're splitting with and tick them. Swipe a name to remove it."
                     : "Everything is split by the default unless you change an item's split.")
            } else {
                Text("Turn on to split this receipt with roommates or friends.")
            }
        }
    }

    private func addPerson() {
        let name = newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        newPersonName = ""
        if let existing = people.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            if !draft.plan.isParticipating(existing.participant) { draft.plan.toggle(existing.participant) }
            return
        }
        let person = Person(name: name)
        context.insert(person)
        try? context.save()
        draft.plan.toggle(person.participant)
    }

    private func deletePeople(at offsets: IndexSet) {
        for index in offsets {
            let person = people[index]
            if draft.plan.isParticipating(person.participant) { draft.plan.toggle(person.participant) }
            context.delete(person)
        }
        try? context.save()
    }

    private func categoryChip(_ category: Binding<ExpenseCategory>) -> some View {
        Menu {
            Picker("Category", selection: category) {
                ForEach(ExpenseCategory.allCases) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
        } label: {
            chip(category.wrappedValue.title, symbol: category.wrappedValue.symbol, tint: category.wrappedValue.color)
        }
        .buttonStyle(.borderless)
    }

    private func splitChip(for item: DraftItem) -> some View {
        Button {
            splitTarget = .item(item.id)
        } label: {
            chip(
                ExpenseMath.describe(draft.split(for: item)),
                symbol: "person.2.fill",
                tint: item.split == nil ? .secondary : .accentColor
            )
        }
        .buttonStyle(.borderless)
    }

    private func chip(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func splitEditor(for target: SplitTarget) -> some View {
        switch target {
        case .receipt:
            SplitEditorView(
                title: "Default split",
                subtitle: "Applies to every item that doesn't have its own split.",
                everyone: draft.plan.everyone,
                current: draft.plan.defaultSplit,
                canUseDefault: false
            ) { entries in
                draft.plan.customDefault = entries
            }
        case .item(let id):
            if let index = draft.items.firstIndex(where: { $0.id == id }) {
                SplitEditorView(
                    title: draft.items[index].name.isEmpty ? "Item split" : draft.items[index].name,
                    subtitle: "Who shares this item, and how much each pays.",
                    everyone: draft.plan.everyone,
                    current: draft.split(for: draft.items[index]),
                    canUseDefault: true
                ) { entries in
                    // An override identical to the default is just the default.
                    draft.items[index].split = entries == draft.plan.defaultSplit ? nil : entries
                }
            }
        }
    }

    private func totalRow(_ title: String, _ cents: Int, bold: Bool = false) -> some View {
        HStack {
            Text(title).fontWeight(bold ? .bold : .regular)
            Spacer()
            Text(Money.format(cents, currency: draft.currency))
                .fontWeight(bold ? .bold : .regular)
                .monospacedDigit()
        }
    }
}
