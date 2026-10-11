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
                            Spacer(minLength: 4)
                            if let other = draft.plan.other {
                                shareColumn(
                                    name: other.name,
                                    basisPoints: Binding(
                                        get: { draft.otherShare(of: item) },
                                        set: { draft.setOtherShare($0, of: item.id) }
                                    )
                                )
                            }
                        }
                        if let other = draft.plan.other {
                            splitBreakdown(for: item, otherName: other.name)
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
                if let other = draft.plan.other {
                    Text("The % on each item is how much \(other.name) pays of it. Tap a category to change it.")
                } else {
                    Text("Tap an item's category to change it, for example vitamins on a grocery receipt.")
                }
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
                        draft.plan.selectOnly(person.participant)
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

                if let other = draft.plan.other {
                    HStack {
                        Text("\(other.name) pays, by default")
                        Spacer()
                        percentField(Binding(
                            get: { draft.defaultOtherShare },
                            set: { draft.setDefaultOtherShare($0) }
                        ))
                    }
                }
            }
        } footer: {
            if draft.plan.isShared {
                Text(draft.plan.other == nil
                     ? "Tick the person you're splitting with, or add them. Swipe a name to remove it."
                     : "Applies to every item. Change the % on an item below to override it.")
            } else {
                Text("Turn on to split this receipt with a roommate or friend.")
            }
        }
    }

    private func addPerson() {
        let name = newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        newPersonName = ""
        if let existing = people.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            if !draft.plan.isParticipating(existing.participant) { draft.plan.selectOnly(existing.participant) }
            return
        }
        let person = Person(name: name)
        context.insert(person)
        try? context.save()
        draft.plan.selectOnly(person.participant)
    }

    private func deletePeople(at offsets: IndexSet) {
        for index in offsets {
            let person = people[index]
            if draft.plan.isParticipating(person.participant) { draft.plan.selectOnly(person.participant) }
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

    /// "You $4.00 + Daya $1.00 = $5.00" -- the percentages in actual money.
    private func splitBreakdown(for item: DraftItem, otherName: String) -> some View {
        let amounts = draft.amounts(of: item)
        let money = { Money.format($0, currency: draft.currency) }
        return Text("You \(money(amounts.you)) + \(otherName) \(money(amounts.other)) = \(money(item.cents))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// "Sam  [ 50.00 ] %" -- who the item is shared with and their share.
    private func shareColumn(name: String, basisPoints: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            percentField(basisPoints)
        }
    }

    private func percentField(_ basisPoints: Binding<Int>) -> some View {
        // CentsField works in hundredths, which is exactly basis points:
        // 5000 -> "50.00".
        HStack(spacing: 2) {
            CentsField(cents: Binding(
                get: { basisPoints.wrappedValue },
                set: { basisPoints.wrappedValue = min(max($0, 0), ExpenseMath.whole) }
            ))
            .frame(width: 64)
            .font(.footnote)
            Text("%").font(.footnote).foregroundStyle(.secondary)
        }
        // Without this the "%" is the first thing a tight form row squeezes out.
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
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
